import Foundation

/// Fires a repeating callback on a background queue at a configurable interval.
final class ScheduledTicker {

    var onTick: (() -> Void)?
    private var timer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "com.tandem.ticker", qos: .utility)

    // MARK: - Start / Stop

    func start(intervalSeconds: TimeInterval) {
        guard timer == nil else { return }
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + intervalSeconds, repeating: intervalSeconds)
        t.setEventHandler { [weak self] in self?.onTick?() }
        t.resume()
        timer = t
    }

    func stop() {
        timer?.cancel()
        timer = nil
    }

    deinit { stop() }
}
