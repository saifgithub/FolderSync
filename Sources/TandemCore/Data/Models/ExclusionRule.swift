import GRDB
import Foundation

/// A single exclusion rule scoped to one sync pair.
struct ExclusionRule: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {

    var id: Int64?
    var pairId: Int64
    var ruleType: RuleType
    var pattern: String     // the glob / path / filename string
    var isEnabled: Bool     // can be toggled without deleting

    // MARK: - Table
    static let databaseTableName = "exclusion_rules"
    static let syncPairForeignKey = ForeignKey(["pairId"])

    enum Columns {
        static let id        = Column("id")
        static let pairId    = Column("pairId")
        static let ruleType  = Column("ruleType")
        static let pattern   = Column("pattern")
        static let isEnabled = Column("isEnabled")
    }

    // MARK: - MutablePersistableRecord
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - RuleType
    enum RuleType: String, Codable, CaseIterable {
        /// Exact filename match anywhere in tree, e.g. ".DS_Store"
        case filename = "filename"
        /// Shell glob matched against filename only, e.g. "*.tmp", "~$*"
        case glob     = "glob"
        /// Relative subfolder path — entire subtree is skipped, e.g. "node_modules/"
        case folder   = "folder"
        /// Relative file path from root, e.g. "config/secrets.json"
        case filepath = "filepath"

        var displayName: String {
            switch self {
            case .filename: return "Filename"
            case .glob:     return "Glob Pattern"
            case .folder:   return "Folder (subtree)"
            case .filepath: return "File Path"
            }
        }
    }

    // MARK: - Matching

    /// Returns true if the given relative path should be excluded by this rule.
    func matches(relativePath: String) -> Bool {
        guard isEnabled else { return false }

        let filename = (relativePath as NSString).lastPathComponent

        switch ruleType {
        case .filename:
            return filename == pattern

        case .glob:
            return matchesGlob(pattern: pattern, string: filename)

        case .folder:
            // normalise trailing slash
            let normPattern = pattern.hasSuffix("/") ? pattern : pattern + "/"
            let normPath    = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            return normPath.hasPrefix(normPattern) || normPath == String(normPattern.dropLast())

        case .filepath:
            let normPattern = pattern.hasPrefix("/") ? String(pattern.dropFirst()) : pattern
            let normPath    = relativePath.hasPrefix("/") ? String(relativePath.dropFirst()) : relativePath
            return normPath == normPattern
        }
    }

    // MARK: - Private glob helper

    private func matchesGlob(pattern: String, string: String) -> Bool {
        // Use fnmatch for shell-style glob matching
        return fnmatch(pattern, string, 0) == 0
    }
}

// MARK: - Collection helper
extension Collection where Element == ExclusionRule {
    /// Returns true if any enabled rule matches the given relative path.
    func excludes(relativePath: String) -> Bool {
        self.contains { $0.matches(relativePath: relativePath) }
    }
}
