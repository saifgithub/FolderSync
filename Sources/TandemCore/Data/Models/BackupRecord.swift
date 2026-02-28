import GRDB
import Foundation

/// Records every file that was moved to the secure backup folder before being overwritten.
struct BackupRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable {

    var id: Int64?
    var pairId: Int64
    var originalRelativePath: String   // e.g. "docs/report.pdf"
    var originalSide: SyncSide         // which side the file came from
    var backupFileName: String         // e.g. "report_20260226_143012.pdf"
    var backupFolderPath: String       // absolute path of the backup folder used
    var backedUpAt: Date
    var sizeBytes: Int64
    var checksum: String?

    // MARK: - Table
    static let databaseTableName = "backup_records"
    static let syncPairForeignKey = ForeignKey(["pairId"])

    enum Columns {
        static let id                   = Column("id")
        static let pairId               = Column("pairId")
        static let originalRelativePath = Column("originalRelativePath")
        static let originalSide         = Column("originalSide")
        static let backupFileName       = Column("backupFileName")
        static let backupFolderPath     = Column("backupFolderPath")
        static let backedUpAt           = Column("backedUpAt")
        static let sizeBytes            = Column("sizeBytes")
        static let checksum             = Column("checksum")
    }

    // MARK: - MutablePersistableRecord
    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    // MARK: - Helpers

    /// Generates the backup filename: originalName_YYYYMMDD_HHmmss.ext
    static func makeBackupFileName(for originalURL: URL, at date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let stamp = formatter.string(from: date)

        let base = originalURL.deletingPathExtension().lastPathComponent
        let ext  = originalURL.pathExtension

        return ext.isEmpty ? "\(base)_\(stamp)" : "\(base)_\(stamp).\(ext)"
    }

    /// Full URL of the backup file on disk.
    var backupFileURL: URL {
        URL(fileURLWithPath: backupFolderPath).appendingPathComponent(backupFileName)
    }
}
