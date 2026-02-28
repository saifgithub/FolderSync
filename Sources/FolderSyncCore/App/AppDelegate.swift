import AppKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // On first launch, ask where to store the database.
        pickDatabaseLocationIfNeeded()

        // Initialise database
        do {
            try DatabaseManager.shared.setup()
        } catch {
            fatalError("Database setup failed: \(error)")
        }

        // Build and show main window
        let wc = MainWindowController()
        mainWindowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    // MARK: - First-launch DB location prompt

    private func pickDatabaseLocationIfNeeded() {
        // Already configured — nothing to do.
        guard UserDefaults.standard.string(forKey: DatabaseManager.dbPathKey) == nil else { return }

        // Compute the default URL to show in the prompt.
        let defaultURL = (try? DatabaseManager.defaultDatabaseURL())
            ?? URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Library/Application Support/FolderSync/foldersync.sqlite")

        let alert = NSAlert()
        alert.messageText     = "Where should FolderSync store its database?"
        alert.informativeText = """
            FolderSync keeps all your sync pairs, rules, and history in a SQLite database.

            Default location:
            \(defaultURL.path)

            Choose a custom location if you want the database on a synced or shared drive.
            """
        alert.addButton(withTitle: "Use Default")
        alert.addButton(withTitle: "Choose Location…")
        alert.alertStyle = .informational

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            // Use default
            UserDefaults.standard.set(defaultURL.path, forKey: DatabaseManager.dbPathKey)
        } else {
            // Open a save panel
            let panel = NSSavePanel()
            panel.title             = "Choose Database Location"
            panel.message           = "Pick a folder and filename for the FolderSync database."
            panel.nameFieldStringValue = "foldersync.sqlite"
            panel.directoryURL      = defaultURL.deletingLastPathComponent()
            panel.allowedContentTypes = [.init(filenameExtension: "sqlite") ?? .data]
            panel.canCreateDirectories = true

            if panel.runModal() == .OK, let chosen = panel.url {
                // If a file already exists at the chosen path, ask whether to use it.
                if FileManager.default.fileExists(atPath: chosen.path) {
                    let a = NSAlert()
                    a.messageText     = "A database already exists here"
                    a.informativeText = "FolderSync found an existing database at:\n\(chosen.path)\n\nDo you want to use this existing database (e.g. from another computer), or start completely fresh?"
                    a.addButton(withTitle: "Use Existing")
                    a.addButton(withTitle: "Start Fresh")
                    a.alertStyle = .informational
                    let r = a.runModal()
                    if r == .alertSecondButtonReturn {
                        // Start Fresh — remove the existing file so GRDB creates a clean one
                        try? FileManager.default.removeItem(at: chosen)
                    }
                    // Either way, use this path
                }
                UserDefaults.standard.set(chosen.path, forKey: DatabaseManager.dbPathKey)
            } else {
                // User cancelled the panel — fall back to default.
                UserDefaults.standard.set(defaultURL.path, forKey: DatabaseManager.dbPathKey)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Stop all active watchers
        WatcherCoordinator.shared.stopAll()
    }

    // MARK: - Preferences (Cmd+,)

    @objc func orderFrontPreferencesPanel(_ sender: Any?) {
        AppPreferencesWindowController.shared.showWindow(sender)
        AppPreferencesWindowController.shared.window?.makeKeyAndOrderFront(sender)
        NSApp.activate(ignoringOtherApps: true)
    }
}
