import Foundation

// MARK: - DiffStatus

/// The computed status of a single relative path after comparing both sides + the DB snapshot.
enum DiffStatus: Equatable {
    /// File exists on both sides and matches (same checksum or same size+modDate).
    case same
    /// File is new on one side — not present on the other side AND not in last-sync snapshot.
    case new(SyncSide)
    /// File was in the DB snapshot but is now missing from one side (deleted).
    case deleted(SyncSide)
    /// Modified on one side only since last sync; the `newer` side carries the update.
    case updated(newer: SyncSide)
    /// Modified on BOTH sides since last sync — requires user intervention.
    case clash
    /// File is excluded by an exclusion rule.
    case excluded
}

// MARK: - FileDiff

/// Diff result for one relative path within a sync pair.
struct FileDiff: Identifiable {
    var id: String { relativePath }
    let relativePath: String
    let status: DiffStatus
    let leftFile: ScannedFile?      // nil if absent on left
    let rightFile: ScannedFile?     // nil if absent on right
    let leftSnapshot: TrackedFile?  // last recorded state on left (from DB)
    let rightSnapshot: TrackedFile? // last recorded state on right (from DB)
}

// MARK: - DiffEngine

/// Compares live filesystem scans against the DB snapshot to produce a `FileDiff` per path.
final class DiffEngine {

    // MARK: - Public API

    /// Runs a full diff for a sync pair.
    /// - Parameters:
    ///   - leftScan:   Result from `FileScanner.scan` for the left folder.
    ///   - rightScan:  Result from `FileScanner.scan` for the right folder.
    ///   - snapshots:  All `TrackedFile` rows for this pair from the DB.
    ///   - checksumEnabled: Use checksum comparison when available.
    /// - Returns: Array of `FileDiff`, one per unique relative path encountered.
    func diff(
        leftScan: [String: ScannedFile],
        rightScan: [String: ScannedFile],
        snapshots: [TrackedFile],
        checksumEnabled: Bool
    ) -> [FileDiff] {

        // Build snapshot lookup
        var leftSnap:  [String: TrackedFile] = [:]
        var rightSnap: [String: TrackedFile] = [:]
        for snap in snapshots {
            switch snap.side {
            case .left:  leftSnap[snap.relativePath]  = snap
            case .right: rightSnap[snap.relativePath] = snap
            }
        }

        // Union of all paths seen
        let allPaths = Set(leftScan.keys)
            .union(rightScan.keys)
            .union(leftSnap.keys)
            .union(rightSnap.keys)

        return allPaths.map { path in
            computeDiff(
                relativePath: path,
                leftFile:    leftScan[path],
                rightFile:   rightScan[path],
                leftSnap:    leftSnap[path],
                rightSnap:   rightSnap[path],
                checksumEnabled: checksumEnabled
            )
        }
        // Note: NOT sorted — sorting 30k strings costs ~500ms.
        // TreeBuilder uses an O(1) dict, so insertion order doesn’t matter.
    }

    // MARK: - Convenience summary

    /// Returns a `DiffSummary` count over a collection of diffs.
    func summary(of diffs: [FileDiff]) -> DiffSummary {
        var s = DiffSummary()
        for d in diffs {
            switch d.status {
            case .same:               s.same += 1
            case .new:                s.new += 1
            case .deleted:            s.deleted += 1
            case .updated:            s.updated += 1
            case .clash:              s.clashes += 1
            case .excluded:           s.excluded += 1
            }
        }
        return s
    }

    // MARK: - Core comparison logic

    private func computeDiff(
        relativePath: String,
        leftFile:  ScannedFile?,
        rightFile: ScannedFile?,
        leftSnap:  TrackedFile?,
        rightSnap: TrackedFile?,
        checksumEnabled: Bool
    ) -> FileDiff {

        let status: DiffStatus

        switch (leftFile != nil, rightFile != nil) {

        // ── Both sides present ──────────────────────────────────────────────
        case (true, true):
            let leftChanged  = hasChanged(file: leftFile!,  since: leftSnap,  checksumEnabled: checksumEnabled)
            let rightChanged = hasChanged(file: rightFile!, since: rightSnap, checksumEnabled: checksumEnabled)

            if leftChanged && rightChanged {
                status = .clash
            } else if leftChanged {
                status = .updated(newer: .left)
            } else if rightChanged {
                status = .updated(newer: .right)
            } else {
                // Both exist, neither changed since last sync — confirm they match
                if filesMatch(leftFile!, rightFile!, checksumEnabled: checksumEnabled) {
                    status = .same
                } else {
                    // No snapshot exists yet (first scan ever) + they differ → treat as clash
                    if leftSnap == nil && rightSnap == nil {
                        status = .clash
                    } else {
                        status = .clash
                    }
                }
            }

        // ── Only on left ────────────────────────────────────────────────────
        case (true, false):
            if rightSnap != nil {
                // Was on both sides before, now gone from right → deleted from right
                status = .deleted(.right)
            } else {
                // Never seen on right → new on left
                status = .new(.left)
            }

        // ── Only on right ───────────────────────────────────────────────────
        case (false, true):
            if leftSnap != nil {
                status = .deleted(.left)
            } else {
                status = .new(.right)
            }

        // ── Gone from both sides ────────────────────────────────────────────
        default:
            // Was tracked but now gone everywhere — already synced deletion,
            // stale snapshot rows will be cleaned up by SyncManager after sync.
            status = .same
        }

        return FileDiff(
            relativePath: relativePath,
            status: status,
            leftFile: leftFile,
            rightFile: rightFile,
            leftSnapshot: leftSnap,
            rightSnapshot: rightSnap
        )
    }

    // MARK: - Change detection helpers

    /// True if `file` differs from its last-sync `snapshot`.
    private func hasChanged(
        file: ScannedFile,
        since snapshot: TrackedFile?,
        checksumEnabled: Bool
    ) -> Bool {
        guard let snap = snapshot else {
            // No snapshot means we've never recorded this side → treat as unchanged
            // (new-file detection happens in the case split above, not here)
            return false
        }

        if checksumEnabled, let fc = file.checksum, let sc = snap.checksum {
            return fc != sc
        }
        // Fallback: size + mod date
        return file.sizeBytes != snap.sizeBytes
            || abs(file.modifiedAt.timeIntervalSince(snap.modifiedAt)) > 2.0
    }

    /// True if two live files appear to be identical.
    private func filesMatch(
        _ a: ScannedFile,
        _ b: ScannedFile,
        checksumEnabled: Bool
    ) -> Bool {
        if checksumEnabled, let ca = a.checksum, let cb = b.checksum {
            return ca == cb
        }
        return a.sizeBytes == b.sizeBytes
            && abs(a.modifiedAt.timeIntervalSince(b.modifiedAt)) <= 2.0
    }
}

// MARK: - DiffSummary

struct DiffSummary {
    var same:     Int = 0
    var new:      Int = 0
    var updated:  Int = 0
    var deleted:  Int = 0
    var clashes:  Int = 0
    var excluded: Int = 0
    /// Number of leaf files that physically exist on each side (used for folder absent-dimming).
    var leftFileCount:  Int = 0
    var rightFileCount: Int = 0

    var total: Int { same + new + updated + deleted + clashes + excluded }

    /// Tooltip-style string shown on folder nodes.
    var tooltipString: String {
        var parts: [String] = []
        if same     > 0 { parts.append("\(same) same") }
        if new      > 0 { parts.append("\(new) new") }
        if updated  > 0 { parts.append("\(updated) updated") }
        if deleted  > 0 { parts.append("\(deleted) deleted") }
        if clashes  > 0 { parts.append("\(clashes) clash\(clashes == 1 ? "" : "es")") }
        if excluded > 0 { parts.append("\(excluded) excluded") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: " · ")
    }
}
