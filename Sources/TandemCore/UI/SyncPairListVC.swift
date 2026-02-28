import AppKit
import GRDB

// MARK: - Row identifier
private extension NSUserInterfaceItemIdentifier {
    static let pairCell = NSUserInterfaceItemIdentifier("PairCell")
}

/// Left sidebar — lists all configured sync pairs, with add/remove buttons.
final class SyncPairListVC: NSViewController {

    // MARK: - Callbacks
    var onPairSelected: ((SyncPair) -> Void)?
    var onAddPair:       (() -> Void)?

    // MARK: - State
    private var pairs: [SyncPair] = []

    // MARK: - UI
    private let scrollView   = NSScrollView()
    private let tableView    = NSTableView()
    private let segmented    = NSSegmentedControl()
    private let titleLabel   = NSTextField(labelWithString: "Sync Pairs")
    private var dbObserver: AnyObject?

    // MARK: - View lifecycle
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupTableView()
        setupButtons()
        setupLayout()
        loadPairs()
        observePairs()
    }

    // MARK: - Public

    func reload() {
        loadPairs()
    }

    func pair(withId id: Int64) -> SyncPair? {
        pairs.first { $0.id == id }
    }

    // MARK: - Data

    private func loadPairs() {
        do {
            pairs = try DatabaseManager.shared.read { db in try SyncPair.order(SyncPair.Columns.name).fetchAll(db) }
            tableView.reloadData()
        } catch {
            NSApp.presentError(error)
        }
    }

    private func observePairs() {
        dbObserver = try? DatabaseManager.shared.observe(
            SyncPair.order(SyncPair.Columns.name)
        ) { [weak self] updated in
            self?.pairs = updated
            self?.tableView.reloadData()
        }
    }

    // MARK: - Setup

    private func setupTableView() {
        let col = NSTableColumn(identifier: .pairCell)
        col.title = "Sync Pairs"
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        tableView.headerView = NSTableHeaderView()
        tableView.dataSource = self
        tableView.delegate   = self
        tableView.allowsEmptySelection = true
        tableView.allowsMultipleSelection = false
        tableView.rowSizeStyle = .default
        tableView.focusRingType = .none

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers  = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func setupButtons() {
        // Segmented +/- control — always visible, standard macOS list style
        segmented.segmentCount = 2
        segmented.setImage(NSImage(systemSymbolName: "plus",  accessibilityDescription: "Add")!,    forSegment: 0)
        segmented.setImage(NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!, forSegment: 1)
        segmented.setWidth(28, forSegment: 0)
        segmented.setWidth(28, forSegment: 1)
        segmented.segmentStyle = .smallSquare
        segmented.trackingMode = .momentary
        segmented.target = self
        segmented.action = #selector(segmentClicked(_:))
        segmented.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmented)
    }

    private func setupHeader() {
        titleLabel.font = .boldSystemFont(ofSize: 11)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(titleLabel)
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),
            titleLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            titleLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: segmented.topAnchor),

            segmented.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            segmented.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            segmented.heightAnchor.constraint(equalToConstant: 24),
        ])
    }

    // MARK: - Actions

    @objc private func segmentClicked(_ sender: NSSegmentedControl) {
        if sender.selectedSegment == 0 { addPair() }
        else { removePair() }
    }

    @objc private func addPair() {
        onAddPair?()
    }

    @objc private func removePair() {
        let row = tableView.selectedRow
        guard row >= 0 && row < pairs.count else { return }
        let pair = pairs[row]

        let alert = NSAlert()
        alert.messageText = "Remove '\(pair.name)'?"
        alert.informativeText = "This will remove the pair and all its sync history from the database. The actual files will not be touched."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            try DatabaseManager.shared.write { db in _ = try pair.delete(db) }
            if let id = pair.id { WatcherCoordinator.shared.deactivate(pairId: id) }
        } catch {
            NSApp.presentError(error)
        }
    }
}

// MARK: - NSTableViewDataSource

extension SyncPairListVC: NSTableViewDataSource {
    func numberOfRows(in tableView: NSTableView) -> Int { pairs.count }
}

// MARK: - NSTableViewDelegate

extension SyncPairListVC: NSTableViewDelegate {

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let pair = pairs[row]
        let cell = NSTableCellView()

        // Name
        let nameField = NSTextField(labelWithString: pair.name)
        nameField.font = .systemFont(ofSize: 13, weight: .medium)
        nameField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(nameField)
        cell.textField = nameField

        // Folder subtitle
        let left  = (pair.leftPath  as NSString).lastPathComponent
        let right = (pair.rightPath as NSString).lastPathComponent
        let subtitleField = NSTextField(labelWithString: "⇄ \(left) / \(right)")
        subtitleField.font = .systemFont(ofSize: 10)
        subtitleField.textColor = .secondaryLabelColor
        subtitleField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(subtitleField)

        // Status line: sync mode + last-synced
        let statusField = NSTextField(labelWithString: statusText(for: pair))
        statusField.font = .systemFont(ofSize: 10)
        statusField.textColor = .tertiaryLabelColor
        statusField.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(statusField)

        if let tf = cell.textField {
            NSLayoutConstraint.activate([
                tf.topAnchor.constraint(equalTo: cell.topAnchor, constant: 6),
                tf.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                tf.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),

                subtitleField.topAnchor.constraint(equalTo: tf.bottomAnchor, constant: 1),
                subtitleField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                subtitleField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),

                statusField.topAnchor.constraint(equalTo: subtitleField.bottomAnchor, constant: 1),
                statusField.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
                statusField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
                statusField.bottomAnchor.constraint(lessThanOrEqualTo: cell.bottomAnchor, constant: -4)
            ])
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 58 }

    // MARK: - Status text helper

    private func statusText(for pair: SyncPair) -> String {
        var parts: [String] = []

        // Sync mode icon
        switch pair.syncMode {
        case .manual:    parts.append("⛹ Manual")
        case .realtime:  parts.append("⚡ Realtime")
        case .scheduled: parts.append("⏰ Scheduled")
        case .all:       parts.append("⚡+⏰ All")
        }

        // Last synced
        if let date = pair.lastSyncedAt {
            let rel = Self.relativeTimeString(from: date)
            parts.append("Synced \(rel)")
        } else {
            parts.append("Never synced")
        }

        return parts.joined(separator: " · ")
    }

    private static let relFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeTimeString(from date: Date) -> String {
        relFormatter.localizedString(for: date, relativeTo: Date())
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0 && row < pairs.count else { return }
        onPairSelected?(pairs[row])
    }
}
