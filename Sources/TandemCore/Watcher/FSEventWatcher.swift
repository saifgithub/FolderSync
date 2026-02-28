import Foundation
import CoreServices

/// Wraps the macOS FSEvents C API to watch one or two directories for changes.
/// Fires a debounced callback carrying the accumulated set of changed URLs.
final class FSEventWatcher {

    // MARK: - Configuration
    let paths: [String]
    /// Called on a background queue with all URLs that changed during the debounce window.
    var onChange: (([URL]) -> Void)?

    // MARK: - Private state
    private var streamRef: FSEventStreamRef?
    private var debounceTimer: DispatchSourceTimer?
    private var pendingURLs: [URL] = []   // accumulated during the debounce window
    private let callbackQueue = DispatchQueue(label: "com.tandem.fsevents", qos: .utility)
    private let debounceInterval: TimeInterval

    // MARK: - Init
    init(paths: [String], debounceInterval: TimeInterval = 2.0) {
        self.paths = paths
        self.debounceInterval = debounceInterval
    }

    deinit { stop() }

    // MARK: - Start / Stop

    func start() {
        guard streamRef == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        // kFSEventStreamCreateFlagUseCFTypes delivers paths as a CFArray of CFStrings.
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FSEventWatcher>.fromOpaque(info).takeUnretainedValue()
            let pathsArray = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as NSArray
            var urls: [URL] = []
            for i in 0..<numEvents {
                if let path = pathsArray[i] as? String {
                    urls.append(URL(fileURLWithPath: path))
                }
            }
            // Already on callbackQueue (set via FSEventStreamSetDispatchQueue)
            watcher.pendingURLs.append(contentsOf: urls)
            watcher.scheduleDebounce()
        }

        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagNoDefer    |
                kFSEventStreamCreateFlagUseCFTypes
            )
        )

        guard let stream else { return }
        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, callbackQueue)
        FSEventStreamStart(stream)
    }

    func stop() {
        debounceTimer?.cancel()
        debounceTimer = nil
        pendingURLs.removeAll()

        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    // MARK: - Debounce
    // Must be called on callbackQueue.

    private func scheduleDebounce() {
        debounceTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: callbackQueue)
        timer.schedule(deadline: .now() + debounceInterval)
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            let urls = pendingURLs
            pendingURLs.removeAll()
            onChange?(urls)
        }
        timer.resume()
        debounceTimer = timer
    }
}

