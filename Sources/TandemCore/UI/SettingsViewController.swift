import AppKit

/// Sheet for creating or editing a sync pair, including exclusion rules.
final class SettingsViewController: NSViewController {

    // MARK: - Callback
    var onSave: ((SyncPair) -> Void)?

    // MARK: - State
    private var pair: SyncPair

    // MARK: - UI — General
    private let nameField        = NSTextField()
    private let leftPathField    = NSTextField()
    private let rightPathField   = NSTextField()
    private let leftBrowseBtn    = NSButton(title: "Browse…", target: nil, action: nil)
    private let rightBrowseBtn   = NSButton(title: "Browse…", target: nil, action: nil)
    private let syncModePopup    = NSPopUpButton()
    private let scheduleField    = NSTextField()
    private let backupCheckbox   = NSButton(checkboxWithTitle: "Enable secure backup", target: nil, action: nil)
    private let backupPathField  = NSTextField()
    private let backupBrowseBtn  = NSButton(title: "Browse…", target: nil, action: nil)
    private let checksumCheckbox = NSButton(checkboxWithTitle: "Use SHA-256 checksum (slower but accurate)", target: nil, action: nil)

    // MARK: - Exclusion rules tab
    private let tabView = NSTabView()
    private lazy var exclusionVC = ExclusionRulesViewController(pairId: pair.id)

    // MARK: - Buttons
    private let saveButton        = NSButton(title: "Save", target: nil, action: nil)
    private let cancelButton      = NSButton(title: "Cancel", target: nil, action: nil)
    private let resetWarningsBtn  = NSButton(title: "Reset Warnings…", target: nil, action: nil)

    // MARK: - Init
    init(pair: SyncPair?) {
        self.pair = pair ?? SyncPair(name: "", leftPath: "", rightPath: "")
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 560))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = pair.id == nil ? "New Sync Pair" : "Edit — \(pair.name)"
        populateFields()
        buildLayout()
    }

    // MARK: - Populate
    private func populateFields() {
        nameField.stringValue       = pair.name
        leftPathField.stringValue   = pair.leftPath
        rightPathField.stringValue  = pair.rightPath
        backupPathField.stringValue = pair.backupPath ?? ""
        scheduleField.stringValue   = String(pair.scheduleIntervalSeconds)
        backupCheckbox.state        = pair.backupEnabled ? .on : .off
        checksumCheckbox.state      = pair.checksumEnabled ? .on : .off

        SyncMode.allCases.forEach { syncModePopup.addItem(withTitle: $0.displayName) }
        if let idx = SyncMode.allCases.firstIndex(of: pair.syncMode) {
            syncModePopup.selectItem(at: idx)
        }
        updateBackupFieldVisibility()
    }

    // MARK: - Build layout

    private func buildLayout() {
        // ── General tab ─────────────────────────────────────────────────────
        let generalView = NSView()

        let form = formStack([
            labeledRow(label: "Pair Name",    control: nameField),
            labeledRow(label: "Left Folder",  control: pathRow(field: leftPathField,  button: leftBrowseBtn)),
            labeledRow(label: "Right Folder", control: pathRow(field: rightPathField, button: rightBrowseBtn)),
            labeledRow(label: "Sync Mode",    control: syncModePopup),
            labeledRow(label: "Schedule (s)", control: scheduleField),
            labeledRow(label: "Backup",       control: backupCheckbox),
            labeledRow(label: "Backup Folder",control: pathRow(field: backupPathField, button: backupBrowseBtn)),
            checksumCheckbox
        ])
        form.translatesAutoresizingMaskIntoConstraints = false
        generalView.addSubview(form)
        NSLayoutConstraint.activate([
            form.topAnchor.constraint(equalTo: generalView.topAnchor, constant: 16),
            form.leadingAnchor.constraint(equalTo: generalView.leadingAnchor, constant: 16),
            form.trailingAnchor.constraint(equalTo: generalView.trailingAnchor, constant: -16)
        ])

        // Wire browse buttons
        leftBrowseBtn.target  = self;  leftBrowseBtn.action  = #selector(browseLeft)
        rightBrowseBtn.target = self;  rightBrowseBtn.action = #selector(browseRight)
        backupBrowseBtn.target = self; backupBrowseBtn.action = #selector(browseBackup)
        backupCheckbox.target  = self; backupCheckbox.action  = #selector(backupToggled)

        // ── Tabs ─────────────────────────────────────────────────────────────
        addChild(exclusionVC)
        let generalTab   = NSTabViewItem(identifier: "general")
        generalTab.label = "General"
        generalTab.view  = generalView

        let exclusionTab   = NSTabViewItem(identifier: "exclusions")
        exclusionTab.label = "Exclusions"
        exclusionTab.view  = exclusionVC.view

        tabView.addTabViewItem(generalTab)
        tabView.addTabViewItem(exclusionTab)
        tabView.translatesAutoresizingMaskIntoConstraints = false

        // ── Save / Cancel ────────────────────────────────────────────────────
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"
        saveButton.target = self
        saveButton.action = #selector(save)

        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancel)

        resetWarningsBtn.bezelStyle = .rounded
        resetWarningsBtn.target = self
        resetWarningsBtn.action = #selector(resetWarnings)
        resetWarningsBtn.toolTip = "Re-enable all confirmation dialogs that were dismissed with \"Don't ask me again\"."

        // Reset button sits at the far left; Save/Cancel are at the right.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let btnStack = NSStackView(views: [resetWarningsBtn, spacer, cancelButton, saveButton])
        btnStack.orientation = .horizontal
        btnStack.spacing = 8
        btnStack.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(tabView)
        view.addSubview(btnStack)

        NSLayoutConstraint.activate([
            tabView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            tabView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tabView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tabView.bottomAnchor.constraint(equalTo: btnStack.topAnchor, constant: -8),

            btnStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            btnStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            btnStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16)
        ])
    }

    // MARK: - Form helpers

    private func formStack(_ views: [NSView]) -> NSStackView {
        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading
        return stack
    }

    private func labeledRow(label: String, control: NSView) -> NSView {
        let lbl = NSTextField(labelWithString: label + ":")
        lbl.font = .systemFont(ofSize: 12)
        lbl.alignment = .right
        lbl.widthAnchor.constraint(equalToConstant: 110).isActive = true
        let row = NSStackView(views: [lbl, control])
        row.orientation  = .horizontal
        row.spacing      = 8
        row.alignment    = .centerY
        return row
    }

    private func pathRow(field: NSTextField, button: NSButton) -> NSView {
        field.placeholderString = "Choose folder…"
        field.isEditable = true
        field.widthAnchor.constraint(equalToConstant: 300).isActive = true
        let row = NSStackView(views: [field, button])
        row.orientation = .horizontal
        row.spacing = 4
        return row
    }

    private func updateBackupFieldVisibility() {
        backupPathField.isEnabled  = backupCheckbox.state == .on
        backupBrowseBtn.isEnabled  = backupCheckbox.state == .on
    }

    // MARK: - Actions

    @objc private func browseLeft()  { pickFolder(for: leftPathField,  mirrorOf: rightPathField) }
    @objc private func browseRight() { pickFolder(for: rightPathField, mirrorOf: leftPathField) }
    @objc private func browseBackup() { pickFolder(for: backupPathField) }
    @objc private func backupToggled() { updateBackupFieldVisibility() }

    @objc private func resetWarnings() {
        guard let pairId = pair.id else {
            let alert = NSAlert()
            alert.messageText = "Save First"
            alert.informativeText = "Save this pair before resetting its warnings."
            alert.runModal()
            return
        }
        let key = "Tandem.skipForceCopyConfirmation.pair\(pairId)"
        guard UserDefaults.standard.bool(forKey: key) else {
            let alert = NSAlert()
            alert.messageText = "No Warnings Suppressed"
            alert.informativeText = "All confirmation dialogs for \"\(pair.name)\" are already active — nothing to reset."
            alert.runModal()
            return
        }
        let alert = NSAlert()
        alert.messageText = "Reset Suppressed Warnings for \"\(pair.name)\"?"
        alert.informativeText = "Confirmation dialogs that were dismissed with \"Don't ask me again\" for this folder pair will be shown again."
        alert.addButton(withTitle: "Reset")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func pickFolder(for textField: NSTextField, mirrorOf sourceField: NSTextField? = nil) {
        let panel = NSOpenPanel()
        panel.canChooseFiles       = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Choose"

        // Present as a child sheet of the settings sheet — avoids nested modal loops
        // that freeze navigation in the open panel when runModal() is used inside a sheet.
        guard let window = view.window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }

            // If this is the right-side picker and a left path is already set,
            // offer to create a matching named subfolder automatically.
            if let sourceField,
               !sourceField.stringValue.isEmpty {
                let otherName = (sourceField.stringValue as NSString).lastPathComponent
                let pickedName = url.lastPathComponent
                if !otherName.isEmpty, pickedName != otherName {
                    let alert = NSAlert()
                    alert.messageText = "Create Subfolder \"\(otherName)\"?"
                    alert.informativeText = "The other side uses a folder named \"\(otherName)\", but you selected \"\(pickedName)\".\n\nWould you like to use \"\(pickedName)/\(otherName)\" so both sides share the same folder name? The subfolder will be created for you when you save."
                    alert.addButton(withTitle: "Create Subfolder")
                    alert.addButton(withTitle: "Use As-Is")
                    if alert.runModal() == .alertFirstButtonReturn {
                        textField.stringValue = url.appendingPathComponent(otherName).path
                        return
                    }
                }
            }
            textField.stringValue = url.path
        }
    }

    @objc private func save() {
        // Validate
        guard !nameField.stringValue.trimmingCharacters(in: .whitespaces).isEmpty else {
            showValidationError("Please enter a name for this pair.")
            return
        }
        guard !leftPathField.stringValue.isEmpty, !rightPathField.stringValue.isEmpty else {
            showValidationError("Both left and right folders must be specified.")
            return
        }

        // Build updated pair
        pair.name        = nameField.stringValue.trimmingCharacters(in: .whitespaces)
        pair.leftPath    = leftPathField.stringValue
        pair.rightPath   = rightPathField.stringValue
        pair.syncMode    = SyncMode.allCases[syncModePopup.indexOfSelectedItem]
        pair.scheduleIntervalSeconds = Int(scheduleField.stringValue) ?? 300
        pair.backupEnabled   = backupCheckbox.state == .on
        pair.backupPath      = backupCheckbox.state == .on ? backupPathField.stringValue : nil
        pair.checksumEnabled = checksumCheckbox.state == .on

        do {
            // Create the right (and left) folder if they don't exist yet.
            // This covers the case where the user confirmed "Create Subfolder" above.
            for path in [pair.leftPath, pair.rightPath] where !path.isEmpty {
                let url = URL(fileURLWithPath: path)
                if !FileManager.default.fileExists(atPath: path) {
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                }
            }
            try DatabaseManager.shared.write { db in
                if pair.id == nil {
                    try pair.insert(db)
                } else {
                    try pair.update(db)
                }
            }
            onSave?(pair)
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func cancel() {
        if let window = view.window, let parent = window.sheetParent {
            parent.endSheet(window)
        } else {
            dismiss(self)
        }
    }

    private func showValidationError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Validation Error"
        alert.informativeText = message
        alert.runModal()
    }
}
