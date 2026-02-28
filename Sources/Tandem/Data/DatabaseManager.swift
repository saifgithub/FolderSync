import GRDB
import Foundation

/// Central database access object. Use `DatabaseManager.shared` throughout the app.
final class DatabaseManager {

    // MARK: - Singleton
    static let shared = DatabaseManager()
    private init() {}

    // MARK: - Internal pool
    private var dbPool: DatabasePool?

    // MARK: - Setup

    /// Creates (or opens) the SQLite database and runs all pending migrations.
    func setup() throws {
        let fileURL = try databaseFileURL()

        var config = Configuration()
        config.label = "Tandem.DatabasePool"

        let pool = try DatabasePool(path: fileURL.path, configuration: config)
        self.dbPool = pool

        try runMigrations(on: pool)
    }

    // MARK: - Public read / write access

    func read<T>(_ block: (Database) throws -> T) throws -> T {
        guard let pool = dbPool else { throw DBError.notSetup }
        return try pool.read(block)
    }

    func write<T>(_ block: (Database) throws -> T) throws -> T {
        guard let pool = dbPool else { throw DBError.notSetup }
        return try pool.write(block)
    }

    // MARK: - Observation helpers (GRDB ValueObservation bridge)

    func observe<T: FetchRequest>(
        _ request: T,
        onChange: @escaping ([T.RowDecoder]) -> Void
    ) throws -> AnyObject where T.RowDecoder: FetchableRecord {
        guard let pool = dbPool else { throw DBError.notSetup }
        let observation = ValueObservation.tracking(request.fetchAll)
        let cancellable = observation.start(in: pool) { error in
            // log but don't crash on observation errors
            print("[DB] Observation error: \(error)")
        } onChange: { rows in
            DispatchQueue.main.async { onChange(rows) }
        }
        return cancellable as AnyObject
    }

    // MARK: - File location

    private func databaseFileURL() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Tandem", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("tandem.sqlite")
    }

    // MARK: - Migrations

    private func runMigrations(on pool: DatabasePool) throws {
        var migrator = DatabaseMigrator()

        // ── v1: initial schema ──────────────────────────────────────────────
        migrator.registerMigration("v1_initial") { db in

            // sync_pairs
            try db.create(table: "sync_pairs", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("leftPath", .text).notNull()
                t.column("rightPath", .text).notNull()
                t.column("syncMode", .text).notNull().defaults(to: "manual")
                t.column("scheduleIntervalSeconds", .integer).notNull().defaults(to: 300)
                t.column("backupEnabled", .boolean).notNull().defaults(to: true)
                t.column("backupPath", .text)
                t.column("checksumEnabled", .boolean).notNull().defaults(to: true)
                t.column("createdAt", .datetime).notNull()
                t.column("lastSyncedAt", .datetime)
            }

            // tracked_files
            try db.create(table: "tracked_files", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pairId", .integer).notNull()
                    .indexed()
                    .references("sync_pairs", onDelete: .cascade)
                t.column("relativePath", .text).notNull()
                t.column("side", .text).notNull()
                t.column("sizeBytes", .integer).notNull()
                t.column("modifiedAt", .datetime).notNull()
                t.column("checksum", .text)
                t.column("syncedAt", .datetime).notNull()
                // one record per (pair, path, side)
                t.uniqueKey(["pairId", "relativePath", "side"])
            }

            // backup_records
            try db.create(table: "backup_records", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pairId", .integer).notNull()
                    .indexed()
                    .references("sync_pairs", onDelete: .cascade)
                t.column("originalRelativePath", .text).notNull()
                t.column("originalSide", .text).notNull()
                t.column("backupFileName", .text).notNull()
                t.column("backupFolderPath", .text).notNull()
                t.column("backedUpAt", .datetime).notNull()
                t.column("sizeBytes", .integer).notNull()
                t.column("checksum", .text)
            }

            // exclusion_rules
            try db.create(table: "exclusion_rules", ifNotExists: true) { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("pairId", .integer).notNull()
                    .indexed()
                    .references("sync_pairs", onDelete: .cascade)
                t.column("ruleType", .text).notNull()
                t.column("pattern", .text).notNull()
                t.column("isEnabled", .boolean).notNull().defaults(to: true)
            }
        }

        // ── future migrations go here ────────────────────────────────────────
        // migrator.registerMigration("v2_...") { db in ... }

        try migrator.migrate(pool)
    }

    // MARK: - Errors
    enum DBError: Error {
        case notSetup
    }
}
