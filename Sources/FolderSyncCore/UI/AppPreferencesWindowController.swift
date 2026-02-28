import AppKit
import UniformTypeIdentifiers

/// App-level preferences window (Cmd+,).
/// Currently exposes the database storage location.
final class AppPreferencesWindowController: NSWindowController {

    // MARK: - Singleton (so Cmd+, re-focuses the same window)
    static let shared = AppPreferencesWindowController()

    // MARK: - UI
    private let pathField   = NSTextField()
    private let changeBtn   = NSButton(title: "Change…",         target: nil, action: nil)
    private let revealBtn   = NSButton(title: "Show in Finder",  target: nil, action: nil)

    // MARK: - Init

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 160),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "FolderSync Preferences"
        window.setFrameAutosaveName("AppPreferencesWindow")
        super.init(window: window)
        buildLayout()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Layout

    private func buildLayout() {
        guard let window else { return }

        // ── Section header ──────────────────────────────────────────────────
        let sectionLabel = NSTextField(labelWithString: "DATABASE LOCATION")
        sectionLabel.font        = .systemFont(ofSize: 10, weight: .semibold)
        sectionLabel.textColor   = .secondaryLabelColor

        // ── Path field (read-only) ──────────────────────────────────────────
        pathField.isEditable    = false
        pathField.isSelectable  = true
        pathField.isBezeled     = true
        pathField.bezelStyle    = .roundedBezel
        pathField.lineBreakMode = .byTruncatingMiddle
        pathField.cell?.usesSingleLineMode = true
        refreshPath()

        // ── Buttons ─────────────────────────────────────────────────────────
        changeBtn.bezelStyle = .rounded
        changeBtn.target     = self
        changeBtn.action     = #selector(changeTapped)

        revealBtn.bezelStyle = .rounded
        revealBtn.target     = self
        revealBtn.action     = #selector(revealTapped)

        let btnRow = NSStackView(views: [revealBtn, changeBtn])
        btnRow.spacing   = 8
        btnRow.alignment = .centerY

        // ── Restart note ────────────────────────────────────────────────────
        let note = NSTextField(wrappingLabelWithString:
            "Changing the location takes effect after you restart FolderSync.")
        note.font      = .systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor

        // ── Outer stack ─────────────────────────────────────────────────────
        let stack = NSStackView(views: [sectionLabel, pathField, btnRow, note])
        stack.orientation = .vertical
        stack.alignment   = .leading
        stack.spacing     = 8
        stack.edgeInsets  = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        stack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            pathField.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -40),
        ])
        window.contentView = container
    }

    // MARK: - Helpers

    private func refreshPath() {
        let current = UserDefaults.standard.string(forKey: DatabaseManager.dbPathKey)
            ?? (try? DatabaseManager.defaultDatabaseURL().path)
            ?? "—"
        pathField.stringValue = current
    }

    // MARK: - Actions

    @objc private func revealTapped() {
        let path = pathField.stringValue
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    @objc private func changeTapped() {
        guard let window else { return }

        let currentURL = URL(fileURLWithPath: pathField.stringValue)

        let panel = NSSavePanel()
        panel.title                  = "Choose New Database Location"
        panel.message                = "Pick a folder and filename for the FolderSync database."
        panel.nameFieldStringValue   = currentURL.lastPathComponent
        panel.directoryURL           = currentURL.deletingLastPathComponent()
        panel.canCreateDirectories   = true
        if let type = UTType(filenameExtension: "sqlite") {
            panel.allowedContentTypes = [type]
        }

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let newURL = panel.url else { return }
            guard newURL != currentURL else { return }
            self.confirmMigration(from: currentURL, to: newURL)
        }
    }

    private func confirmMigration(from src: URL, to dst: URL) {
        guard let window else { return }

        let srcExists = FileManager.default.fileExists(atPath: src.path)
        let dstExists = FileManager.default.fileExists(atPath: dst.path)

        let alert = NSAlert()
        alert.alertStyle = .informational

        if dstExists {
            // Destination already has a database — most likely from another computer.
            alert.messageText     = "A database already exists at that location"
            alert.informativeText = "FolderSync found an existing database at:\n\(dst.path)\n\nDo you want to use this existing database (e.g. migrated from another computer), or overwrite it by moving your current database there?"
            alert.addButton(withTitle: "Use Existing")          // 1st
            if srcExists {
                alert.addButton(withTitle: "Overwrite with Current") // 2nd
            }
            alert.addButton(withTitle: "Cancel")                // last

            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:                      // Use Existing
                    self.applyNewPath(dst)
                case .alertSecondButtonReturn where srcExists:     // Overwrite with Current
                    self.migrateDatabase(from: src, to: dst)
                default: break                                     // Cancel
                }
            }
        } else if srcExists {
            // Normal move-or-fresh flow.
            alert.messageText     = "Move existing database?"
            alert.informativeText = "Do you want to move your current database to the new location, or start with a fresh (empty) database?\n\nNew location:\n\(dst.path)"
            alert.addButton(withTitle: "Move Database")   // 1st
            alert.addButton(withTitle: "Start Fresh")     // 2nd
            alert.addButton(withTitle: "Cancel")          // 3rd

            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                switch response {
                case .alertFirstButtonReturn:  self.migrateDatabase(from: src, to: dst)
                case .alertSecondButtonReturn: self.applyNewPath(dst)
                default: break
                }
            }
        } else {
            // No source, no destination — just point to the new empty location.
            alert.messageText     = "Use new location?"
            alert.informativeText = "A fresh database will be created at:\n\(dst.path)"
            alert.addButton(withTitle: "Use New Location")
            alert.addButton(withTitle: "Cancel")

            alert.beginSheetModal(for: window) { [weak self] response in
                guard let self else { return }
                if response == .alertFirstButtonReturn { self.applyNewPath(dst) }
            }
        }
    }

    private func migrateDatabase(from src: URL, to dst: URL) {
        do {
            try FileManager.default.createDirectory(
                at: dst.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: dst.path) {
                try FileManager.default.removeItem(at: dst)
            }
            try FileManager.default.copyItem(at: src, to: dst)
            applyNewPath(dst)
        } catch {
            showError("Failed to move database: \(error.localizedDescription)")
        }
    }

    private func applyNewPath(_ url: URL) {
        UserDefaults.standard.set(url.path, forKey: DatabaseManager.dbPathKey)
        refreshPath()
        showRestartPrompt()
    }

    private func showRestartPrompt() {
        guard let window else { return }
        let a = NSAlert()
        a.messageText     = "Restart Required"
        a.informativeText = "The new database location will be used the next time FolderSync starts."
        a.addButton(withTitle: "OK")
        a.alertStyle = .informational
        a.beginSheetModal(for: window) { _ in }
    }

    private func showError(_ message: String) {
        guard let window else { return }
        let a = NSAlert()
        a.messageText     = "Error"
        a.informativeText = message
        a.addButton(withTitle: "OK")
        a.alertStyle = .critical
        a.beginSheetModal(for: window) { _ in }
    }
}
