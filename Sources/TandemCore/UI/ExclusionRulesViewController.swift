import AppKit

private extension NSUserInterfaceItemIdentifier {
    static let enabledCol = NSUserInterfaceItemIdentifier("EnabledCol")
    static let typeCol    = NSUserInterfaceItemIdentifier("TypeCol")
    static let patternCol = NSUserInterfaceItemIdentifier("PatternCol")
    static let noteCol    = NSUserInterfaceItemIdentifier("NoteCol")
}

// MARK: - PopUpBridge
/// Bridges NSPopUpButton selection changes to a closure, needed inside runModal() alert sheets.
private final class PopUpBridge: NSObject {
    private let onChange: (Int) -> Void
    init(_ onChange: @escaping (Int) -> Void) { self.onChange = onChange }
    @objc func selectionChanged(_ sender: NSPopUpButton) { onChange(sender.indexOfSelectedItem) }
}

/// Manages exclusion rules for a single sync pair (`pairId` non-nil) or
/// the global rule set (`pairId` nil, rules apply to every pair).
///
/// Embed as a child view-controller tab inside `SettingsViewController` (pair mode)
/// or `AppPreferencesWindowController` (global mode).
final class ExclusionRulesViewController: NSViewController {

    // MARK: - Mode
    enum Mode {
        /// Rules scoped to one sync pair.
        case pair(pairId: Int64)
        /// Global rules — applied to every sync pair.
        case global
    }

    // MARK: - State
    private let mode: Mode
    private var rules: [ExclusionRule] = []

    // MARK: - Preset library
    struct Preset {
        let label:    String
        let ruleType: ExclusionRule.RuleType
        let pattern:  String
        let note:     String
    }

    // Groups: (groupTitle, [Preset])
    static let presetGroups: [(String, [Preset])] = [
        ("macOS", [
            Preset(label: ".DS_Store",          ruleType: .filename, pattern: ".DS_Store",          note: "macOS folder metadata"),
            Preset(label: ".localized",          ruleType: .filename, pattern: ".localized",          note: "macOS localisation stub"),
            Preset(label: ".Spotlight-V100",     ruleType: .folder,   pattern: ".Spotlight-V100/",   note: "Spotlight index"),
            Preset(label: ".Trashes",            ruleType: .folder,   pattern: ".Trashes/",          note: "Trash folder"),
            Preset(label: ".fseventsd",          ruleType: .folder,   pattern: ".fseventsd/",        note: "FSEvents journal"),
            Preset(label: "__MACOSX",            ruleType: .folder,   pattern: "__MACOSX/",          note: "ZIP resource forks"),
        ]),
        ("Windows", [
            Preset(label: "Thumbs.db",           ruleType: .filename, pattern: "Thumbs.db",          note: "Windows thumbnail cache"),
            Preset(label: "desktop.ini",         ruleType: .filename, pattern: "desktop.ini",        note: "Windows folder settings"),
            Preset(label: "System Volume Information", ruleType: .folder, pattern: "System Volume Information/", note: "Windows system folder"),
        ]),
        ("Temp & Build", [
            Preset(label: "*.tmp",               ruleType: .glob,     pattern: "*.tmp",              note: "Temporary files"),
            Preset(label: "*.log",               ruleType: .glob,     pattern: "*.log",              note: "Log files"),
            Preset(label: "*.bak",               ruleType: .glob,     pattern: "*.bak",              note: "Backup files"),
            Preset(label: "*.swp",               ruleType: .glob,     pattern: "*.swp",              note: "Vim swap files"),
            Preset(label: ".git/",               ruleType: .folder,   pattern: ".git/",             note: "Git repository data"),
            Preset(label: "node_modules/",       ruleType: .folder,   pattern: "node_modules/",     note: "npm packages"),
            Preset(label: "__pycache__/",        ruleType: .folder,   pattern: "__pycache__/",      note: "Python bytecode cache"),
            Preset(label: ".cache/",             ruleType: .folder,   pattern: ".cache/",           note: "Generic cache folder"),
            Preset(label: ".gradle/",            ruleType: .folder,   pattern: ".gradle/",          note: "Gradle build cache"),
            Preset(label: "build/",              ruleType: .folder,   pattern: "build/",            note: "Build output folder"),
            Preset(label: "dist/",               ruleType: .folder,   pattern: "dist/",             note: "Distribution output folder"),
            Preset(label: ".next/",              ruleType: .folder,   pattern: ".next/",            note: "Next.js build output"),
        ]),
        ("Office / Lock files", [
            Preset(label: "~$* (Office locks)",  ruleType: .glob,     pattern: "~$*",               note: "Microsoft Office lock files"),
            Preset(label: ".~lock.*",            ruleType: .glob,     pattern: ".~lock.*",          note: "LibreOffice lock files"),
        ]),
    ]

    // MARK: - UI
    private let headerLabel     = NSTextField(labelWithString: "")
    private let tableView       = NSTableView()
    private let scrollView      = NSScrollView()
    private let addButton       = NSButton(title: "+ Add",       target: nil, action: nil)
    private let removeButton    = NSButton(title: "Remove",      target: nil, action: nil)
    private let duplicateButton = NSButton(title: "Duplicate",   target: nil, action: nil)
    private let presetsButton   = NSButton(title: "Presets ▾",  target: nil, action: nil)
    private let exportButton    = NSButton(title: "Export…",    target: nil, action: nil)
    private let importButton    = NSButton(title: "Import…",    target: nil, action: nil)

    // MARK: - Test bar
    private let testPathContainer = NSView()
    private let testPathField     = NSTextField()
    private let testMatchLabel    = NSTextField(labelWithString: "")

    // MARK: - Callback
    /// Fires whenever the rule list changes so owners can update a tab badge, etc.
    var onCountChanged: ((Int) -> Void)?

    // MARK: - Init

    /// Convenience init that mirrors the old API: pass nil for global mode.
    convenience init(pairId: Int64?) {
        if let id = pairId {
            self.init(mode: .pair(pairId: id))
        } else {
            self.init(mode: .global)
        }
    }

    init(mode: Mode) {
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle

    override func loadView() {
        view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupTableView()
        setupTestBar()
        setupButtons()
        setupLayout()
        loadRules()
    }

    // MARK: - Data

    func loadRules() {
        do {
            rules = try DatabaseManager.shared.read { db in
                switch self.mode {
                case .pair(let pairId):
                    return try ExclusionRule
                        .filter(sql: "pairId = ?", arguments: [pairId])
                        .order(ExclusionRule.Columns.sortOrder, ExclusionRule.Columns.id)
                        .fetchAll(db)
                case .global:
                    return try ExclusionRule
                        .filter(sql: "pairId IS NULL")
                        .order(ExclusionRule.Columns.sortOrder, ExclusionRule.Columns.id)
                        .fetchAll(db)
                }
            }
            tableView.reloadData()
            if isViewLoaded { updateTestMatchLabel() }
            onCountChanged?(rules.count)
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Setup

    private func setupHeader() {
        switch mode {
        case .pair:
            headerLabel.stringValue = "Rules below apply only to this sync pair.  Global rules (Preferences ▸ Global Exclusions) also apply automatically."
        case .global:
            headerLabel.stringValue = "Global rules apply to every sync pair in addition to each pair's own rules."
        }
        headerLabel.font      = .systemFont(ofSize: 11)
        headerLabel.textColor = .secondaryLabelColor
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)
    }

    private func setupTableView() {
        func col(_ title: String, id: NSUserInterfaceItemIdentifier,
                 width: CGFloat, resizable: Bool = true) -> NSTableColumn {
            let c = NSTableColumn(identifier: id)
            c.title        = title
            c.width        = width
            c.minWidth     = resizable ? 40 : width
            c.maxWidth     = resizable ? 2_000 : width
            c.resizingMask = resizable ? .userResizingMask : []
            return c
        }

        let enabledColumn = col("On",      id: .enabledCol, width: 36, resizable: false)
        let typeColumn    = col("Type",    id: .typeCol,    width: 118)
        let patternColumn = col("Pattern", id: .patternCol, width: 200)
        let noteColumn    = col("Note",    id: .noteCol,    width: 180)

        typeColumn.headerToolTip = ExclusionRule.RuleType.allCases
            .map { "\($0.displayName): \($0.typeHint)" }
            .joined(separator: "\n\n")

        tableView.addTableColumn(enabledColumn)
        tableView.addTableColumn(typeColumn)
        tableView.addTableColumn(patternColumn)
        tableView.addTableColumn(noteColumn)

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.allowsMultipleSelection     = true
        tableView.rowSizeStyle                = .default
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.columnAutoresizingStyle     = .lastColumnOnlyAutoresizingStyle
        tableView.doubleAction                = #selector(doubleClickedRow)
        tableView.target                      = self
        tableView.registerForDraggedTypes([.string])
        tableView.menu = makeBulkContextMenu()

        scrollView.documentView          = tableView
        scrollView.hasVerticalScroller   = true
        scrollView.autohidesScrollers    = true
        scrollView.borderType            = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func setupTestBar() {
        let label = NSTextField(labelWithString: "Test path:")
        label.font = .systemFont(ofSize: 11)
        label.setContentHuggingPriority(.defaultHigh, for: .horizontal)

        testPathField.placeholderString = "e.g. docs/report.tmp  or  node_modules/lodash/index.js"
        testPathField.font              = .monospacedSystemFont(ofSize: 11, weight: .regular)
        testPathField.delegate          = self
        testPathField.setContentHuggingPriority(.defaultLow, for: .horizontal)

        testMatchLabel.font              = .systemFont(ofSize: 11)
        testMatchLabel.textColor         = .secondaryLabelColor
        testMatchLabel.stringValue       = ""
        testMatchLabel.lineBreakMode     = .byTruncatingTail
        testMatchLabel.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        testMatchLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 280).isActive = true

        let row = NSStackView(views: [label, testPathField, testMatchLabel])
        row.orientation = .horizontal
        row.spacing     = 6
        row.translatesAutoresizingMaskIntoConstraints = false

        testPathContainer.translatesAutoresizingMaskIntoConstraints = false
        testPathContainer.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo:  testPathContainer.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: testPathContainer.trailingAnchor),
            row.topAnchor.constraint(equalTo:      testPathContainer.topAnchor),
            row.bottomAnchor.constraint(equalTo:   testPathContainer.bottomAnchor)
        ])
        view.addSubview(testPathContainer)
    }

    private func setupButtons() {
        for btn in [addButton, removeButton, duplicateButton, presetsButton, exportButton, importButton] {
            btn.bezelStyle = .rounded
        }
        addButton.target       = self; addButton.action       = #selector(addRule)
        removeButton.target    = self; removeButton.action    = #selector(removeRule)
        duplicateButton.target = self; duplicateButton.action = #selector(duplicateRule)
        presetsButton.target   = self; presetsButton.action   = #selector(showPresetsMenu(_:))
        presetsButton.toolTip  = "Insert a commonly-used exclusion pattern"
        exportButton.target    = self; exportButton.action    = #selector(exportRules)
        exportButton.toolTip   = "Save all rules to a JSON file"
        importButton.target    = self; importButton.action    = #selector(importRules)
        importButton.toolTip   = "Load rules from a previously exported JSON file (appended after existing rules)"

        let sep1 = NSBox(); sep1.boxType = .separator
        sep1.widthAnchor.constraint(equalToConstant: 1).isActive = true
        let sep2 = NSBox(); sep2.boxType = .separator
        sep2.widthAnchor.constraint(equalToConstant: 1).isActive = true

        let spacer = NSView()
        let stack  = NSStackView(views: [addButton, presetsButton, sep1,
                                         removeButton, duplicateButton, sep2,
                                         exportButton, importButton, spacer])
        stack.orientation = .horizontal
        stack.spacing     = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: testPathContainer.bottomAnchor, constant: 6),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Presets menu

    @objc private func showPresetsMenu(_ sender: NSButton) {
        let menu = NSMenu(title: "Presets")

        for (groupTitle, presets) in ExclusionRulesViewController.presetGroups {
            let header = NSMenuItem(title: groupTitle, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            for preset in presets {
                let item = NSMenuItem(
                    title: "  " + preset.label,
                    action: #selector(insertPreset(_:)),
                    keyEquivalent: ""
                )
                item.target          = self
                item.representedObject = preset
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        // Remove trailing separator
        if menu.items.last?.isSeparatorItem == true { menu.items.removeLast() }

        let btnBounds = sender.bounds
        menu.popUp(positioning: nil,
                   at: NSPoint(x: 0, y: btnBounds.maxY + 2),
                   in: sender)
    }

    @objc private func insertPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? Preset else { return }

        let pairId: Int64? = {
            if case .pair(let id) = mode { return id }
            return nil
        }()

        var rule = ExclusionRule(
            pairId:    pairId,
            ruleType:  preset.ruleType,
            pattern:   preset.pattern,
            isEnabled: true,
            note:      preset.note,
            sortOrder: rules.count
        )
        do {
            try DatabaseManager.shared.write { db in try rule.insert(db) }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 6),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: testPathContainer.topAnchor, constant: -6),

            testPathContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            testPathContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            testPathContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -36),
            testPathContainer.heightAnchor.constraint(equalToConstant: 22)
        ])
    }

    // MARK: - Actions

    @objc private func addRule() {
        presentEditSheet(existing: nil)
    }

    @objc private func removeRule() {
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }

        let alert = NSAlert()
        alert.messageText     = selected.count == 1
            ? "Remove this exclusion rule?"
            : "Remove \(selected.count) exclusion rules?"
        alert.informativeText = "This cannot be undone."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let toDelete = selected.map { rules[$0] }
        do {
            try DatabaseManager.shared.write { db in
                for rule in toDelete { _ = try rule.delete(db) }
            }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func duplicateRule() {
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }
        var nextOrder = rules.count
        do {
            try DatabaseManager.shared.write { db in
                for idx in selected.sorted() {
                    var copy = rules[idx]
                    copy.id        = nil
                    copy.sortOrder = nextOrder
                    nextOrder += 1
                    try copy.insert(db)
                }
            }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Bulk toggle actions

    @objc private func enableAllRules()         { setAllEnabled(true) }
    @objc private func disableAllRules()        { setAllEnabled(false) }
    @objc private func enableSelectedRules()    { setSelectedEnabled(true) }
    @objc private func disableSelectedRules()   { setSelectedEnabled(false) }

    @objc private func toggleAllRules() {
        guard !rules.isEmpty else { return }
        do {
            try DatabaseManager.shared.write { db in
                for var rule in rules {
                    rule.isEnabled = !rule.isEnabled
                    try rule.update(db)
                }
            }
        } catch {
            NSAlert.simple(message: "Failed to update rules: \(error.localizedDescription)")
        }
        loadRules()
    }

    private func setAllEnabled(_ enabled: Bool) {
        let changed = rules.filter { $0.isEnabled != enabled }
        guard !changed.isEmpty else { return }
        do {
            try DatabaseManager.shared.write { db in
                for var rule in changed {
                    rule.isEnabled = enabled
                    try rule.update(db)
                }
            }
        } catch {
            NSAlert.simple(message: "Failed to update rules: \(error.localizedDescription)")
        }
        loadRules()
    }

    private func setSelectedEnabled(_ enabled: Bool) {
        let indexes = tableView.selectedRowIndexes
        guard !indexes.isEmpty else { return }
        let changed = indexes.map { rules[$0] }.filter { $0.isEnabled != enabled }
        guard !changed.isEmpty else { return }
        do {
            try DatabaseManager.shared.write { db in
                for var rule in changed {
                    rule.isEnabled = enabled
                    try rule.update(db)
                }
            }
        } catch {
            NSAlert.simple(message: "Failed to update rules: \(error.localizedDescription)")
        }
        loadRules()
    }

    @objc private func doubleClickedRow() {
        let row = tableView.clickedRow
        guard row >= 0, row < rules.count else { return }
        presentEditSheet(existing: rules[row])
    }

    // MARK: - Add / Edit sheet

    /// Presents a sheet to add a new rule or edit an existing one (double-click).
    private func presentEditSheet(existing: ExclusionRule?) {
        let isNew = (existing == nil)

        let alert = NSAlert()
        alert.messageText     = isNew ? "Add Exclusion Rule" : "Edit Exclusion Rule"
        alert.informativeText = "Choose a type and enter the pattern to exclude.\nOptionally add a short note for your own reference."
        alert.addButton(withTitle: isNew ? "Add" : "Save")
        alert.addButton(withTitle: "Cancel")

        // ── Type popup ───────────────────────────────────────────────────────
        let typePopup = NSPopUpButton()
        for type in ExclusionRule.RuleType.allCases {
            typePopup.addItem(withTitle: type.displayName)
            typePopup.lastItem?.toolTip = type.typeHint
        }
        if let existing { typePopup.selectItem(withTitle: existing.ruleType.displayName) }

        // ── Type hint label (live, updates with popup selection) ─────────────
        let typeHintLabel = NSTextField(labelWithString: "")
        typeHintLabel.font           = .systemFont(ofSize: 11)
        typeHintLabel.textColor      = .secondaryLabelColor
        typeHintLabel.maximumNumberOfLines = 2
        typeHintLabel.lineBreakMode  = .byWordWrapping

        let bridge = PopUpBridge { idx in
            typeHintLabel.stringValue = ExclusionRule.RuleType.allCases[idx].typeHint
        }
        // Prime hint for initial selection
        typeHintLabel.stringValue = ExclusionRule.RuleType.allCases[typePopup.indexOfSelectedItem].typeHint
        typePopup.target = bridge
        typePopup.action = #selector(PopUpBridge.selectionChanged(_:))

        // ── Pattern field ────────────────────────────────────────────────────
        let patternField = NSTextField()
        patternField.placeholderString = "e.g.  *.tmp   |   node_modules/   |   .DS_Store"
        patternField.stringValue       = existing?.pattern ?? ""

        // ── Note field ───────────────────────────────────────────────────────
        let noteField = NSTextField()
        noteField.placeholderString = "Optional description (e.g. \"macOS metadata files\")"
        noteField.stringValue = existing?.note ?? ""

        // ── Layout ───────────────────────────────────────────────────────────
        let fieldWidth: CGFloat = 310

        func label(_ s: String) -> NSTextField {
            let lbl = NSTextField(labelWithString: s)
            lbl.font = .systemFont(ofSize: 12)
            lbl.alignment = .right
            lbl.widthAnchor.constraint(equalToConstant: 58).isActive = true
            return lbl
        }
        func row(_ lbl: NSView, _ ctrl: NSView) -> NSView {
            ctrl.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
            let s = NSStackView(views: [lbl, ctrl])
            s.orientation = .horizontal; s.spacing = 6; s.alignment = .centerY
            return s
        }

        typePopup.widthAnchor.constraint(equalToConstant: fieldWidth).isActive = true
        typeHintLabel.widthAnchor.constraint(equalToConstant: fieldWidth + 58 + 6).isActive = true

        let stack = NSStackView(views: [
            row(label("Type:"),    typePopup),
            typeHintLabel,
            row(label("Pattern:"), patternField),
            row(label("Note:"),    noteField)
        ])
        stack.orientation = .vertical
        stack.spacing = 8
        stack.frame = NSRect(x: 0, y: 0, width: 384, height: 120)
        alert.accessoryView = stack

        _ = bridge  // keep bridge alive for the duration of runModal()
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selectedType = ExclusionRule.RuleType.allCases[typePopup.indexOfSelectedItem]
        let pattern      = patternField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }
        let noteTrimmed  = noteField.stringValue.trimmingCharacters(in: .whitespaces)

        do {
            if var rule = existing {
                rule.ruleType = selectedType
                rule.pattern  = pattern
                rule.note     = noteTrimmed
                try DatabaseManager.shared.write { db in try rule.save(db) }
            } else {
                let pairId: Int64? = {
                    if case .pair(let id) = mode { return id }
                    return nil
                }()
                var rule = ExclusionRule(
                    pairId:    pairId,
                    ruleType:  selectedType,
                    pattern:   pattern,
                    isEnabled: true,
                    note:      noteTrimmed,
                    sortOrder: rules.count
                )
                try DatabaseManager.shared.write { db in try rule.insert(db) }
            }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Bulk context menu

    private func makeBulkContextMenu() -> NSMenu {
        let menu = NSMenu()
        func item(_ title: String, action: Selector) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.target = self
            return i
        }
        menu.addItem(item("Enable All",  action: #selector(enableAllRules)))
        menu.addItem(item("Disable All", action: #selector(disableAllRules)))
        menu.addItem(item("Toggle All",  action: #selector(toggleAllRules)))
        menu.addItem(.separator())
        menu.addItem(item("Enable Selected",  action: #selector(enableSelectedRules)))
        menu.addItem(item("Disable Selected", action: #selector(disableSelectedRules)))
        return menu
    }

    // MARK: - Import / Export

    /// Portable representation — omits DB-specific fields (id, pairId, sortOrder).
    private struct RuleExport: Codable {
        let ruleType:  String
        let pattern:   String
        let isEnabled: Bool
        let note:      String
    }

    @objc private func exportRules() {
        guard !rules.isEmpty else {
            NSAlert.simple(message: "No rules to export.")
            return
        }
        let payload = rules.map { r in
            RuleExport(ruleType: r.ruleType.rawValue, pattern: r.pattern,
                       isEnabled: r.isEnabled, note: r.note)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(payload) else { return }

        let panel = NSSavePanel()
        panel.title              = "Export Exclusion Rules"
        panel.nameFieldStringValue = "exclusion_rules.json"
        panel.allowedContentTypes  = [.json]
        panel.canCreateDirectories = true

        let parent = view.window
        let run: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                try data.write(to: url)
            } catch {
                NSApp.presentError(error)
            }
        }

        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: run)
        } else {
            run(panel.runModal())
        }
    }

    @objc private func importRules() {
        let panel = NSOpenPanel()
        panel.title              = "Import Exclusion Rules"
        panel.allowedContentTypes  = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories    = false

        let parent = view.window
        let run: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            self.doImport(from: url)
        }

        if let parent {
            panel.beginSheetModal(for: parent, completionHandler: run)
        } else {
            run(panel.runModal())
        }
    }

    private func doImport(from url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            NSAlert.simple(message: "Could not read the selected file.")
            return
        }
        guard let exports = try? JSONDecoder().decode([RuleExport].self, from: data) else {
            NSAlert.simple(message: "The file does not contain valid exclusion rules JSON.")
            return
        }
        guard !exports.isEmpty else { return }

        let pairId: Int64? = {
            if case .pair(let id) = mode { return id }
            return nil
        }()

        var nextOrder = rules.count
        do {
            try DatabaseManager.shared.write { db in
                for export in exports {
                    guard let type = ExclusionRule.RuleType(rawValue: export.ruleType) else { continue }
                    var rule = ExclusionRule(
                        pairId:    pairId,
                        ruleType:  type,
                        pattern:   export.pattern,
                        isEnabled: export.isEnabled,
                        note:      export.note,
                        sortOrder: nextOrder
                    )
                    nextOrder += 1
                    try rule.insert(db)
                }
            }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }
}

// MARK: - NSTableViewDataSource

extension ExclusionRulesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }

    // MARK: Drag source
    func tableView(_ tableView: NSTableView,
                   pasteboardWriterForRow row: Int) -> NSPasteboardWriting? {
        let item = NSPasteboardItem()
        item.setString(String(row), forType: .string)
        return item
    }

    // MARK: Drag destination
    func tableView(_ tableView: NSTableView,
                   validateDrop info: NSDraggingInfo,
                   proposedRow row: Int,
                   proposedDropOperation op: NSTableView.DropOperation) -> NSDragOperation {
        // Only accept drops between rows (not onto a row)
        if op == .above { return .move }
        tableView.setDropRow(row, dropOperation: .above)
        return .move
    }

    func tableView(_ tableView: NSTableView,
                   acceptDrop info: NSDraggingInfo,
                   row destinationRow: Int,
                   dropOperation: NSTableView.DropOperation) -> Bool {

        // Collect dragged row indices from the pasteboard
        var dragged: [Int] = []
        info.draggingPasteboard.pasteboardItems?.forEach { item in
            if let s = item.string(forType: .string), let idx = Int(s) {
                dragged.append(idx)
            }
        }
        dragged.sort()
        guard !dragged.isEmpty else { return false }

        // Build reordered array
        var remaining = rules
        let moved = dragged.map { remaining[$0] }
        // Remove in reverse so indices stay valid
        for idx in dragged.reversed() { remaining.remove(at: idx) }

        // Adjust destination for removed rows above it
        let removedAbove = dragged.filter { $0 < destinationRow }.count
        let insertAt = max(0, min(destinationRow - removedAbove, remaining.count))
        remaining.insert(contentsOf: moved, at: insertAt)

        // Persist new sortOrder values
        do {
            try DatabaseManager.shared.write { db in
                for (idx, var rule) in remaining.enumerated() {
                    rule.sortOrder = idx
                    try rule.save(db)
                    remaining[idx] = rule
                }
            }
        } catch {
            NSApp.presentError(error)
            return false
        }

        rules = remaining
        tableView.reloadData()
        return true
    }
}

// MARK: - NSTableViewDelegate

extension ExclusionRulesViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        guard row < rules.count else { return nil }
        let rule = rules[row]

        switch tableColumn?.identifier {

        case .enabledCol:
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            check.state = rule.isEnabled ? .on : .off
            check.tag   = row
            return check

        case .typeCol:
            let popup = NSPopUpButton()
            for type in ExclusionRule.RuleType.allCases {
                popup.addItem(withTitle: type.displayName)
                popup.lastItem?.toolTip = type.typeHint
            }
            popup.selectItem(withTitle: rule.ruleType.displayName)
            popup.toolTip = rule.ruleType.typeHint
            popup.tag    = row
            popup.target = self
            popup.action = #selector(typeChanged(_:))
            return popup

        case .patternCol:
            return inlineTextField(text: rule.pattern, tag: row, action: #selector(patternEdited(_:)),
                                   placeholder: nil)

        case .noteCol:
            let f = inlineTextField(text: rule.note, tag: row, action: #selector(noteEdited(_:)),
                                    placeholder: "Add a description…")
            if rule.note.isEmpty { f.textColor = .tertiaryLabelColor }
            return f

        default:
            return nil
        }
    }

    private func inlineTextField(text: String, tag: Int, action: Selector,
                                  placeholder: String?) -> NSTextField {
        let field = NSTextField(string: text)
        field.isEditable       = true
        field.isBezeled        = false
        field.drawsBackground  = false
        field.tag              = tag
        field.target           = self
        field.action           = action
        field.placeholderString = placeholder ?? ""
        return field
    }

    @objc private func toggleRule(_ sender: NSButton) {
        guard sender.tag < rules.count else { return }
        var rule = rules[sender.tag]
        rule.isEnabled = (sender.state == .on)
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }

    @objc private func patternEdited(_ sender: NSTextField) {
        guard sender.tag < rules.count else { return }
        var rule = rules[sender.tag]
        rule.pattern = sender.stringValue
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }

    @objc private func noteEdited(_ sender: NSTextField) {
        guard sender.tag < rules.count else { return }
        var rule = rules[sender.tag]
        rule.note = sender.stringValue
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }

    @objc private func typeChanged(_ sender: NSPopUpButton) {
        guard sender.tag < rules.count else { return }
        var rule = rules[sender.tag]
        rule.ruleType = ExclusionRule.RuleType.allCases[sender.indexOfSelectedItem]
        sender.toolTip = rule.ruleType.typeHint
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }
}

// MARK: - NSTextFieldDelegate (live test-path feedback)

extension ExclusionRulesViewController: NSTextFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSTextField) === testPathField else { return }
        updateTestMatchLabel()
    }

    private func updateTestMatchLabel() {
        let path = testPathField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            testMatchLabel.stringValue = ""
            return
        }
        if let match = rules.first(where: { $0.matches(relativePath: path) }) {
            testMatchLabel.stringValue = "✓  \"\(match.pattern)\"  (\(match.ruleType.displayName))"
            testMatchLabel.textColor   = NSColor(calibratedRed: 0.10, green: 0.60, blue: 0.20, alpha: 1)
        } else {
            testMatchLabel.stringValue = "✗  No rule matches"
            testMatchLabel.textColor   = .secondaryLabelColor
        }
    }
}

// MARK: - NSAlert convenience
extension NSAlert {
    static func simple(message: String) {
        let a = NSAlert()
        a.messageText = message
        a.runModal()
    }
}
