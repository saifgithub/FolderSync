import AppKit

/// Root window controller. Hosts a sidebar (pair list) and a side-by-side tree detail view.
final class MainWindowController: NSWindowController {

    // MARK: - Child view controllers
    private let splitVC         = NSSplitViewController()
    private let pairListVC      = SyncPairListVC()
    private var pairDetailVC    = PairDetailViewController()

    // MARK: - Active sync pair
    private var selectedPair: SyncPair? {
        didSet { pairDetailVC.configure(with: selectedPair) }
    }

    // MARK: - Background sync queue
    private let syncQueue = DispatchQueue(label: "com.tandem.syncqueue", qos: .userInitiated)

    // MARK: - Init

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "Tandem"
        window.setFrameAutosaveName("MainWindow")
        window.minSize = NSSize(width: 800, height: 500)
        self.init(window: window)
        
        buildLayout()
        bindCallbacks()
        activateWatcherCoordinator()
    }

    // MARK: - Layout

    private func buildLayout() {
        guard let window else { return }

        // Sidebar item
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: pairListVC)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 320

        // Detail item
        let detailItem = NSSplitViewItem(viewController: pairDetailVC)
        detailItem.minimumThickness = 600

        splitVC.addSplitViewItem(sidebarItem)
        splitVC.addSplitViewItem(detailItem)
        splitVC.splitView.isVertical = true
        splitVC.splitView.autosaveName = "MainSplit"

        window.contentViewController = splitVC
        window.center()
    }

    // MARK: - Callbacks

    private func bindCallbacks() {
        // When the user selects a different pair in the sidebar
        pairListVC.onPairSelected = { [weak self] pair in
            self?.selectedPair = pair
        }

        // Sync button from the toolbar/detail view
        pairDetailVC.onSyncRequested = { [weak self] pair, options, diffs in
            self?.runSync(pair: pair, options: options, diffs: diffs)
        }

        // Pair created/edited from the detail view toolbar
        pairDetailVC.onEditPair = { [weak self] pair in
            self?.showSettings(for: pair)
        }

        // Pair add button from sidebar
        pairListVC.onAddPair = { [weak self] in
            self?.showSettings(for: nil)
        }

        // Conflict resolution
        pairDetailVC.onResolveClash = { [weak self] diff, pair in
            self?.showConflictResolution(diff: diff, pair: pair)
        }

        // Backup history
        pairDetailVC.onViewHistory = { [weak self] pair in
            self?.showBackupHistory(for: pair)
        }
    }

    // MARK: - WatcherCoordinator

    private func activateWatcherCoordinator() {
        WatcherCoordinator.shared.onSyncNeeded = { [weak self] pairId, changedURLs in
            guard let self else { return }
            DispatchQueue.main.async {
                guard let pair = self.pairListVC.pair(withId: pairId) else { return }
                if changedURLs.isEmpty {
                    // Scheduled tick → full sync
                    self.runSync(pair: pair, options: SyncOptions())
                } else {
                    // FSEvent trigger → incremental sync on affected paths only
                    self.runIncrementalSync(pair: pair, changedURLs: changedURLs, options: SyncOptions())
                }
            }
        }

        // Activate watchers for all persisted pairs
        do {
            let pairs = try DatabaseManager.shared.read { db in try SyncPair.fetchAll(db) }
            pairs.forEach { WatcherCoordinator.shared.activate(pair: $0) }
        } catch {
            presentError(error)
        }
    }

    // MARK: - Sync

    func runSync(pair: SyncPair, options: SyncOptions, diffs: [FileDiff]? = nil) {
        let manager = SyncManager()
        manager.onProgress = { [weak self] message in
            self?.pairDetailVC.showStatusMessage(message)
        }
        manager.onFileCopy = { [weak self] fileName, direction in
            self?.pairDetailVC.startCopyAnimation(fileName: fileName, direction: direction)
        }

        // Prefer the pre-computed diffs already in the UI — avoids a redundant scan.
        // If the caller supplied explicit diffs (e.g. single-file sync) use those first.
        let activeDiffs: [FileDiff]?
        if let supplied = diffs {
            activeDiffs = supplied
        } else {
            activeDiffs = pairDetailVC.currentDiffs.isEmpty ? nil : pairDetailVC.currentDiffs
        }

        syncQueue.async { [weak self] in
            do {
                let result = try manager.sync(pair: pair, options: options, diffs: activeDiffs)
                DispatchQueue.main.async {
                    // Update tree in-place — no rescan.
                    self?.pairDetailVC.applySyncResult(result)
                    self?.pairListVC.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.presentError(error)
                }
            }
        }
    }

    // MARK: - Incremental Sync (FSEvent-triggered)

    func runIncrementalSync(pair: SyncPair, changedURLs: [URL], options: SyncOptions) {
        let manager = SyncManager()
        manager.onProgress = { [weak self] message in
            DispatchQueue.main.async {
                if self?.selectedPair?.id == pair.id {
                    self?.pairDetailVC.showStatusMessage(message)
                }
            }
        }
        syncQueue.async { [weak self] in
            do {
                let result = try manager.syncIncremental(pair: pair, changedURLs: changedURLs, options: options)
                DispatchQueue.main.async {
                    if self?.selectedPair?.id == pair.id {
                        self?.pairDetailVC.applySyncResult(result)
                    }
                    self?.pairListVC.reload()
                }
            } catch {
                DispatchQueue.main.async {
                    self?.presentError(error)
                }
            }
        }
    }

    // MARK: - Sheets

    func showSettings(for pair: SyncPair?) {
        let vc = SettingsViewController(pair: pair)
        vc.onSave = { [weak self] savedPair in
            if let sheetWindow = vc.view.window, let parent = sheetWindow.sheetParent {
                parent.endSheet(sheetWindow)
            } else {
                self?.window?.contentViewController?.dismiss(vc)
            }
            WatcherCoordinator.shared.activate(pair: savedPair)
            self?.pairListVC.reload()
            if self?.selectedPair?.id == savedPair.id {
                self?.selectedPair = savedPair             // refreshes headers, clears tree
                self?.pairDetailVC.reload(pair: savedPair) // auto-rescan after settings change
            }
        }
        window?.contentViewController?.presentAsSheet(vc)
    }

    func showConflictResolution(diff: FileDiff, pair: SyncPair) {
        let vc = ConflictResolutionViewController(diff: diff, pair: pair)
        vc.onResolved = { [weak self] in
            self?.window?.contentViewController?.dismiss(vc)
            self?.pairDetailVC.reload(pair: pair)
        }
        window?.contentViewController?.presentAsSheet(vc)
    }

    func showBackupHistory(for pair: SyncPair) {
        let vc = BackupHistoryViewController(pair: pair)
        window?.contentViewController?.presentAsSheet(vc)
    }
}
