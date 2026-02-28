import GRDB
import Foundation

/// Tracks the last-known state of a file on one side of a sync pair.
/// One row per (pairId, relativePath, side). Updated after each successful sync.
struct TrackedFile: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {

    var id: Int64?
    var pairId: Int64           // FK → sync_pairs.id
    var relativePath: String    // path relative to the side's root, e.g. "docs/report.pdf"
    var side: SyncSide          // .left | .right
    var sizeBytes: Int64
    var modifiedAt: Date
    var checksum: String?       // SHA-256 hex string, nil if checksum disabled
    var syncedAt: Date          // when this snapshot was last written

    // MARK: - Table
    static let databaseTableName = "tracked_files"

    static let syncPairForeignKey = ForeignKey(["pairId"])

    enum Columns {
        static let id           = Column("id")
        static let pairId       = Column("pairId")
        static let relativePath = Column("relativePath")
        static let side         = Column("side")
        static let sizeBytes    = Column("sizeBytes")
        static let modifiedAt   = Column("modifiedAt")
        static let checksum     = Column("checksum")
        static let syncedAt     = Column("syncedAt")
    }

    // MARK: - MutablePersistableRecord
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Init
    init(
        id: Int64? = nil,
        pairId: Int64,
        relativePath: String,
        side: SyncSide,
        sizeBytes: Int64,
        modifiedAt: Date,
        checksum: String? = nil,
        syncedAt: Date = Date()
    ) {
        self.id = id
        self.pairId = pairId
        self.relativePath = relativePath
        self.side = side
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.checksum = checksum
        self.syncedAt = syncedAt
    }
}

// MARK: - SyncSide
enum SyncSide: String, Codable, CaseIterable {
    case left  = "left"
    case right = "right"

    var opposite: SyncSide { self == .left ? .right : .left }

    var displayName: String { self == .left ? "Left" : "Right" }

    /// Direction label where the arrow always points toward the destination.
    /// e.g.  left.arrowTo(.right) → "Left → Right"
    ///       right.arrowTo(.left) → "Left ← Right"
    func arrowTo(_ dest: SyncSide) -> String {
        self == .left ? "Left → Right" : "Left ← Right"
    }
}
