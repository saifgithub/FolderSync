import Foundation

// MARK: - SyncResult

struct SyncResult {
    var copied:    [(relativePath: String, from: SyncSide)] = []
    var deleted:   [(relativePath: String, side: SyncSide)] = []
    var backedUp:  [BackupRecord] = []
    var clashes:   [FileDiff] = []     // left untouched, require user action
    var errors:    [(relativePath: String, error: Error)] = []

    var totalChanges: Int { copied.count + deleted.count }
}

// MARK: - SyncOptions

struct SyncOptions {
    /// When true, copy the newer file over the older one for .updated diffs.
    var syncUpdated: Bool = true
    /// When true, propagate .new files to the other side.
    var syncNew: Bool = true
    /// When true, delete files from the other side that were deleted from one side.
    var syncDeleted: Bool = true
    /// Clashes are NEVER auto-resolved; this flag is informational.
    var skipClashes: Bool = true
    /// Back up before overwriting (requires pair.backupEnabled).
    var useBackup: Bool = true
}

// MARK: - SyncManager

/// Orchestrates a full sync pass for a single `SyncPair`.
/// Run off the main thread — all UI updates happen via the completion handler on the main thread.
final class SyncManager {

    // MARK: - Dependencies
    private let diffEngine    = DiffEngine()
    private let scanner       = FileScanner()
    private let fileOperator  = FileOperator()
    private let backupManager = BackupManager()

    // MARK: - Observation / progress callback
    var onProgress: ((String) -> Void)?
    /// Fired on the main thread immediately before a file copy begins.
    /// `direction` is the side being copied FROM (i.e. the newer/source side).
    var onFileCopy: ((String, SyncSide) -> Void)?

    // MARK: - Public API

    /// Performs a full diff + sync pass.
    /// - Parameters:
    ///   - pair:    The sync pair to process.
    ///   - options: Which classes of change to act on.
    ///   - diffs:   Pre-computed diffs (pass nil to compute fresh scan + diff).
    /// - Returns: A `SyncResult` describing what happened.
    func sync(pair: SyncPair, options: SyncOptions = SyncOptions(), diffs: [FileDiff]? = nil) throws -> SyncResult {

        guard let pairId = pair.id else { throw SyncError.invalidPair }
        let syncWallStart = CFAbsoluteTimeGetCurrent()

        progress("Loading exclusion rules…")
        let t0excl = CFAbsoluteTimeGetCurrent()
        let exclusions = try DatabaseManager.shared.read { db in
            try ExclusionRule.filter(sql: "pairId = \(pairId)").fetchAll(db)
        }
        let tExclusionsRead = CFAbsoluteTimeGetCurrent() - t0excl

        // ── 1. Scan (only when no pre-computed diffs provided) ───────────────
        let activeDiffs: [FileDiff]
        var freshLeftScan:  [String: ScannedFile]? = nil
        var freshRightScan: [String: ScannedFile]? = nil

        if let precomputed = diffs {
            activeDiffs = precomputed
        } else {
            progress("Scanning left folder…")
            let leftScan = try scanner.scan(
                rootURL: URL(fileURLWithPath: pair.leftPath),
                exclusionRules: exclusions,
                checksumEnabled: pair.checksumEnabled
            )

            progress("Scanning right folder…")
            let rightScan = try scanner.scan(
                rootURL: URL(fileURLWithPath: pair.rightPath),
                exclusionRules: exclusions,
                checksumEnabled: pair.checksumEnabled
            )

            freshLeftScan  = leftScan
            freshRightScan = rightScan

            progress("Comparing with last snapshot…")
            let snapshots = try DatabaseManager.shared.read { db in
                try TrackedFile.filter(sql: "pairId = \(pairId)").fetchAll(db)
            }

            activeDiffs = diffEngine.diff(
                leftScan: leftScan,
                rightScan: rightScan,
                snapshots: snapshots,
                checksumEnabled: pair.checksumEnabled
            )
        }

        // ── 2. Process diffs ─────────────────────────────────────────────────
        var result = SyncResult()
        let leftRoot  = URL(fileURLWithPath: pair.leftPath)
        let rightRoot = URL(fileURLWithPath: pair.rightPath)
        let t0ops = CFAbsoluteTimeGetCurrent()

        for diff in activeDiffs {
            do {
                try processDiff(
                    diff:       diff,
                    pair:       pair,
                    options:    options,
                    leftRoot:   leftRoot,
                    rightRoot:  rightRoot,
                    result:     &result
                )
            } catch {
                result.errors.append((relativePath: diff.relativePath, error: error))
            }
        }
        let tFileOps = CFAbsoluteTimeGetCurrent() - t0ops

        // ── 3. Update DB snapshot (reuse fresh scans when available) ─────────
        progress("Updating sync snapshot…")
        let t0snap = CFAbsoluteTimeGetCurrent()
        if var l = freshLeftScan, var r = freshRightScan {
            for item in result.copied {
                if item.from == .left {
                    if let lf = l[item.relativePath] {
                        r[item.relativePath] = ScannedFile(
                            relativePath: item.relativePath,
                            absoluteURL:  rightRoot.appendingPathComponent(item.relativePath),
                            sizeBytes:    lf.sizeBytes,
                            modifiedAt:   lf.modifiedAt,
                            checksum:     lf.checksum
                        )
                    }
                } else {
                    if let rf = r[item.relativePath] {
                        l[item.relativePath] = ScannedFile(
                            relativePath: item.relativePath,
                            absoluteURL:  leftRoot.appendingPathComponent(item.relativePath),
                            sizeBytes:    rf.sizeBytes,
                            modifiedAt:   rf.modifiedAt,
                            checksum:     rf.checksum
                        )
                    }
                }
            }
            for item in result.deleted {
                l.removeValue(forKey: item.relativePath)
                r.removeValue(forKey: item.relativePath)
            }
            try updateSnapshot(pair: pair, leftScan: l, rightScan: r)
        } else {
            try updateSnapshot(pair: pair, exclusions: exclusions)
        }
        let tSnapshotWrite = CFAbsoluteTimeGetCurrent() - t0snap

        // ── 4. Update lastSyncedAt on pair ───────────────────────────────────
        let t0ts = CFAbsoluteTimeGetCurrent()
        try DatabaseManager.shared.write { db in
            var mutablePair = pair
            mutablePair.lastSyncedAt = Date()
            try mutablePair.update(db)
        }
        let tTimestampWrite = CFAbsoluteTimeGetCurrent() - t0ts

        let tSyncWall = CFAbsoluteTimeGetCurrent() - syncWallStart
        func ms(_ s: Double) -> String { String(format: "%.0f ms", s * 1000) }
        let lines: [(String, String)] = [
            ("DB read:  exclusion rules",                     ms(tExclusionsRead)),
            ("File operations (\(result.totalChanges) copied/deleted)", ms(tFileOps)),
            ("DB write: snapshot update",                     ms(tSnapshotWrite)),
            ("DB write: lastSyncedAt timestamp",              ms(tTimestampWrite)),
            ("──────────────────────────────────────────", "─────────"),
            ("TOTAL sync wall time",                          ms(tSyncWall))
        ]
        let colW = lines.map(\.0.count).max() ?? 0
        let table = lines.map { l, v in l.padding(toLength: colW, withPad: " ", startingAt: 0) + "    " + v }.joined(separator: "\n")
        print("\n[Sync Timing Report]\n\(table)\n")
        progress("Done — \(result.totalChanges) change(s), \(result.clashes.count) clash(es), \(result.errors.count) error(s).")
        return result
    }

    // MARK: - Diff processing

    private func processDiff(
        diff: FileDiff,
        pair: SyncPair,
        options: SyncOptions,
        leftRoot: URL,
        rightRoot: URL,
        result: inout SyncResult
    ) throws {

        let relPath = diff.relativePath

        switch diff.status {

        case .same, .excluded:
            break // nothing to do

        case .new(let side):
            guard options.syncNew else { break }
            // Safety check: destination must still be absent — if it appeared since
            // the scan the situation is now a clash.
            guard safetyCheck(diff: diff, leftRoot: leftRoot, rightRoot: rightRoot) else {
                progress("⚠️  \(relPath): destination appeared after scan — skipping (now a clash)")
                result.clashes.append(upgradedToClash(diff))
                break
            }
            progress("Copying new file: \(relPath) (\(side.displayName) → \(side.opposite.displayName))")
            fileCopy(relPath, side)
            let (src, dst) = urls(for: relPath, newFileSide: side, leftRoot: leftRoot, rightRoot: rightRoot)
            try fileOperator.copy(from: src, to: dst)
            result.copied.append((relativePath: relPath, from: side))

        case .updated(let newerSide):
            guard options.syncUpdated else { break }
            // Safety check: destination must still match what we scanned — if it
            // changed in the meantime both sides are now modified, i.e. a clash.
            guard safetyCheck(diff: diff, leftRoot: leftRoot, rightRoot: rightRoot) else {
                progress("⚠️  \(relPath): destination changed after scan — skipping (now a clash)")
                result.clashes.append(upgradedToClash(diff))
                break
            }
            progress("Syncing update: \(relPath) (\(newerSide.displayName) is newer)")
            fileCopy(relPath, newerSide)
            let (src, dst) = urls(for: relPath, newFileSide: newerSide, leftRoot: leftRoot, rightRoot: rightRoot)
            if options.useBackup && pair.backupEnabled {
                if FileManager.default.fileExists(atPath: dst.path) {
                    let backupRecord = try backupManager.backup(
                        sourceURL: dst,
                        relativePath: relPath,
                        side: newerSide.opposite,
                        pair: pair
                    )
                    result.backedUp.append(backupRecord)
                }
            }
            try fileOperator.copy(from: src, to: dst)
            result.copied.append((relativePath: relPath, from: newerSide))

        case .deleted(let deletedFrom):
            guard options.syncDeleted else { break }
            let survivingSide = deletedFrom.opposite
            let fileToDelete  = url(for: relPath, side: survivingSide, leftRoot: leftRoot, rightRoot: rightRoot)
            progress("Removing deleted file: \(relPath) (from \(survivingSide.displayName))")
            if options.useBackup && pair.backupEnabled {
                if FileManager.default.fileExists(atPath: fileToDelete.path) {
                    let backupRecord = try backupManager.backup(
                        sourceURL: fileToDelete,
                        relativePath: relPath,
                        side: survivingSide,
                        pair: pair
                    )
                    result.backedUp.append(backupRecord)
                }
            } else {
                try fileOperator.trash(fileURL: fileToDelete)
            }
            result.deleted.append((relativePath: relPath, side: survivingSide))

        case .clash:
            // Never auto-resolve — add to clashes list for user action
            result.clashes.append(diff)
        }
    }

    // MARK: - Snapshot update

    /// Writes a fresh snapshot from pre-built scan maps (no disk re-scan needed).
    private func updateSnapshot(pair: SyncPair, leftScan: [String: ScannedFile], rightScan: [String: ScannedFile]) throws {
        guard let pairId = pair.id else { return }
        try DatabaseManager.shared.write { db in
            try TrackedFile.filter(sql: "pairId = \(pairId)").deleteAll(db)
            let now = Date()
            for (relPath, file) in leftScan {
                var tf = TrackedFile(pairId: pairId, relativePath: relPath, side: .left,  sizeBytes: file.sizeBytes, modifiedAt: file.modifiedAt, checksum: file.checksum, syncedAt: now)
                try tf.insert(db)
            }
            for (relPath, file) in rightScan {
                var tf = TrackedFile(pairId: pairId, relativePath: relPath, side: .right, sizeBytes: file.sizeBytes, modifiedAt: file.modifiedAt, checksum: file.checksum, syncedAt: now)
                try tf.insert(db)
            }
        }
    }

    /// Fallback: re-scans both sides then writes the snapshot.
    /// Used only when no pre-built scan maps are available.
    private func updateSnapshot(pair: SyncPair, exclusions: [ExclusionRule]) throws {
        guard pair.id != nil else { return }
        let leftScan  = try scanner.scan(rootURL: URL(fileURLWithPath: pair.leftPath),  exclusionRules: exclusions, checksumEnabled: pair.checksumEnabled)
        let rightScan = try scanner.scan(rootURL: URL(fileURLWithPath: pair.rightPath), exclusionRules: exclusions, checksumEnabled: pair.checksumEnabled)
        try updateSnapshot(pair: pair, leftScan: leftScan, rightScan: rightScan)
    }

    /// Updates snapshot rows for only a specific set of paths — used by incremental sync.
    private func updateSnapshotForPaths(
        pair: SyncPair,
        paths: Set<String>,
        leftScan: [String: ScannedFile],
        rightScan: [String: ScannedFile]
    ) throws {
        guard let pairId = pair.id else { return }
        guard !paths.isEmpty else { return }
        let pathList = paths
            .map { $0.replacingOccurrences(of: "'", with: "''") }
            .map { "'\($0)'" }
            .joined(separator: ",")
        try DatabaseManager.shared.write { db in
            try db.execute(sql: "DELETE FROM tracked_files WHERE pairId = \(pairId) AND relativePath IN (\(pathList))")
            let now = Date()
            for path in paths {
                if let file = leftScan[path] {
                    var tf = TrackedFile(pairId: pairId, relativePath: path, side: .left,  sizeBytes: file.sizeBytes, modifiedAt: file.modifiedAt, checksum: file.checksum, syncedAt: now)
                    try tf.insert(db)
                }
                if let file = rightScan[path] {
                    var tf = TrackedFile(pairId: pairId, relativePath: path, side: .right, sizeBytes: file.sizeBytes, modifiedAt: file.modifiedAt, checksum: file.checksum, syncedAt: now)
                    try tf.insert(db)
                }
            }
        }
    }

    // MARK: - Incremental sync (used by real-time FSEvent mode)

    /// Performs a targeted sync for a specific set of changed URLs reported by FSEvents.
    /// Only re-scans the files that changed — much faster than a full sync for large pairs.
    func syncIncremental(pair: SyncPair, changedURLs: [URL], options: SyncOptions = SyncOptions()) throws -> SyncResult {
        guard let pairId = pair.id else { throw SyncError.invalidPair }

        let exclusions = try DatabaseManager.shared.read { db in
            try ExclusionRule.filter(sql: "pairId = \(pairId)").fetchAll(db)
        }

        let leftRoot      = URL(fileURLWithPath: pair.leftPath)
        let rightRoot     = URL(fileURLWithPath: pair.rightPath)
        let leftRootPath  = leftRoot.path
        let rightRootPath = rightRoot.path

        // Split reported URLs by side
        let leftURLs  = changedURLs.filter { $0.path.hasPrefix(leftRootPath) }
        let rightURLs = changedURLs.filter { $0.path.hasPrefix(rightRootPath) }

        // Compute the set of relative paths that were touched
        var changedRelPaths = Set<String>()
        for url in leftURLs {
            let rel = String(url.path.dropFirst(leftRootPath.count))
            let path = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
            if !path.isEmpty { changedRelPaths.insert(path) }
        }
        for url in rightURLs {
            let rel = String(url.path.dropFirst(rightRootPath.count))
            let path = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
            if !path.isEmpty { changedRelPaths.insert(path) }
        }

        guard !changedRelPaths.isEmpty else { return SyncResult() }

        // Scan only the changed files on each side
        let leftScan  = scanner.scanFiles(leftURLs,  rootURL: leftRoot,  exclusionRules: exclusions, checksumEnabled: false)
        let rightScan = scanner.scanFiles(rightURLs, rootURL: rightRoot, exclusionRules: exclusions, checksumEnabled: false)

        // Load snapshots only for the affected paths
        let pathList = changedRelPaths
            .map { $0.replacingOccurrences(of: "'", with: "''") }
            .map { "'\($0)'" }
            .joined(separator: ",")
        let snapshots = try DatabaseManager.shared.read { db in
            try TrackedFile.filter(sql: "pairId = \(pairId) AND relativePath IN (\(pathList))").fetchAll(db)
        }

        let diffs = diffEngine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: false)
        let actionable = diffs.filter { if case .same = $0.status { return false }; if case .excluded = $0.status { return false }; return true }
        guard !actionable.isEmpty else { return SyncResult() }

        var result = SyncResult()
        for diff in actionable {
            do { try processDiff(diff: diff, pair: pair, options: options, leftRoot: leftRoot, rightRoot: rightRoot, result: &result) }
            catch { result.errors.append((relativePath: diff.relativePath, error: error)) }
        }

        // Derive post-sync state and write partial snapshot update
        var updatedLeft  = leftScan
        var updatedRight = rightScan
        for item in result.copied {
            if item.from == .left, let lf = updatedLeft[item.relativePath] {
                updatedRight[item.relativePath] = ScannedFile(relativePath: item.relativePath, absoluteURL: rightRoot.appendingPathComponent(item.relativePath), sizeBytes: lf.sizeBytes, modifiedAt: lf.modifiedAt, checksum: nil)
            } else if item.from == .right, let rf = updatedRight[item.relativePath] {
                updatedLeft[item.relativePath]  = ScannedFile(relativePath: item.relativePath, absoluteURL: leftRoot.appendingPathComponent(item.relativePath),  sizeBytes: rf.sizeBytes, modifiedAt: rf.modifiedAt, checksum: nil)
            }
        }
        for item in result.deleted {
            updatedLeft.removeValue(forKey: item.relativePath)
            updatedRight.removeValue(forKey: item.relativePath)
        }
        try updateSnapshotForPaths(pair: pair, paths: changedRelPaths, leftScan: updatedLeft, rightScan: updatedRight)

        try DatabaseManager.shared.write { db in
            var mutablePair = pair
            mutablePair.lastSyncedAt = Date()
            try mutablePair.update(db)
        }
        progress("Real-time sync — \(result.totalChanges) change(s), \(result.clashes.count) clash(es).")
        return result
    }

    // MARK: - Pre-copy safety check

    /// Returns `true` if it is still safe to proceed with the copy described by `diff`.
    /// Re-stats the destination file on disk right before writing to catch races where
    /// the destination was modified after the diff was computed.
    ///
    /// - `.new(side)`:      destination must still be absent.
    /// - `.updated(newer)`: destination must still match the size + mod-date we recorded
    ///                      in the diff scan; if it drifted, both sides are now modified.
    private func safetyCheck(diff: FileDiff, leftRoot: URL, rightRoot: URL) -> Bool {
        let fm = FileManager.default
        switch diff.status {

        case .new(let side):
            let dstURL = url(for: diff.relativePath, side: side.opposite,
                             leftRoot: leftRoot, rightRoot: rightRoot)
            return !fm.fileExists(atPath: dstURL.path)

        case .updated(let newerSide):
            let dstSide   = newerSide.opposite
            let recorded  = dstSide == .left ? diff.leftFile : diff.rightFile
            guard let recorded else { return true }   // destination was absent — still fine
            let dstURL = url(for: diff.relativePath, side: dstSide,
                             leftRoot: leftRoot, rightRoot: rightRoot)
            guard let attrs = try? fm.attributesOfItem(atPath: dstURL.path) else {
                return true   // destination vanished — source copy is fine
            }
            // Coerce .size to Int64 regardless of whether the OS returns Int or Int64.
            let rawSize    = attrs[.size]
            let currentSize: Int64
            if let v = rawSize as? Int64      { currentSize = v }
            else if let v = rawSize as? Int   { currentSize = Int64(v) }
            else                              { currentSize = 0 }
            let currentMod = (attrs[.modificationDate] as? Date) ?? .distantPast
            return currentSize == recorded.sizeBytes
                && abs(currentMod.timeIntervalSince(recorded.modifiedAt)) <= 2.0

        default:
            return true
        }
    }

    /// Returns a copy of `diff` with its status upgraded to `.clash`.
    /// Used when a safety check fires — the diff data is kept intact so the
    /// user sees accurate file info in the conflict resolution sheet.
    private func upgradedToClash(_ diff: FileDiff) -> FileDiff {
        FileDiff(
            relativePath:  diff.relativePath,
            status:        .clash,
            leftFile:      diff.leftFile,
            rightFile:     diff.rightFile,
            leftSnapshot:  diff.leftSnapshot,
            rightSnapshot: diff.rightSnapshot
        )
    }

    // MARK: - URL helpers

    private func url(for relativePath: String, side: SyncSide, leftRoot: URL, rightRoot: URL) -> URL {
        (side == .left ? leftRoot : rightRoot).appendingPathComponent(relativePath)
    }

    private func urls(for relativePath: String, newFileSide: SyncSide, leftRoot: URL, rightRoot: URL) -> (src: URL, dst: URL) {
        let src = url(for: relativePath, side: newFileSide,          leftRoot: leftRoot, rightRoot: rightRoot)
        let dst = url(for: relativePath, side: newFileSide.opposite, leftRoot: leftRoot, rightRoot: rightRoot)
        return (src, dst)
    }

    // MARK: - Progress

    private func progress(_ message: String) {
        DispatchQueue.main.async { [weak self] in
            self?.onProgress?(message)
        }
    }

    private func fileCopy(_ path: String, _ direction: SyncSide) {
        DispatchQueue.main.async { [weak self] in
            self?.onFileCopy?(path, direction)
        }
    }

    // MARK: - Errors
    enum SyncError: LocalizedError {
        case invalidPair
        var errorDescription: String? { "Sync pair is missing an ID — save it first." }
    }
}
