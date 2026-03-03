import GRDB
import Foundation

/// A single exclusion rule.
///
/// When `pairId` is non-nil the rule applies only to that sync pair.
/// When `pairId` is nil the rule is **global** and applies to every pair.
struct ExclusionRule: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {

    var id: Int64?
    var pairId: Int64?      // nil = global rule (applies to all pairs)
    var ruleType: RuleType
    var pattern: String     // the glob / path / filename string
    var isEnabled: Bool     // can be toggled without deleting
    var note: String = ""   // optional human-readable description
    var sortOrder: Int = 0  // user-defined display order

    // MARK: - Table
    static let databaseTableName = "exclusion_rules"
    static let syncPairForeignKey = ForeignKey(["pairId"])

    enum Columns {
        static let id        = Column("id")
        static let pairId    = Column("pairId")
        static let ruleType  = Column("ruleType")
        static let pattern   = Column("pattern")
        static let isEnabled = Column("isEnabled")
        static let note      = Column("note")
        static let sortOrder = Column("sortOrder")
    }

    // MARK: - MutablePersistableRecord
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Codable — custom decoder for forward/backward compatibility
    // `init(from:)` in the struct body suppresses the synthesised memberwise init,
    // so we provide an explicit one below for all programmatic call-sites.
    init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decodeIfPresent(Int64.self,   forKey: .id)
        pairId    = try c.decodeIfPresent(Int64.self,   forKey: .pairId)
        ruleType  = try c.decode(RuleType.self,         forKey: .ruleType)
        pattern   = try c.decode(String.self,           forKey: .pattern)
        isEnabled = try c.decode(Bool.self,             forKey: .isEnabled)
        note      = (try c.decodeIfPresent(String.self, forKey: .note))      ?? ""
        sortOrder = (try c.decodeIfPresent(Int.self,    forKey: .sortOrder)) ?? 0
    }

    /// Explicit memberwise-like init so call-sites are not broken when
    /// the synthesised init is suppressed by the Decodable init above.
    init(id:        Int64?     = nil,
         pairId:    Int64?     = nil,
         ruleType:  RuleType,
         pattern:   String,
         isEnabled: Bool       = true,
         note:      String     = "",
         sortOrder: Int        = 0) {
        self.id        = id
        self.pairId    = pairId
        self.ruleType  = ruleType
        self.pattern   = pattern
        self.isEnabled = isEnabled
        self.note      = note
        self.sortOrder = sortOrder
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

        /// Short description + example shown in the edit sheet and as a popup-item tooltip.
        var typeHint: String {
            switch self {
            case .filename:
                return "Exact filename match anywhere in the tree.\nExample: .DS_Store  •  Thumbs.db"
            case .glob:
                return "Shell glob matched against the filename only (* and ? wildcards).\nExample: *.tmp  •  ~$*  •  *.bak"
            case .folder:
                return "Skip an entire subtree starting at this folder path (trailing / optional).\nExample: node_modules/  •  build/  •  .git/"
            case .filepath:
                return "Exact relative path from the sync root.\nExample: config/secrets.json  •  dist/bundle.min.js"
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
