import AppKit
import GRDB

/// Modal sheet showing all backup records for one sync pair.
/// Double-clicking a row reveals the backup file in Finder.
final class BackupHistoryViewController: NSViewController {

    // MARK: - State
    private let pair: SyncPair
    private var records: [BackupRecord] = []

    // MARK: - UI
    private let scrollView  = NSScrollView()
    private let tableView   = NSTableView()
    private let closeButton = NSButton(title: "Close", target: nil, action: nil)
    private let clearButton = NSButton(title: "Clear All…", target: nil, action: nil)
    private let titleLabel  = NSTextField(labelWithString: "")
    private let emptyLabel  = NSTextField(labelWithString: "No backup records for this pair.")

    // MARK: - Columns
    private enum Col: String {
        case date     = "Date"
        case path     = "Original Path"
        case side     = "Side"
        case size     = "Size"
        case backup   = "Backup File"
    }

    // MARK: - Init
    init(pair: SyncPair) {
        self.pair = pair
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - Lifecycle
    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 780, height: 480))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupTitle()
        setupTableView()
        setupButtons()
        setupEmptyLabel()
        setupLayout()
        loadRecords()
    }

    // MARK: - Data

    private func loadRecords() {
        guard let pairId = pair.id else { return }
        do {
            records = try DatabaseManager.shared.read { db in
                try BackupRecord
                    .filter(BackupRecord.Columns.pairId == pairId)
                    .order(BackupRecord.Columns.backedUpAt.desc)
                    .fetchAll(db)
            }
        } catch {
            NSApp.presentError(error)
        }
        tableView.reloadData()
        emptyLabel.isHidden = !records.isEmpty
        tableView.isHidden  = records.isEmpty
    }

    // MARK: - Setup

    private func setupTitle() {
        titleLabel.stringValue = "Backup History — \(pair.name)"
        titleLabel.font = .boldSystemFont(ofSize: 13)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupTableView() {
        let cols: [(Col, CGFloat)] = [
            (.date,   150),
            (.path,   230),
            (.side,    60),
            (.size,    80),
            (.backup, 210)
        ]
        for (col, width) in cols {
            let tc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(col.rawValue))
            tc.title = col.rawValue
            tc.width = width
            tc.isEditable = false
            tableView.addTableColumn(tc)
        }

        tableView.dataSource       = self
        tableView.delegate         = self
        tableView.rowSizeStyle     = .default
        tableView.allowsMultipleSelection = false
        tableView.doubleAction     = #selector(rowDoubleClicked)
        tableView.target           = self
        tableView.focusRingType    = .none

        scrollView.documentView        = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType          = .bezelBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func setupButtons() {
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        closeButton.target = self
        closeButton.action = #selector(close)
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        clearButton.bezelStyle = .rounded
        clearButton.target = self
        clearButton.action = #selector(clearAll)
        clearButton.contentTintColor = .systemRed
        clearButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(closeButton)
        view.addSubview(clearButton)
    }

    private func setupEmptyLabel() {
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .tertiaryLabelColor
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(emptyLabel)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            scrollView.bottomAnchor.constraint(equalTo: closeButton.topAnchor, constant: -12),

            emptyLabel.centerXAnchor.constraint(equalTo: scrollView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: scrollView.centerYAnchor),

            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            closeButton.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -16),
            closeButton.widthAnchor.constraint(equalToConstant: 80),

            clearButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            clearButton.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
        ])
    }

    // MARK: - Actions

    @objc private func close() {
        presentingViewController?.dismiss(self)
    }

    @objc private func clearAll() {
        guard let pairId = pair.id else { return }
        let alert = NSAlert()
        alert.messageText = "Clear All Backup Records?"
        alert.informativeText = "This removes all backup history entries from the database for '\(pair.name)'. The backup files on disk will NOT be deleted."
        alert.addButton(withTitle: "Clear All")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try DatabaseManager.shared.write { db in
                _ = try BackupRecord
                    .filter(BackupRecord.Columns.pairId == pairId)
                    .deleteAll(db)
            }
            records.removeAll()
            tableView.reloadData()
            emptyLabel.isHidden = false
            tableView.isHidden  = true
        } catch {
            NSApp.presentError(error)
        }
    }

    @objc private func rowDoubleClicked() {
        let row = tableView.selectedRow
        guard row >= 0 && row < records.count else { return }
        let record = records[row]
        NSWorkspace.shared.activateFileViewerSelecting([record.backupFileURL])
    }

    // MARK: - Formatting helpers

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .medium
        return f
    }()

    private static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

// MARK: - NSTableViewDataSource

extension BackupHistoryViewController: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { records.count }
}

// MARK: - NSTableViewDelegate

extension BackupHistoryViewController: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let colId = tableColumn?.identifier.rawValue,
              let col = Col(rawValue: colId) else { return nil }

        let record = records[row]
        let text: String

        switch col {
        case .date:   text = Self.dateFormatter.string(from: record.backedUpAt)
        case .path:   text = record.originalRelativePath
        case .side:   text = record.originalSide.displayName
        case .size:   text = Self.formatBytes(record.sizeBytes)
        case .backup: text = record.backupFileName
        }

        let cell = NSTableCellView()
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 12)
        field.lineBreakMode = .byTruncatingMiddle
        field.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(field)
        cell.textField = field
        NSLayoutConstraint.activate([
            field.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
            field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 2),
            field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -2)
        ])
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 22 }
}
