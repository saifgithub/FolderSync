import AppKit
import QuickLookUI

/// Modal sheet displayed when the user chooses to resolve a clash manually.
/// Shows side-by-side metadata + Quick Look previews and lets the user
/// pick which side is authoritative — or keep both (rename one).
final class ConflictResolutionViewController: NSViewController {

    // MARK: - Input
    private let diff: FileDiff
    private let pair: SyncPair

    // MARK: - Output
    var onResolved: (() -> Void)?

    // MARK: - UI
    private let titleLabel     = NSTextField(labelWithString: "")
    private let leftPanel      = FileMetadataPanel(side: .left)
    private let rightPanel     = FileMetadataPanel(side: .right)
    private let useLeftButton  = NSButton(title: "Force Copy Left → Right", target: nil, action: nil)
    private let useRightButton = NSButton(title: "Force Copy Left ← Right", target: nil, action: nil)
    private let keepBothButton = NSButton(title: "Keep Both (rename Left copy)", target: nil, action: nil)
    private let cancelButton   = NSButton(title: "Decide Later", target: nil, action: nil)

    // MARK: - Init
    init(diff: FileDiff, pair: SyncPair) {
        self.diff = diff
        self.pair = pair
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 680, height: 440))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Resolve Clash"
        buildLayout()
        populate()
    }

    // MARK: - Populate

    private func populate() {
        titleLabel.stringValue = "⚠️  Clash: \"\(diff.relativePath)\""
        titleLabel.font = .boldSystemFont(ofSize: 14)

        leftPanel.configure(with: diff.leftFile, snapshotDate: diff.leftSnapshot?.syncedAt)
        rightPanel.configure(with: diff.rightFile, snapshotDate: diff.rightSnapshot?.syncedAt)
    }

    // MARK: - Build layout

    private func buildLayout() {
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let panelStack = NSStackView(views: [leftPanel, rightPanel])
        panelStack.orientation = .horizontal
        panelStack.distribution = .fillEqually
        panelStack.spacing = 12
        panelStack.translatesAutoresizingMaskIntoConstraints = false

        for btn in [useLeftButton, useRightButton, keepBothButton, cancelButton] {
            btn.bezelStyle = .rounded
            btn.target = self
        }
        useLeftButton.action  = #selector(chooseLeft)
        useRightButton.action = #selector(chooseRight)
        keepBothButton.action = #selector(keepBoth)
        cancelButton.action   = #selector(decideLater)

        useLeftButton.keyEquivalent  = ""
        useRightButton.keyEquivalent = ""

        let btnStack = NSStackView(views: [keepBothButton, NSView(), cancelButton, useRightButton, useLeftButton])
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(titleLabel)
        view.addSubview(panelStack)
        view.addSubview(btnStack)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            panelStack.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 12),
            panelStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            panelStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            panelStack.bottomAnchor.constraint(equalTo: btnStack.topAnchor, constant: -12),

            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Resolution actions

    @objc private func chooseLeft() {
        confirmThenResolve(keepSide: .left)
    }

    @objc private func chooseRight() {
        confirmThenResolve(keepSide: .right)
    }

    // MARK: - Confirmation

    /// Per-pair UserDefaults key — different pairs can have different confirmation preferences.
    private var skipConfirmKey: String {
        "FolderSync.skipForceCopyConfirmation.pair\(pair.id ?? 0)"
    }

    /// Shows a confirmation alert (unless the user previously checked "Don't ask me again"
    /// *for this specific pair*), then calls `resolve(keepSide:)` if the user proceeds.
    private func confirmThenResolve(keepSide: SyncSide) {
        if UserDefaults.standard.bool(forKey: skipConfirmKey) {
            resolve(keepSide: keepSide)
            return
        }

        let srcLabel = keepSide == .left ? "Left" : "Right"
        let dstLabel = keepSide == .left ? "Right" : "Left"
        let dirLabel = keepSide.arrowTo(keepSide.opposite)
        let fileName = URL(fileURLWithPath: diff.relativePath).lastPathComponent

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Force Copy \(dirLabel)?"
        alert.informativeText = """
            "\(fileName)" on the \(dstLabel) side will be permanently overwritten \
            with the \(srcLabel) version.
            \(pair.backupEnabled ? "The overwritten file will be backed up first." : "⚠️  Backup is disabled — the overwritten file cannot be recovered.")
            This action applies to this single file only.
            """
        alert.addButton(withTitle: "Force Copy \(dirLabel)")
        alert.addButton(withTitle: "Cancel")

        // "Don't ask me again" checkbox — scoped to this folder pair only.
        let checkbox = NSButton(checkboxWithTitle: "Don't ask me again for \"\(pair.name)\"", target: nil, action: nil)
        checkbox.state = .off
        alert.accessoryView = checkbox

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        if checkbox.state == .on {
            UserDefaults.standard.set(true, forKey: skipConfirmKey)
        }
        resolve(keepSide: keepSide)
    }

    @objc private func keepBoth() {
        // Rename left copy in-place with a timestamp suffix, then treat as two separate files
        guard let leftFile = diff.leftFile else { dismiss(self); return }
        let renamedURL = leftFile.absoluteURL.deletingLastPathComponent()
            .appendingPathComponent(BackupRecord.makeBackupFileName(for: leftFile.absoluteURL))
        do {
            try FileOperator().move(from: leftFile.absoluteURL, to: renamedURL)
            onResolved?()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func decideLater() {
        dismiss(self)
    }

    // MARK: - Resolve

    private func resolve(keepSide: SyncSide) {
        guard
            let srcFile = keepSide == .left ? diff.leftFile  : diff.rightFile,
            let dstFile = keepSide == .left ? diff.rightFile : diff.leftFile
        else { dismiss(self); return }

        let op = FileOperator()
        let backup = BackupManager()
        do {
            // Back up the losing file first (if backup is enabled)
            if pair.backupEnabled {
                try backup.backup(
                    sourceURL: dstFile.absoluteURL,
                    relativePath: diff.relativePath,
                    side: keepSide.opposite,
                    pair: pair
                )
            }
            // Copy winner over loser
            try op.copy(from: srcFile.absoluteURL, to: dstFile.absoluteURL)
            onResolved?()
        } catch {
            NSApp.presentError(error)
        }
    }
}

// MARK: - FileMetadataPanel

/// Small panel showing file metadata (size, dates) and a QLPreviewView for one side.
private final class FileMetadataPanel: NSView {

    private let side: SyncSide
    private let nameLabel     = NSTextField(labelWithString: "—")
    private let sizeLabel     = NSTextField(labelWithString: "Size: —")
    private let modDateLabel  = NSTextField(labelWithString: "Modified: —")
    private let syncDateLabel = NSTextField(labelWithString: "Last synced: —")
    private let previewView   = QLPreviewView(frame: .zero, style: .compact)!

    init(side: SyncSide) {
        self.side = side
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        buildLayout()
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(with file: ScannedFile?, snapshotDate: Date?) {
        let sideTitle = side.displayName
        nameLabel.stringValue     = "\(sideTitle): " + (file?.absoluteURL.lastPathComponent ?? "—")
        sizeLabel.stringValue     = "Size: "    + (file.map { $0.sizeBytes.formattedSize } ?? "—")
        modDateLabel.stringValue  = "Modified: " + (file?.modifiedAt.formatted() ?? "—")
        syncDateLabel.stringValue = "Last sync: " + (snapshotDate?.formatted() ?? "Never")
        nameLabel.font = .boldSystemFont(ofSize: 12)

        if let url = file?.absoluteURL {
            previewView.previewItem = url as QLPreviewItem
        }
    }

    private func buildLayout() {
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth  = 1
        layer?.borderColor  = NSColor.separatorColor.cgColor

        previewView.translatesAutoresizingMaskIntoConstraints = false
        previewView.autostarts = true
        for lbl in [nameLabel, sizeLabel, modDateLabel, syncDateLabel] {
            lbl.translatesAutoresizingMaskIntoConstraints = false
        }

        let infoStack = NSStackView(views: [nameLabel, sizeLabel, modDateLabel, syncDateLabel])
        infoStack.orientation = .vertical
        infoStack.spacing = 4
        infoStack.alignment = .leading
        infoStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(infoStack)
        addSubview(previewView)

        NSLayoutConstraint.activate([
            infoStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            infoStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            infoStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            previewView.topAnchor.constraint(equalTo: infoStack.bottomAnchor, constant: 8),
            previewView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            previewView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            previewView.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10),
            previewView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        ])
    }
}
