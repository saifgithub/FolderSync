import AppKit

// MARK: - TreeNode

/// Represents one node in the side-by-side file tree outline view.
/// Can be a directory (with children) or a file (leaf).
final class TreeNode {

    // MARK: - Identity
    let relativePath: String

    /// Filename / last path component for display.
    var displayName: String {
        (relativePath as NSString).lastPathComponent
    }

    // MARK: - Content
    let diff: FileDiff?               // nil for the synthetic root node
    var children: [TreeNode] = []
    weak var parent: TreeNode?

    var isDirectory: Bool { !children.isEmpty }
    var isLeaf: Bool { children.isEmpty }

    // MARK: - Aggregate diff summary and cached status for directory nodes
    private(set) var summary: DiffSummary = DiffSummary()
    /// Cached status — computed once in recalculateSummary(), never re-traversed at render time.
    private(set) var cachedStatus: DiffStatus?

    // MARK: - Init

    /// Leaf node (file).
    init(diff: FileDiff) {
        self.relativePath = diff.relativePath
        self.diff = diff
        // summary is set by TreeBuilder.build via recalculateSummary() — no DiffEngine needed here
    }

    /// Directory / root node.
    init(relativePath: String) {
        self.relativePath = relativePath
        self.diff = nil
    }

    // MARK: - Status for this node

    /// The display status of this node. Returns the value cached by recalculateSummary().
    /// Never traverses children at render time — O(1).
    var status: DiffStatus? { cachedStatus }

    // MARK: - Layout colour for this node

    var statusColor: NSColor {
        guard let status else { return .secondaryLabelColor }
        return status.displayColor
    }

    /// Side-aware colour: `.updated` shows blue on the newer side, black on the older side.
    /// Directory nodes fall back to the side-agnostic colour (aggregate badge).
    func statusColor(for side: SyncSide) -> NSColor {
        guard let status else { return .secondaryLabelColor }
        // Only leaf rows carry a single concrete diff worth per-side colouring
        if !isDirectory, diff != nil {
            return status.displayColor(for: side)
        }
        return status.displayColor
    }

    /// True when this node has no files on the given side.
    /// For leaves: based on the diff's left/rightFile. For directories: based on the aggregated counts.
    func isAbsent(on side: SyncSide) -> Bool {
        side == .left ? summary.leftFileCount == 0 : summary.rightFileCount == 0
    }

    var isExcluded: Bool {
        if let diff { return diff.status == .excluded }
        return children.allSatisfy { $0.isExcluded }
    }

    // MARK: - Tooltip string

    var tooltipString: String {
        if let diff {
            return diff.status.displayLabel
                + (diff.leftFile != nil ? "\nLeft:  \(diff.leftFile!.sizeBytes.formattedSize), \(diff.leftFile!.modifiedAt.formatted())" : "\nLeft: —")
                + (diff.rightFile != nil ? "\nRight: \(diff.rightFile!.sizeBytes.formattedSize), \(diff.rightFile!.modifiedAt.formatted())" : "\nRight: —")
        }
        return summary.tooltipString
    }

    // MARK: - Recalculate summary from children (called by builder)

    func recalculateSummary() {
        if let diff {
            // Inline — avoids allocating a DiffEngine per leaf
            var s = DiffSummary()
            switch diff.status {
            case .same:     s.same     = 1
            case .new:      s.new      = 1
            case .updated:  s.updated  = 1
            case .deleted:  s.deleted  = 1
            case .clash:    s.clashes  = 1
            case .excluded: s.excluded = 1
            }
            s.leftFileCount  = diff.leftFile  != nil ? 1 : 0
            s.rightFileCount = diff.rightFile != nil ? 1 : 0
            summary = s
            cachedStatus = diff.status   // cache for O(1) render-time access
            return
        }
        var s = DiffSummary()
        for child in children {
            child.recalculateSummary()   // bottom-up: children are ready before us
            s.same           += child.summary.same
            s.new            += child.summary.new
            s.updated        += child.summary.updated
            s.deleted        += child.summary.deleted
            s.clashes        += child.summary.clashes
            s.excluded       += child.summary.excluded
            s.leftFileCount  += child.summary.leftFileCount
            s.rightFileCount += child.summary.rightFileCount
        }
        summary = s
        // Derive and cache worst-case status from pre-computed child statuses — O(children) not O(subtree)
        cachedStatus = worstStatus(in: children)
    }

    // MARK: - Helpers

    private func worstStatus(in nodes: [TreeNode]) -> DiffStatus? {
        // Priority: clash > deleted > updated > new > same > excluded
        if nodes.contains(where: { $0.status == .clash }) { return .clash }
        if nodes.contains(where: { if case .deleted = $0.status { return true }; return false }) { return .deleted(.left) }
        if nodes.contains(where: { if case .updated = $0.status { return true }; return false }) { return .updated(newer: .left) }
        if nodes.contains(where: { if case .new = $0.status { return true }; return false }) { return .new(.left) }
        if nodes.contains(where: { $0.status == .same }) { return .same }
        return .excluded
    }
}

// MARK: - DiffStatus display helpers

extension DiffStatus {
    /// Side-agnostic colour — used for directory badge rows and status-column labels.
    var displayColor: NSColor {
        switch self {
        case .same:               return .systemGreen
        case .new:                return .systemOrange
        case .updated:            return .systemBlue
        case .deleted:            return .systemYellow
        case .clash:              return .systemRed
        case .excluded:           return .systemGray
        }
    }

    /// Side-aware colour — used for file-row name cells.
    /// For `.updated`, the newer side is blue and the older side is the default label colour.
    func displayColor(for side: SyncSide) -> NSColor {
        switch self {
        case .same:                          return .systemGreen
        case .new:                           return .systemOrange
        case .updated(newer: let newerSide): return newerSide == side ? .systemBlue : .labelColor
        case .deleted:                       return .systemYellow
        case .clash:                         return .systemRed
        case .excluded:                      return .systemGray
        }
    }

    var displayLabel: String {
        switch self {
        case .same:               return "Same"
        case .new(let s):         return "New on \(s.displayName)"
        case .updated(let s):     return "\(s.displayName) is newer"
        case .deleted(let s):     return "Deleted from \(s.displayName)"
        case .clash:              return "⚠️ Clash — modified on both sides"
        case .excluded:           return "Excluded"
        }
    }

    var displayIcon: NSImage? {
        switch self {
        case .same:               return NSImage(systemSymbolName: "checkmark.circle",      accessibilityDescription: "Same")
        case .new:                return NSImage(systemSymbolName: "plus.circle",           accessibilityDescription: "New")
        case .updated:            return NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: "Updated")
        case .deleted:            return NSImage(systemSymbolName: "minus.circle",          accessibilityDescription: "Deleted")
        case .clash:              return NSImage(systemSymbolName: "exclamationmark.circle",accessibilityDescription: "Clash")
        case .excluded:           return NSImage(systemSymbolName: "nosign",                accessibilityDescription: "Excluded")
        }
    }
}

// MARK: - TreeBuilder

/// Converts a flat list of `FileDiff` into a hierarchical `TreeNode` structure.
enum TreeBuilder {

    static func build(from diffs: [FileDiff]) -> TreeNode {
        let root = TreeNode(relativePath: "")
        // O(1) node lookup by full path — avoids the O(n²) linear-scan in children arrays
        var nodeByPath: [String: TreeNode] = ["": root]

        for diff in diffs {
            let path = diff.relativePath
            var parentPath = ""

            // Build every intermediate directory node that doesn’t exist yet
            let slashCount = path.unicodeScalars.filter { $0 == "/" }.count
            if slashCount > 0 {
                var scanIdx = path.startIndex
                for _ in 0..<slashCount {
                    guard let slash = path[scanIdx...].firstIndex(of: "/") else { break }
                    let dirPath = String(path[path.startIndex..<slash])
                    if nodeByPath[dirPath] == nil {
                        let dir = TreeNode(relativePath: dirPath)
                        let parent = nodeByPath[parentPath]!
                        dir.parent = parent
                        parent.children.append(dir)
                        nodeByPath[dirPath] = dir
                    }
                    parentPath = dirPath
                    scanIdx = path.index(after: slash)
                }
            }

            // Leaf node
            let leaf = TreeNode(diff: diff)
            let parent = nodeByPath[parentPath]!
            leaf.parent = parent
            parent.children.append(leaf)
        }

        root.recalculateSummary()
        return root
    }
}

// MARK: - Int64 size formatter helper

extension Int64 {
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
