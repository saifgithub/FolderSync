import AppKit

// MARK: - Column identifiers
private extension NSUserInterfaceItemIdentifier {
    static let nameColumn     = NSUserInterfaceItemIdentifier("name")
    static let statusColumn   = NSUserInterfaceItemIdentifier("status")
    static let sizeColumn     = NSUserInterfaceItemIdentifier("size")
    static let modDateColumn  = NSUserInterfaceItemIdentifier("modDate")
    static let treeCell       = NSUserInterfaceItemIdentifier("TreeCell")
}

/// Displays one side (Left or Right) of a sync pair in a colour-coded NSOutlineView.
final class TreeViewController: NSViewController {

    // MARK: - Configuration
    let side: SyncSide
    var rootNode: TreeNode? { didSet { outlineView.reloadData() } }
    /// Absolute path of the root folder this tree represents. Set by PairDetailViewController.
    var rootPath: String?

    // MARK: - Callbacks
    var onSyncFile:    ((FileDiff) -> Void)?
    var onCopyFile:    ((FileDiff, SyncSide) -> Void)?
    var onCopyFolder:  ((TreeNode, SyncSide) -> Void)?
    var onDeleteFile:  ((FileDiff, SyncSide) -> Void)?
    var onResolveClash:((FileDiff) -> Void)?
    var onAddExclusion:((FileDiff) -> Void)?
    /// Fired when the user expands a node — used to mirror onto the opposite tree.
    var onExpand:  ((TreeNode) -> Void)?
    /// Fired when the user collapses a node — used to mirror onto the opposite tree.
    var onCollapse:((TreeNode) -> Void)?
    /// Prevents re-entrancy when mirroring an expand/collapse from the other side.
    private var isMirroring = false
    /// Prevents re-entrancy when mirroring scroll from the other side.
    private var isSyncingScroll = false

    // MARK: - UI
    private let scrollView   = NSScrollView()
    private let outlineView  = NSOutlineView()
    private let headerLabel  = NSTextField(labelWithString: "")

    // MARK: - Init
    init(side: SyncSide) {
        self.side = side
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - View lifecycle
    override func loadView() {
        view = NSView()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupHeader()
        setupOutlineView()
        setupLayout()
    }

    // MARK: - Setup

    private func setupHeader() {
        headerLabel.font = .boldSystemFont(ofSize: 13)
        headerLabel.stringValue = side.displayName + " Folder"
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(headerLabel)
    }

    private func setupOutlineView() {
        let nameCol   = makeColumn(title: "Name",     id: .nameColumn,    minWidth: 180)
        let statusCol = makeColumn(title: "Status",   id: .statusColumn,  minWidth: 100)
        let sizeCol   = makeColumn(title: "Size",     id: .sizeColumn,    minWidth: 70)
        let dateCol   = makeColumn(title: "Modified", id: .modDateColumn, minWidth: 120)

        outlineView.addTableColumn(nameCol)
        outlineView.addTableColumn(statusCol)
        outlineView.addTableColumn(sizeCol)
        outlineView.addTableColumn(dateCol)

        outlineView.outlineTableColumn = nameCol
        outlineView.dataSource = self
        outlineView.delegate   = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.allowsMultipleSelection = false
        outlineView.rowSizeStyle = .default
        outlineView.usesAlternatingRowBackgroundColors = true
        outlineView.menu = buildContextMenu()

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
    }

    private func makeColumn(title: String, id: NSUserInterfaceItemIdentifier, minWidth: CGFloat) -> NSTableColumn {
        let col = NSTableColumn(identifier: id)
        col.title = title
        col.minWidth = minWidth
        col.resizingMask = .userResizingMask
        return col
    }

    private func setupLayout() {
        NSLayoutConstraint.activate([
            headerLabel.topAnchor.constraint(equalTo: view.topAnchor, constant: 8),
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            headerLabel.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -8),

            scrollView.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 4),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
    }

    // MARK: - Context menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Sync File",                        action: #selector(syncFile),             keyEquivalent: "")
        menu.addItem(withTitle: "Force Copy File Left → Right",    action: #selector(forceCopyLeft),        keyEquivalent: "")
        menu.addItem(withTitle: "Force Copy File Left ← Right",    action: #selector(forceCopyRight),       keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Force Copy Folder Left → Right",  action: #selector(forceCopyFolderLeft),  keyEquivalent: "")
        menu.addItem(withTitle: "Force Copy Folder Left ← Right",  action: #selector(forceCopyFolderRight), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Resolve Clash…",                   action: #selector(resolveClash),         keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Add to Exclusions",                action: #selector(addExclusion),         keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Reveal in Finder",                 action: #selector(revealInFinder),       keyEquivalent: "")
        for item in menu.items { item.target = self }
        return menu
    }

    // MARK: - Context menu actions

    private var clickedDiff: FileDiff? {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TreeNode else { return nil }
        return node.diff
    }

    private var clickedNode: TreeNode? {
        let row = outlineView.clickedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? TreeNode
    }

    @objc private func syncFile() {
        guard let diff = clickedDiff else { return }
        onSyncFile?(diff)
    }

    @objc private func forceCopyLeft() {
        guard let diff = clickedDiff else { return }
        onCopyFile?(diff, .left)
    }

    @objc private func forceCopyRight() {
        guard let diff = clickedDiff else { return }
        onCopyFile?(diff, .right)
    }

    @objc private func forceCopyFolderLeft() {
        guard let node = clickedNode, node.isDirectory else { return }
        onCopyFolder?(node, .left)
    }

    @objc private func forceCopyFolderRight() {
        guard let node = clickedNode, node.isDirectory else { return }
        onCopyFolder?(node, .right)
    }

    @objc private func resolveClash() {
        guard let diff = clickedDiff else { return }
        onResolveClash?(diff)
    }

    @objc private func addExclusion() {
        guard let diff = clickedDiff else { return }
        onAddExclusion?(diff)
    }

    @objc private func revealInFinder() {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? TreeNode else { return }

        // Build the full URL from the root path + the node's relative path.
        // This works for both file leaves and directory nodes, and for absent-on-this-side files.
        let url: URL?
        if let root = rootPath, !root.isEmpty {
            let full = URL(fileURLWithPath: root)
                .appendingPathComponent(node.relativePath)
            // Prefer revealing the item itself; fall back to its parent if it doesn't exist on disk.
            if FileManager.default.fileExists(atPath: full.path) {
                url = full
            } else {
                // File absent on this side — reveal the nearest existing parent directory
                var parent = full.deletingLastPathComponent()
                while !parent.path.isEmpty && !FileManager.default.fileExists(atPath: parent.path) {
                    let up = parent.deletingLastPathComponent()
                    if up == parent { break }
                    parent = up
                }
                url = parent
            }
        } else {
            // Fallback: use absoluteURL from the file model if root path isn't set yet
            let diff = node.diff
            let file = side == .left ? diff?.leftFile : diff?.rightFile
            url = file?.absoluteURL
        }

        if let url {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    // MARK: - Public helpers

    func updateHeader(path: String) {
        headerLabel.stringValue = side.displayName + " — " + (path as NSString).abbreviatingWithTildeInPath
    }

    func expandAll()  { outlineView.expandItem(nil,  expandChildren: true) }
    func collapseAll() { outlineView.collapseItem(nil, collapseChildren: true) }

    // MARK: - Sync helpers (called by the opposite tree)

    /// Expands `node` without firing `onExpand` (prevents infinite ping-pong).
    func mirrorExpand(_ node: TreeNode) {
        isMirroring = true
        outlineView.expandItem(node)
        isMirroring = false
    }

    /// Collapses `node` without firing `onCollapse`.
    func mirrorCollapse(_ node: TreeNode) {
        isMirroring = true
        outlineView.collapseItem(node)
        isMirroring = false
    }

    /// Scrolls to the given Y offset without firing the scroll notification callback.
    func mirrorScrollOffset(_ y: CGFloat) {
        guard !isSyncingScroll else { return }
        isSyncingScroll = true
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isSyncingScroll = false
    }

    /// The clip view whose `boundsDidChangeNotification` can be observed for scroll sync.
    var clipView: NSClipView { scrollView.contentView }

    /// Returns the current vertical scroll offset.
    var scrollOffsetY: CGFloat { scrollView.contentView.bounds.origin.y }
}

// MARK: - NSMenuItemValidation

extension TreeViewController: NSMenuItemValidation {
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        let action = menuItem.action
        if action == #selector(forceCopyFolderLeft) || action == #selector(forceCopyFolderRight) {
            // Only enable for directory nodes (not file leaves or root when it has no children)
            return clickedNode?.isDirectory == true
        }
        if action == #selector(forceCopyLeft) || action == #selector(forceCopyRight) ||
           action == #selector(syncFile) || action == #selector(resolveClash) ||
           action == #selector(addExclusion) {
            return clickedDiff != nil
        }
        return true
    }
}

// MARK: - NSOutlineViewDataSource

extension TreeViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return rootNode?.children.count ?? 0 }
        return (item as? TreeNode)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return rootNode!.children[index] }
        return (item as! TreeNode).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? TreeNode)?.isDirectory ?? false
    }
}

// MARK: - NSOutlineViewDelegate

extension TreeViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? TreeNode else { return nil }
        let colId = tableColumn?.identifier

        // A node is "absent" on this side when it has no files on this side.
        // Works uniformly for both leaves and directory nodes (via pre-computed DiffSummary counts).
        let absent = node.isAbsent(on: side)

        switch colId {
        case .nameColumn:
            let id = NSUserInterfaceItemIdentifier("NameCell")
            let cell: NameCell
            if let reused = outlineView.makeView(withIdentifier: id, owner: self) as? NameCell {
                cell = reused
            } else {
                cell = NameCell()
                cell.identifier = id
                cell.wantsLayer = true   // set once at creation, never during layout
            }
            cell.configure(node: node, absent: absent, side: side)
            applyClashTint(to: cell, node: node)
            return cell

        default:
            let rawId = colId?.rawValue ?? "plain"
            let id = NSUserInterfaceItemIdentifier("TextCell_\(rawId)")
            let cell: NSTextField
            if let reused = outlineView.makeView(withIdentifier: id, owner: self) as? NSTextField {
                cell = reused
            } else {
                let f = NSTextField(labelWithString: "")
                f.identifier = id
                f.wantsLayer = true   // set once at creation, never during layout
                cell = f
            }
            switch colId {
            case .statusColumn:
                // Always show the status label so both sides communicate what the diff is
                cell.stringValue = node.diff?.status.displayLabel ?? node.summary.tooltipString
                cell.textColor   = absent ? .tertiaryLabelColor : node.statusColor(for: side)
                cell.font        = .systemFont(ofSize: 11)
            case .sizeColumn:
                let file = side == .left ? node.diff?.leftFile : node.diff?.rightFile
                cell.stringValue = absent ? "\u{2014}" : (file.map { $0.sizeBytes.formattedSize } ?? "")
                cell.textColor   = absent ? .tertiaryLabelColor : .labelColor
            case .modDateColumn:
                let file = side == .left ? node.diff?.leftFile : node.diff?.rightFile
                cell.stringValue = absent ? "\u{2014}" : (file.flatMap { $0.modifiedAt }.map {
                    $0.formatted(date: .abbreviated, time: .shortened)
                } ?? "")
                cell.textColor   = absent ? .tertiaryLabelColor : .labelColor
            default:
                cell.stringValue = ""
            }
            applyClashTint(to: cell, node: node)
            return cell
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isMirroring, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        onExpand?(node)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isMirroring, let node = notification.userInfo?["NSObject"] as? TreeNode else { return }
        onCollapse?(node)
    }

    func outlineView(_ outlineView: NSOutlineView, toolTipFor cell: NSCell, rect: NSRectPointer, tableColumn: NSTableColumn?, item: Any, mouseLocation: NSPoint) -> String {
        (item as? TreeNode)?.tooltipString ?? ""
    }

    /// Applies a subtle red CALayer background to clash rows.
    /// Uses CALayer (not Auto Layout constraints) to avoid triggering relayout passes.
    private func applyClashTint(to view: NSView, node: TreeNode) {
        // wantsLayer is set once during cell creation — never here (would trigger layout loop)
        view.layer?.backgroundColor = node.status == .clash
            ? NSColor.systemRed.withAlphaComponent(0.06).cgColor
            : nil
    }

    // rowViewForItem: intentionally omitted — setting NSTableRowView.backgroundColor
    // during layout triggers setNeedsLayout on the row view, causing an infinite
    // layout loop. Clash tinting is applied via CALayer in viewFor(tableColumn:item:).
}

// MARK: - Reusable name cell (icon + label, no per-row alloc)

/// A lightweight reusable cell for the Name column.
/// Constraints are built once at init; `configure(node:)` just mutates values.
final class NameCell: NSView {
    private let iconView = NSImageView()
    private let label    = NSTextField(labelWithString: "")

    private static let folderIcon = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
    private static let fileIcon   = NSImage(systemSymbolName: "doc",    accessibilityDescription: nil)
    private static let italicFont = NSFont(
        descriptor: NSFont.systemFont(ofSize: NSFont.systemFontSize)
            .fontDescriptor.withSymbolicTraits(.italic),
        size: 0
    ) ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
    private static let normalFont = NSFont.systemFont(ofSize: NSFont.systemFontSize)

    override init(frame: NSRect) {
        super.init(frame: frame)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints    = false
        iconView.imageScaling = .scaleProportionallyDown
        addSubview(iconView)
        addSubview(label)
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),
            label.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 4),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func configure(node: TreeNode, absent: Bool, side: SyncSide) {
        iconView.image    = node.isDirectory ? NameCell.folderIcon : NameCell.fileIcon
        label.stringValue = node.displayName
        if absent {
            // File doesn't exist on this side — dim it to signal absence
            label.textColor     = .tertiaryLabelColor
            label.font          = NameCell.normalFont
            iconView.alphaValue = 0.25
        } else {
            label.textColor     = node.statusColor(for: side)
            label.font          = node.isExcluded ? NameCell.italicFont : NameCell.normalFont
            iconView.alphaValue = 1.0
        }
    }
}
