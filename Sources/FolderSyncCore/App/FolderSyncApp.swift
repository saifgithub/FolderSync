import AppKit

/// Public entry point called by the executable target.
/// Keeps AppDelegate internal to FolderSyncCore.
public enum FolderSyncApp {
    // Hold a strong reference alongside NSApp's unowned delegation slot.
    private static var appDelegate: AppDelegate?

    public static func run() {
        NSApplication.shared.setActivationPolicy(.regular)
        let delegate = AppDelegate()
        appDelegate = delegate
        NSApplication.shared.delegate = delegate
        NSApplication.shared.run()
    }
}
