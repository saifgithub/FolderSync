import GRDB
import Foundation

/// A configured pair of folders to keep in sync.
struct SyncPair: Codable, FetchableRecord, PersistableRecord, Identifiable {

    // MARK: - Stored properties
    var id: Int64?
    var name: String                  // user-visible label, e.g. "Work ↔ NAS"
    var leftPath: String              // absolute path, left side
    var rightPath: String             // absolute path, right side

    // Sync trigger mode
    var syncMode: SyncMode            // manual | realtime | scheduled | all

    // Scheduled interval in seconds (used when syncMode == .scheduled or .all)
    var scheduleIntervalSeconds: Int

    // Secure backup
    var backupEnabled: Bool
    var backupPath: String?           // nil when backupEnabled == false

    // Checksum strategy
    var checksumEnabled: Bool         // true = SHA-256, false = modDate+size only

    // Timestamps
    var createdAt: Date
    var lastSyncedAt: Date?

    // MARK: - Database table
    static let databaseTableName = "sync_pairs"

    // MARK: - Column definitions for queries
    enum Columns {
        static let id = Column("id")
        static let name = Column("name")
        static let leftPath = Column("leftPath")
        static let rightPath = Column("rightPath")
        static let syncMode = Column("syncMode")
        static let scheduleIntervalSeconds = Column("scheduleIntervalSeconds")
        static let backupEnabled = Column("backupEnabled")
        static let backupPath = Column("backupPath")
        static let checksumEnabled = Column("checksumEnabled")
        static let createdAt = Column("createdAt")
        static let lastSyncedAt = Column("lastSyncedAt")
    }

    // MARK: - Relationships
    static let exclusionRules = hasMany(ExclusionRule.self, using: ExclusionRule.syncPairForeignKey)
    static let trackedFiles  = hasMany(TrackedFile.self,   using: TrackedFile.syncPairForeignKey)
    static let backupRecords = hasMany(BackupRecord.self,  using: BackupRecord.syncPairForeignKey)

    // MARK: - Init
    init(
        id: Int64? = nil,
        name: String,
        leftPath: String,
        rightPath: String,
        syncMode: SyncMode = .manual,
        scheduleIntervalSeconds: Int = 300,
        backupEnabled: Bool = true,
        backupPath: String? = nil,
        checksumEnabled: Bool = false, // Default to false for performance
        createdAt: Date = Date(),
        lastSyncedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.leftPath = leftPath
        self.rightPath = rightPath
        self.syncMode = syncMode
        self.scheduleIntervalSeconds = scheduleIntervalSeconds
        self.backupEnabled = backupEnabled
        self.backupPath = backupPath
        self.checksumEnabled = checksumEnabled
        self.createdAt = createdAt
        self.lastSyncedAt = lastSyncedAt
    }
}

// MARK: - MutablePersistableRecord (auto-assign generated id)
extension SyncPair: MutablePersistableRecord {
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

// MARK: - SyncMode
enum SyncMode: String, Codable, CaseIterable {
    case manual    = "manual"
    case realtime  = "realtime"
    case scheduled = "scheduled"
    case all       = "all"

    var displayName: String {
        switch self {
        case .manual:    return "Manual"
        case .realtime:  return "Real-time (FSEvents)"
        case .scheduled: return "Scheduled"
        case .all:       return "All (Real-time + Scheduled)"
        }
    }
}
