import AppKit

/// Container that holds two `TreeViewController` instances side by side, 
/// plus a toolbar with Sync, Expand/Collapse, and status bar.
final class PairDetailViewController: NSViewController {

    // MARK: - Callbacks
    /// Called when the user requests a sync. `diffs` is non-nil when only a
    /// subset of diffs should be synced (e.g. a single file context-menu action).
    var onSyncRequested: ((SyncPair, SyncOptions, [FileDiff]?) -> Void)?
    var onEditPair:       ((SyncPair) -> Void)?
    var onResolveClash:   ((FileDiff, SyncPair) -> Void)?
    var onViewHistory:    ((SyncPair) -> Void)?

    // MARK: - Child VCs
    private let leftTreeVC  = TreeViewController(side: .left)
    private let rightTreeVC = TreeViewController(side: .right)

    // MARK: - UI
    private let toolbar        = NSView()
    private let syncButton     = NSButton(title: "Sync", target: nil, action: nil)
    private let scanButton     = NSButton(title: "Scan", target: nil, action: nil)
    private let editButton     = NSButton(title: "Settings…", target: nil, action: nil)
    private let historyButton  = NSButton(title: "History…", target: nil, action: nil)
    private let expandButton        = NSButton(title: "Expand All", target: nil, action: nil)
    private let collapseButton      = NSButton(title: "Collapse All", target: nil, action: nil)
    private let showExcludedButton  = NSButton(checkboxWithTitle: "Show Excluded", target: nil, action: nil)
    private let progressSpinner: NSProgressIndicator = {
        let s = NSProgressIndicator()
        s.style = .spinning
        s.controlSize = .small
        s.isIndeterminate = true
        s.isHidden = true
        s.translatesAutoresizingMaskIntoConstraints = false
        return s
    }()
    private let statusBar      = NSTextField(labelWithString: "")
    private let splitView      = NSSplitView()
    private let placeholderLabel = NSTextField(labelWithString: "Select or add a folder pair from the sidebar.")

    // MARK: - State
    private var currentPair: SyncPair?
    var currentDiffs: [FileDiff] = []
    private var currentExcludedDiffs: [FileDiff] = []
    private var showExcluded = false
    private let diffEngine = DiffEngine()
    /// Incremented every time configure(with:) is called so in-flight scans know they are stale.
    private var scanGeneration = 0

    // MARK: - Copy animation state
    private var copyAnimTimer: Timer?
    private var copyAnimFrame = 0
    private var copyAnimFileName = ""
    private var copyAnimDirection: SyncSide = .left


    // MARK: - View lifecycle
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupToolbar()
        setupTreeSplit()
        setupStatusBar()
        setupPlaceholder()
        setupLayout()
        bindTreeCallbacks()
        showPlaceholder(true)
    }

    // MARK: - Public API

    func configure(with pair: SyncPair?) {
        scanGeneration += 1        // invalidate any in-flight scan
        currentPair = pair
        guard let pair else { showPlaceholder(true); return }
        showPlaceholder(false)
        leftTreeVC.updateHeader(path: pair.leftPath)
        leftTreeVC.rootPath = pair.leftPath
        rightTreeVC.updateHeader(path: pair.rightPath)
        rightTreeVC.rootPath = pair.rightPath
        currentDiffs = []
        currentExcludedDiffs = []
        applyDiffs([])

        // Check that both folders are reachable before scanning.
        // If a drive is offline the scan would immediately fail — skip it and
        // show a clear warning instead of a cryptic error in the status bar.
        let fm = FileManager.default
        var missing: [String] = []
        if !fm.fileExists(atPath: pair.leftPath)  { missing.append(URL(fileURLWithPath: pair.leftPath).lastPathComponent) }
        if !fm.fileExists(atPath: pair.rightPath) { missing.append(URL(fileURLWithPath: pair.rightPath).lastPathComponent) }
        if !missing.isEmpty {
            let noun = missing.count == 1 ? "folder" : "folders"
            showStatusMessage("\u{26a0}\u{fe0f}  Drive offline \u{2014} \(noun) not found: \(missing.joined(separator: " \u{00b7} "))")
            syncButton.isEnabled = false
            scanButton.isEnabled = false
            return
        }

        reload(pair: pair)  // auto-scan on selection
    }

    func reload(pair: SyncPair, pressedAt: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()) {
        let generation = scanGeneration
        startProgress()
        showStatusMessage("Scanning…")

        // Counts updated by background threads (lock-protected); read by the timer on main.
        let lock = NSLock()
        var leftCount  = 0
        var rightCount = 0

        // Progress label driven by a repeating timer on the main thread.
        // Worker threads NEVER dispatch to main — they only write counts under the lock.
        let progressTimer = DispatchSource.makeTimerSource(queue: .main)
        progressTimer.schedule(deadline: .now() + .milliseconds(250), repeating: .milliseconds(250))
        progressTimer.setEventHandler { [weak self] in
            guard let self, self.scanGeneration == generation else { progressTimer.cancel(); return }
            lock.lock(); let lc = leftCount; let rc = rightCount; lock.unlock()
            self.showStatusMessage("Scanning…  ← \(lc.formatted()) files  ·  → \(rc.formatted()) files")
        }
        progressTimer.resume()

        let pairId      = pair.id ?? 0
        let isCancelled: () -> Bool = { [weak self] in self?.scanGeneration != generation }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { progressTimer.cancel(); return }

            // ── Phase 1: Exclusion rules ──────────────────────────────────────
            let p1s = CFAbsoluteTimeGetCurrent()
            let exclusions: [ExclusionRule]
            do {
                exclusions = try DatabaseManager.shared.read { db in
                    try ExclusionRule.filter(sql: "pairId = \(pairId)").fetchAll(db)
                }
            } catch {
                progressTimer.cancel()
                DispatchQueue.main.async { [weak self] in
                    self?.stopProgress()
                    self?.showStatusMessage("Scan error: \(error.localizedDescription)")
                }
                return
            }
            let tExclusions = CFAbsoluteTimeGetCurrent() - p1s
            guard !isCancelled() else { progressTimer.cancel(); return }

            // ── Phase 2+3: Parallel scan — zero dispatches to main ────────────
            let parallelStart = CFAbsoluteTimeGetCurrent()
            var leftResult:   [String: ScannedFile] = [:]
            var rightResult:  [String: ScannedFile] = [:]
            var leftScanTime  = 0.0
            var rightScanTime = 0.0
            var scanError:    Error?

            let grp = DispatchGroup()
            let q   = DispatchQueue.global(qos: .userInitiated)

            var leftExcluded:  [String: ScannedFile] = [:]
            var rightExcluded: [String: ScannedFile] = [:]

            grp.enter()
            q.async {
                let t = CFAbsoluteTimeGetCurrent()
                let scanner = FileScanner()
                scanner.collectExcluded = true
                do {
                    leftResult = try scanner.scan(
                        rootURL: URL(fileURLWithPath: pair.leftPath),
                        exclusionRules: exclusions,
                        checksumEnabled: pair.checksumEnabled,
                        isCancelled: isCancelled,
                        onProgress: { n in lock.lock(); leftCount = n; lock.unlock() }
                    )
                } catch { lock.lock(); if scanError == nil { scanError = error }; lock.unlock() }
                lock.lock()
                leftScanTime = CFAbsoluteTimeGetCurrent() - t
                leftExcluded = scanner.excludedFiles
                lock.unlock()
                grp.leave()
            }

            grp.enter()
            q.async {
                let t = CFAbsoluteTimeGetCurrent()
                let scanner = FileScanner()
                scanner.collectExcluded = true
                do {
                    rightResult = try scanner.scan(
                        rootURL: URL(fileURLWithPath: pair.rightPath),
                        exclusionRules: exclusions,
                        checksumEnabled: pair.checksumEnabled,
                        isCancelled: isCancelled,
                        onProgress: { n in lock.lock(); rightCount = n; lock.unlock() }
                    )
                } catch { lock.lock(); if scanError == nil { scanError = error }; lock.unlock() }
                lock.lock()
                rightScanTime = CFAbsoluteTimeGetCurrent() - t
                rightExcluded = scanner.excludedFiles
                lock.unlock()
                grp.leave()
            }

            grp.wait()   // blocks background thread only — main thread is fully free
            let tParallel = CFAbsoluteTimeGetCurrent() - parallelStart
            progressTimer.cancel()   // stop timer now that scan is done

            // Build excluded diffs from items the scanners skipped on both sides
            let excludedDiffs: [FileDiff] = {
                let paths = Set(leftExcluded.keys).union(rightExcluded.keys)
                return paths.map { path in
                    FileDiff(relativePath: path, status: .excluded,
                             leftFile: leftExcluded[path], rightFile: rightExcluded[path],
                             leftSnapshot: nil, rightSnapshot: nil)
                }
            }()

            if let err = scanError {
                DispatchQueue.main.async { [weak self] in
                    self?.stopProgress()
                    if case FileScanner.ScanError.cancelled = err { return }
                    if case FileScanner.ScanError.rootNotFound(let path) = err {
                        let name = URL(fileURLWithPath: path).lastPathComponent
                        self?.syncButton.isEnabled = false
                        self?.scanButton.isEnabled = false
                        self?.showStatusMessage("\u{26a0}\u{fe0f}  Drive offline \u{2014} folder not found: \(name)")
                        return
                    }
                    self?.showStatusMessage("Scan error: \(err.localizedDescription)")
                }
                return
            }
            guard !isCancelled() else { return }

            // ── Phase 4: Snapshots ────────────────────────────────────────────
            let p4s = CFAbsoluteTimeGetCurrent()
            let snapshots: [TrackedFile]
            do {
                snapshots = try DatabaseManager.shared.read { db in
                    try TrackedFile.filter(sql: "pairId = \(pairId)").fetchAll(db)
                }
            } catch {
                DispatchQueue.main.async { [weak self] in
                    self?.stopProgress()
                    self?.showStatusMessage("Scan error: \(error.localizedDescription)")
                }
                return
            }
            let tSnapshots = CFAbsoluteTimeGetCurrent() - p4s
            guard !isCancelled() else { return }

            // ── Phase 5: Diff ─────────────────────────────────────────────────
            let p5s   = CFAbsoluteTimeGetCurrent()
            let diffs = self.diffEngine.diff(
                leftScan: leftResult, rightScan: rightResult,
                snapshots: snapshots, checksumEnabled: pair.checksumEnabled
            )
            let tDiff = CFAbsoluteTimeGetCurrent() - p5s
            guard !isCancelled() else { return }

            // ── Phase 5b: Persist baseline snapshots for first-time matching files ──
            // Files that are `.same` (both sides present and matching) but have NO snapshot
            // yet represent folders that were already in sync before Tandem first saw them.
            // Writing their snapshot now enables accurate deletion/update tracking on the
            // very next scan — without requiring the user to press Sync first.
            let untrackedSame = diffs.filter {
                if case .same = $0.status { return $0.leftSnapshot == nil && $0.rightSnapshot == nil }
                return false
            }

            if !untrackedSame.isEmpty, pair.id != nil {
                let nowBaseline = Date()
                try? DatabaseManager.shared.write { db in
                    let sql = """
                        INSERT OR IGNORE INTO tracked_files
                            (pairId, relativePath, side, sizeBytes, modifiedAt, checksum, syncedAt)
                        VALUES (?, ?, ?, ?, ?, ?, ?)
                        """
                    for diff in untrackedSame {
                        if let lf = leftResult[diff.relativePath] {
                            try db.execute(sql: sql, arguments: [
                                pairId, diff.relativePath, SyncSide.left.rawValue,
                                lf.sizeBytes, lf.modifiedAt, lf.checksum, nowBaseline])
                        }
                        if let rf = rightResult[diff.relativePath] {
                            try db.execute(sql: sql, arguments: [
                                pairId, diff.relativePath, SyncSide.right.rawValue,
                                rf.sizeBytes, rf.modifiedAt, rf.checksum, nowBaseline])
                        }
                    }
                }
            }

            let lc = leftResult.count;  let ls = leftScanTime
            let rc = rightResult.count; let rs = rightScanTime

            // ── Phase 6: ONE dispatch to main — all background work is done ───
            let tEnqueued = CFAbsoluteTimeGetCurrent()
            DispatchQueue.main.async { [weak self] in
                let tQueueBacklog = CFAbsoluteTimeGetCurrent() - tEnqueued
                guard let self, self.scanGeneration == generation else { return }

                let p6s = CFAbsoluteTimeGetCurrent()
                self.currentDiffs = diffs
                self.currentExcludedDiffs = excludedDiffs
                self.applyDiffs(diffs)
                let tTree  = CFAbsoluteTimeGetCurrent() - p6s
                self.stopProgress()
                self.showStatusMessage(self.diffEngine.summary(of: diffs).tooltipString)

                func ms(_ s: Double) -> String { String(format: "%.1f ms", s * 1000) }
                let tTotal = CFAbsoluteTimeGetCurrent() - pressedAt

                let lines: [(String, String)] = [
                    ("1. DB read — exclusion rules",                         ms(tExclusions)),
                    ("2. LEFT  filesystem scan (\(lc.formatted()) files)",   ms(ls)),
                    ("   RIGHT filesystem scan (\(rc.formatted()) files)",   ms(rs)),
                    ("   Both sides (parallel wall time)",                   ms(tParallel)),
                    ("3. DB read — prior snapshots (\(snapshots.count.formatted()) rows)", ms(tSnapshots)),
                    ("4. Diff computation (\(diffs.count.formatted()) pairs)", ms(tDiff)),
                    ("   ↳ main queue backlog",                              ms(tQueueBacklog)),
                    ("5. Build tree + render UI",                            ms(tTree)),
                    ("────────────────────────────────────────",             "─────────"),
                    ("Button pressed → popup appears",                       ms(tTotal))
                ]
                let colW  = lines.map(\.0.count).max() ?? 0
                let table = lines.map { l, v in
                    l.padding(toLength: colW, withPad: " ", startingAt: 0) + "   " + v
                }.joined(separator: "\n")
                let logPath = "/tmp/tandem_timing.txt"
                let entry = "[Scan Timing — \(pair.name)]\n\(table)\n\n"
                if let data = entry.data(using: .utf8) {
                    if FileManager.default.fileExists(atPath: logPath),
                       let handle = FileHandle(forWritingAtPath: logPath) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    } else {
                        try? data.write(to: URL(fileURLWithPath: logPath))
                    }
                }
            }
        }
    }

    func applyResult(_ result: SyncResult) {
        var parts: [String] = []
        if result.copied.count  > 0 { parts.append("\(result.copied.count) copied") }
        if result.deleted.count > 0 { parts.append("\(result.deleted.count) deleted") }
        if result.clashes.count > 0 { parts.append("\(result.clashes.count) clash(es) — intervention required") }
        if result.errors.count  > 0 { parts.append("\(result.errors.count) error(s)") }
        showStatusMessage(parts.isEmpty ? "No changes" : parts.joined(separator: " · "))
    }

    /// Updates the tree in-place based on a completed sync result — no rescan needed.
    func applySyncResult(_ result: SyncResult) {
        applyResult(result)
        let copiedPaths  = Set(result.copied.map(  \.relativePath))
        let deletedPaths = Set(result.deleted.map( \.relativePath))
        currentDiffs = currentDiffs.compactMap { diff in
            if deletedPaths.contains(diff.relativePath) { return nil }
            if copiedPaths.contains(diff.relativePath) {
                // Both sides now match — mark as same
                let file = diff.leftFile ?? diff.rightFile
                return FileDiff(
                    relativePath:  diff.relativePath,
                    status:        .same,
                    leftFile:      file,
                    rightFile:     file,
                    leftSnapshot:  diff.leftSnapshot,
                    rightSnapshot: diff.rightSnapshot
                )
            }
            return diff
        }
        applyDiffs(currentDiffs)
    }

    func showStatusMessage(_ message: String) {
        stopCopyAnimation()
        statusBar.stringValue = message
    }

    // MARK: - Copy direction animation

    /// Called just before a file copy starts. Animates an arrow track in the status bar
    /// showing which direction the copy is flowing, until the next message arrives.
    func startCopyAnimation(fileName: String, direction: SyncSide) {
        copyAnimFileName = URL(fileURLWithPath: fileName).lastPathComponent
        copyAnimDirection = direction
        copyAnimFrame = 0
        copyAnimTimer?.invalidate()
        copyAnimTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.tickCopyAnimation()
        }
    }

    private func tickCopyAnimation() {
        copyAnimFrame += 1
        // Track: 9 chars wide, 4-arrow head bouncing back and forth.
        let width    = 9
        let arrowLen = 4
        let span     = width - arrowLen       // 5 valid start positions: 0..4
        let cycle    = span * 2               // 10-frame bounce cycle
        let t        = copyAnimFrame % cycle
        let pos      = t <= span ? t : cycle - t

        // Arrows point in the copy direction; they sweep in that direction too.
        let rightward = (copyAnimDirection == .left)   // FROM left → arrows go right
        let arrowChar: Character = rightward ? ">" : "<"
        let effectivePos = rightward ? pos : (span - pos)

        var chars = Array(repeating: Character("·"), count: width)
        for i in 0..<arrowLen { chars[effectivePos + i] = arrowChar }
        statusBar.stringValue = "\(copyAnimFileName)  [\(String(chars))]"
    }

    func stopCopyAnimation() {
        copyAnimTimer?.invalidate()
        copyAnimTimer = nil
    }

    // MARK: - Progress helpers

    func startProgress() {
        syncButton.isEnabled   = false
        scanButton.isEnabled   = false
        progressSpinner.isHidden = false
        progressSpinner.startAnimation(nil)
    }

    func stopProgress() {
        stopCopyAnimation()
        syncButton.isEnabled   = true
        scanButton.isEnabled   = true
        progressSpinner.isHidden = true
        progressSpinner.stopAnimation(nil)
    }

    // MARK: - Private helpers

    private func applyDiffs(_ diffs: [FileDiff]) {
        // Both sides share the same tree — absent files are dimmed in each side's cells.
        let allDiffs = showExcluded ? diffs + currentExcludedDiffs : diffs
        let tree = TreeBuilder.build(from: allDiffs)
        leftTreeVC.rootNode  = tree
        rightTreeVC.rootNode = tree
    }

    private func showPlaceholder(_ show: Bool) {
        placeholderLabel.isHidden = !show
        splitView.isHidden        = show
        toolbar.isHidden          = show
        statusBar.isHidden        = show
    }

    // MARK: - Setup

    private func setupToolbar() {
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        toolbar.wantsLayer = true
        toolbar.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        syncButton.bezelStyle = .rounded
        syncButton.target = self
        syncButton.action = #selector(syncPressed)

        scanButton.bezelStyle = .rounded
        scanButton.target = self
        scanButton.action = #selector(scanPressed)

        editButton.bezelStyle = .rounded
        editButton.target = self
        editButton.action = #selector(editPressed)

        historyButton.bezelStyle = .rounded
        historyButton.target = self
        historyButton.action = #selector(viewHistory)

        expandButton.bezelStyle = .rounded
        expandButton.target = self
        expandButton.action = #selector(expandAll)

        collapseButton.bezelStyle = .rounded
        collapseButton.target = self
        collapseButton.action = #selector(collapseAll)

        showExcludedButton.target = self
        showExcludedButton.action = #selector(toggleShowExcluded)
        showExcludedButton.state  = .off

        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)  // allow spacer to stretch
        spacer.setContentCompressionResistancePriority(.init(1), for: .horizontal)
        let stack = NSStackView(views: [syncButton, scanButton, editButton, historyButton, spacer, progressSpinner, expandButton, collapseButton, showExcludedButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 8
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.setHuggingPriority(.init(1), for: .horizontal)
        toolbar.addSubview(stack)
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: toolbar.topAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: toolbar.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: toolbar.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: -6)
        ])
    }

    private func setupTreeSplit() {
        addChild(leftTreeVC)
        addChild(rightTreeVC)
        splitView.isVertical = true
        splitView.addArrangedSubview(leftTreeVC.view)
        splitView.addArrangedSubview(rightTreeVC.view)
        splitView.dividerStyle = .thin
        splitView.autosaveName = "PairDetailSplit"
        splitView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(splitView)
    }

    private func setupStatusBar() {
        statusBar.font = .systemFont(ofSize: 11)
        statusBar.textColor = .secondaryLabelColor
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusBar)
    }

    private func setupPlaceholder() {
        placeholderLabel.font = .systemFont(ofSize: 15)
        placeholderLabel.textColor = .tertiaryLabelColor
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.alignment = .center
        view.addSubview(placeholderLabel)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.heightAnchor.constraint(greaterThanOrEqualToConstant: 36),

            splitView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 1),
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.bottomAnchor.constraint(equalTo: statusBar.topAnchor, constant: -4),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -6),
            statusBar.heightAnchor.constraint(equalToConstant: 18),

            placeholderLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            placeholderLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }

    private func bindTreeCallbacks() {
        let handler: (TreeViewController) -> Void = { [weak self] treeVC in
            guard let self else { return }

            treeVC.onSyncFile = { [weak self] diff in
                guard let self, let pair = self.currentPair else { return }
                self.onSyncRequested?(pair, SyncOptions(), [diff])
            }

            treeVC.onCopyFile = { [weak self] diff, fromSide in
                guard let self, let pair = self.currentPair else { return }
                self.forceCopy(diff: diff, fromSide: fromSide, pair: pair)
            }

            treeVC.onCopyFolder = { [weak self] node, fromSide in
                guard let self, let pair = self.currentPair else { return }
                self.forceCopyFolder(node: node, fromSide: fromSide, pair: pair)
            }

            treeVC.onResolveClash = { [weak self] diff in
                guard let self, let pair = self.currentPair else { return }
                self.onResolveClash?(diff, pair)
            }

            treeVC.onAddExclusion = { [weak self] diff in
                guard let self, let pair = self.currentPair else { return }
                self.addQuickExclusion(for: diff, pair: pair)
            }
        }
        handler(leftTreeVC)
        handler(rightTreeVC)

        // Synchronized expand/collapse — mirrored without re-firing to avoid ping-pong
        leftTreeVC.onExpand    = { [weak self] node in self?.rightTreeVC.mirrorExpand(node) }
        leftTreeVC.onCollapse  = { [weak self] node in self?.rightTreeVC.mirrorCollapse(node) }
        rightTreeVC.onExpand   = { [weak self] node in self?.leftTreeVC.mirrorExpand(node) }
        rightTreeVC.onCollapse = { [weak self] node in self?.leftTreeVC.mirrorCollapse(node) }

        // Synchronized scroll — observe clip-view bounds changes
        leftTreeVC.clipView.postsBoundsChangedNotifications  = true
        rightTreeVC.clipView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(leftTreeScrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: leftTreeVC.clipView)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(rightTreeScrolled(_:)),
            name: NSView.boundsDidChangeNotification,
            object: rightTreeVC.clipView)
    }

    @objc private func leftTreeScrolled(_ note: Notification) {
        rightTreeVC.mirrorScrollOffset(leftTreeVC.scrollOffsetY)
    }

    @objc private func rightTreeScrolled(_ note: Notification) {
        leftTreeVC.mirrorScrollOffset(rightTreeVC.scrollOffsetY)
    }

    // MARK: - Toolbar actions

    @objc private func syncPressed() {
        guard let pair = currentPair else { return }
        onSyncRequested?(pair, SyncOptions(), nil)
    }

    @objc private func scanPressed() {
        guard let pair = currentPair else { return }
        reload(pair: pair, pressedAt: CFAbsoluteTimeGetCurrent())
    }

    @objc private func editPressed() {
        guard let pair = currentPair else { return }
        onEditPair?(pair)
    }

    @objc private func viewHistory() {
        guard let pair = currentPair else { return }
        onViewHistory?(pair)
    }

    @objc private func expandAll() {
        leftTreeVC.expandAll()
        rightTreeVC.expandAll()
    }

    @objc private func collapseAll() {
        leftTreeVC.collapseAll()
        rightTreeVC.collapseAll()
    }

    @objc private func toggleShowExcluded() {
        showExcluded = showExcludedButton.state == .on
        applyDiffs(currentDiffs)
    }

    // MARK: - Force copy

    private var skipConfirmKey: (SyncPair) -> String {
        { pair in "Tandem.skipForceCopyConfirmation.pair\(pair.id ?? 0)" }
    }

    private func forceCopy(diff: FileDiff, fromSide: SyncSide, pair: SyncPair) {
        let key = skipConfirmKey(pair)

        func proceed() {
            let syntheticDiff = FileDiff(
                relativePath:  diff.relativePath,
                status:        .updated(newer: fromSide),
                leftFile:      diff.leftFile,
                rightFile:     diff.rightFile,
                leftSnapshot:  diff.leftSnapshot,
                rightSnapshot: diff.rightSnapshot
            )
            var opts = SyncOptions()
            opts.syncUpdated  = true
            opts.syncNew      = true
            opts.syncDeleted  = false
            opts.isForceCopy  = true
            onSyncRequested?(pair, opts, [syntheticDiff])
        }

        if UserDefaults.standard.bool(forKey: key) { proceed(); return }

        let alert = NSAlert()
        alert.messageText = "Force Copy \(fromSide.arrowTo(fromSide.opposite))?"
        alert.informativeText = "\"\(diff.relativePath)\" on the \(fromSide.opposite.displayName) side will be overwritten with the \(fromSide.displayName) version.\n\nThe overwritten file will be moved to the backup folder first (if backup is enabled)."
        alert.addButton(withTitle: "Force Copy")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let checkbox = NSButton(checkboxWithTitle: "Don't ask me again for \"\(pair.name)\"", target: nil, action: nil)
        checkbox.state = .off
        alert.accessoryView = checkbox

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if checkbox.state == .on { UserDefaults.standard.set(true, forKey: key) }
        proceed()
    }

    private func forceCopyFolder(node: TreeNode, fromSide: SyncSide, pair: SyncPair) {
        // Collect all leaf diffs that exist on the source side
        var diffs: [FileDiff] = []
        func collectLeaves(_ n: TreeNode) {
            if n.isLeaf, let diff = n.diff {
                let exists = fromSide == .left ? diff.leftFile != nil : diff.rightFile != nil
                if exists { diffs.append(diff) }
            } else {
                n.children.forEach(collectLeaves)
            }
        }
        collectLeaves(node)

        // No source files — guide the user to the correct direction
        guard !diffs.isEmpty else {
            let destSide = fromSide.opposite
            let hint = NSAlert()
            hint.messageText = "No \(fromSide.displayName) Files in \"\(node.displayName)\""
            hint.informativeText = "There are no files on the \(fromSide.displayName) side of this folder to copy.\n\nIf you want to copy \(destSide.displayName) files to \(fromSide.displayName), use \"Force Copy Folder \(destSide.arrowTo(fromSide))\" instead."
            hint.alertStyle = .informational
            hint.addButton(withTitle: "OK")
            hint.runModal()
            return
        }

        let key      = skipConfirmKey(pair)
        let destSide = fromSide.opposite
        let fileWord = diffs.count == 1 ? "file" : "files"

        // Distinguish truly new files (destination absent) from overwrites
        let newCount       = diffs.filter { fromSide == .left ? $0.rightFile == nil : $0.leftFile == nil }.count
        let overwriteCount = diffs.count - newCount

        var bodyLines: [String] = []
        if newCount > 0 && overwriteCount == 0 {
            bodyLines.append("\(diffs.count) new \(fileWord) will be created on the \(destSide.displayName) side.")
        } else if overwriteCount > 0 && newCount == 0 {
            bodyLines.append("\(diffs.count) \(fileWord) will overwrite existing \(destSide.displayName) versions.")
            bodyLines.append("Overwritten files will be moved to the backup folder first (if backup is enabled).")
        } else {
            bodyLines.append("\(newCount) new \(newCount == 1 ? "file" : "files") will be created and \(overwriteCount) will overwrite existing \(destSide.displayName) versions.")
            bodyLines.append("Overwritten files will be moved to the backup folder first (if backup is enabled).")
        }

        func proceed() {
            let synthetics = diffs.map { diff in
                FileDiff(
                    relativePath: diff.relativePath,
                    status:       .updated(newer: fromSide),
                    leftFile:     diff.leftFile,
                    rightFile:    diff.rightFile,
                    leftSnapshot: diff.leftSnapshot,
                    rightSnapshot: diff.rightSnapshot
                )
            }
            var opts = SyncOptions()
            opts.syncUpdated  = true
            opts.syncNew      = true
            opts.syncDeleted  = false
            opts.isForceCopy  = true
            onSyncRequested?(pair, opts, synthetics)
        }

        if UserDefaults.standard.bool(forKey: key) { proceed(); return }

        let alert = NSAlert()
        alert.messageText = "Force Copy Folder \"\(node.displayName)\" — \(fromSide.arrowTo(destSide))?"
        alert.informativeText = bodyLines.joined(separator: "\n\n")
        alert.addButton(withTitle: "Force Copy \(diffs.count) \(fileWord.capitalized)")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning

        let checkbox = NSButton(checkboxWithTitle: "Don't ask me again for \"\(pair.name)\"", target: nil, action: nil)
        checkbox.state = .off
        alert.accessoryView = checkbox

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        if checkbox.state == .on { UserDefaults.standard.set(true, forKey: key) }
        proceed()
    }

    // MARK: - Quick exclusion

    private func addQuickExclusion(for diff: FileDiff, pair: SyncPair) {
        guard let pairId = pair.id else { return }
        do {
            let existingCount = (try? DatabaseManager.shared.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM exclusion_rules WHERE pairId = ?",
                                 arguments: [pairId])
            } ?? 0) ?? 0
            var rule = ExclusionRule(
                pairId:    pairId,
                ruleType:  .filepath,
                pattern:   diff.relativePath,
                isEnabled: true,
                sortOrder: existingCount
            )
            try DatabaseManager.shared.write { db in try rule.insert(db) }
            reload(pair: pair)
        } catch {
            NSApp.presentError(error)
        }
    }
}
