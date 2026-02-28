import AppKit

private extension NSUserInterfaceItemIdentifier {
    static let ruleCell    = NSUserInterfaceItemIdentifier("RuleCell")
    static let typeCol     = NSUserInterfaceItemIdentifier("TypeCol")
    static let patternCol  = NSUserInterfaceItemIdentifier("PatternCol")
    static let enabledCol  = NSUserInterfaceItemIdentifier("EnabledCol")
}

/// Managed exclusion rules for a sync pair.
/// Embedded as a tab inside `SettingsViewController`.
final class ExclusionRulesViewController: NSViewController {

    // MARK: - State
    private let pairId: Int64?
    private var rules: [ExclusionRule] = []

    // MARK: - UI
    private let tableView    = NSTableView()
    private let scrollView   = NSScrollView()
    private let addButton    = NSButton(title: "+ Add Rule", target: nil, action: nil)
    private let removeButton = NSButton(title: "Remove", target: nil, action: nil)

    // MARK: - Init
    init(pairId: Int64?) {
        self.pairId = pairId
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
        setupTableView()
        setupButtons()
        setupLayout()
        loadRules()
    }

    // MARK: - Data

    func loadRules() {
        guard let pairId else { rules = []; tableView.reloadData(); return }
        do {
            rules = try DatabaseManager.shared.read { db in
                try ExclusionRule.filter(sql: "pairId = \(pairId)").fetchAll(db)
            }
            tableView.reloadData()
        } catch {
            NSApp.presentError(error)
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        func col(_ title: String, id: NSUserInterfaceItemIdentifier, width: CGFloat) -> NSTableColumn {
            let c = NSTableColumn(identifier: id)
            c.title = title
            c.width = width
            return c
        }

        tableView.addTableColumn(col("Enabled", id: .enabledCol, width: 60))
        tableView.addTableColumn(col("Type",    id: .typeCol,    width: 110))
        tableView.addTableColumn(col("Pattern", id: .patternCol, width: 280))

        tableView.dataSource = self
        tableView.delegate   = self
        tableView.allowsMultipleSelection = true
        tableView.rowSizeStyle = .default
        tableView.usesAlternatingRowBackgroundColors = true

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func setupButtons() {
        addButton.bezelStyle   = .rounded
        removeButton.bezelStyle = .rounded
        addButton.target   = self;   addButton.action   = #selector(addRule)
        removeButton.target = self;  removeButton.action = #selector(removeRule)

        let stack = NSStackView(views: [addButton, removeButton, NSView()])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -44)
        ])
    }

    // MARK: - Actions

    @objc private func addRule() {
        guard let pairId else {
            NSAlert.simple(message: "Save the pair first before adding exclusion rules.")
            return
        }

        // Show a quick-entry panel
        let alert = NSAlert()
        alert.messageText = "Add Exclusion Rule"
        alert.informativeText = "Choose a rule type and enter the pattern."
        alert.addButton(withTitle: "Add")
        alert.addButton(withTitle: "Cancel")

        let typePopup = NSPopUpButton()
        ExclusionRule.RuleType.allCases.forEach { typePopup.addItem(withTitle: $0.displayName) }

        let patternField = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        patternField.placeholderString = "e.g. *.tmp  or  node_modules/  or  .DS_Store"

        let container = NSStackView(views: [typePopup, patternField])
        container.orientation = .vertical
        container.spacing = 6
        container.frame = NSRect(x: 0, y: 0, width: 300, height: 60)
        alert.accessoryView = container

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let selectedType = ExclusionRule.RuleType.allCases[typePopup.indexOfSelectedItem]
        let pattern = patternField.stringValue.trimmingCharacters(in: .whitespaces)
        guard !pattern.isEmpty else { return }

        var rule = ExclusionRule(pairId: pairId, ruleType: selectedType, pattern: pattern, isEnabled: true)
        do {
            try DatabaseManager.shared.write { db in try rule.insert(db) }
            loadRules()
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func removeRule() {
        let selected = tableView.selectedRowIndexes
        guard !selected.isEmpty else { return }
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
}

// MARK: - NSTableViewDataSource

extension ExclusionRulesViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { rules.count }
}

// MARK: - NSTableViewDelegate

extension ExclusionRulesViewController: NSTableViewDelegate {
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let rule = rules[row]

        switch tableColumn?.identifier {
        case .enabledCol:
            let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(toggleRule(_:)))
            check.state = rule.isEnabled ? .on : .off
            check.tag   = row
            return check

        case .typeCol:
            let popup = NSPopUpButton()
            ExclusionRule.RuleType.allCases.forEach { popup.addItem(withTitle: $0.displayName) }
            popup.selectItem(withTitle: rule.ruleType.displayName)
            popup.tag    = row
            popup.target = self
            popup.action = #selector(typeChanged(_:))
            return popup

        case .patternCol:
            let field = NSTextField(string: rule.pattern)
            field.isEditable = true
            field.isBezeled  = false
            field.drawsBackground = false
            field.tag = row
            field.target = self
            field.action = #selector(patternEdited(_:))
            return field

        default: return nil
        }
    }

    @objc private func toggleRule(_ sender: NSButton) {
        var rule = rules[sender.tag]
        rule.isEnabled = sender.state == .on
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }

    @objc private func patternEdited(_ sender: NSTextField) {
        var rule = rules[sender.tag]
        rule.pattern = sender.stringValue
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
    }

    @objc private func typeChanged(_ sender: NSPopUpButton) {
        var rule = rules[sender.tag]
        rule.ruleType = ExclusionRule.RuleType.allCases[sender.indexOfSelectedItem]
        try? DatabaseManager.shared.write { db in try rule.save(db) }
        rules[sender.tag] = rule
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
