import Foundation

/// Manages one `FSEventWatcher` + one `ScheduledTicker` per active sync pair.
/// Referenced from `AppDelegate` to start/stop all watchers.
final class WatcherCoordinator {

    static let shared = WatcherCoordinator()
    private init() {}

    // MARK: - Active watchers

    /// Keyed by SyncPair.id
    private var fsWatchers: [Int64: FSEventWatcher]    = [:]
    private var tickers:    [Int64: ScheduledTicker]   = [:]

    /// Callback injected by the app when a pair needs a sync pass.
    /// `changedURLs` is non-empty for real-time FSEvent triggers (incremental sync),
    /// empty for scheduled ticks (full sync).
    var onSyncNeeded: ((Int64, [URL]) -> Void)?

    // MARK: - Lifecycle

    /// Starts watchers appropriate for the pair's `syncMode`.
    func activate(pair: SyncPair) {
        guard let pairId = pair.id else { return }
        deactivate(pairId: pairId)  // stop existing watchers first

        switch pair.syncMode {
        case .manual:
            break

        case .realtime:
            startFSWatcher(for: pair, pairId: pairId)

        case .scheduled:
            startTicker(for: pair, pairId: pairId)

        case .all:
            startFSWatcher(for: pair, pairId: pairId)
            startTicker(for: pair, pairId: pairId)
        }
    }

    /// Stops and removes watchers for one pair.
    func deactivate(pairId: Int64) {
        fsWatchers[pairId]?.stop()
        fsWatchers.removeValue(forKey: pairId)
        tickers[pairId]?.stop()
        tickers.removeValue(forKey: pairId)
    }

    /// Stops everything (called on app termination).
    func stopAll() {
        fsWatchers.values.forEach { $0.stop() }
        tickers.values.forEach    { $0.stop() }
        fsWatchers.removeAll()
        tickers.removeAll()
    }

    // MARK: - Private

    private func startFSWatcher(for pair: SyncPair, pairId: Int64) {
        let watcher = FSEventWatcher(paths: [pair.leftPath, pair.rightPath])
        watcher.onChange = { [weak self] urls in
            self?.onSyncNeeded?(pairId, urls)
        }
        watcher.start()
        fsWatchers[pairId] = watcher
    }

    private func startTicker(for pair: SyncPair, pairId: Int64) {
        let ticker = ScheduledTicker()
        ticker.onTick = { [weak self] in
            // Empty URL list → caller should do a full sync
            self?.onSyncNeeded?(pairId, [])
        }
        ticker.start(intervalSeconds: TimeInterval(pair.scheduleIntervalSeconds))
        tickers[pairId] = ticker
    }
}
