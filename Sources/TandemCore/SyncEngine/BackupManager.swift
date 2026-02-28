import Foundation

/// Moves a file to the secure backup folder before it is overwritten or deleted,
/// then persists a `BackupRecord` in the database.
final class BackupManager {

    private let fileOperator: FileOperator
    private let scanner: FileScanner

    init(fileOperator: FileOperator = FileOperator(), scanner: FileScanner = FileScanner()) {
        self.fileOperator = fileOperator
        self.scanner = scanner
    }

    // MARK: - Public API

    /// Backs up the file at `sourceURL` and records it in the DB.
    /// - Parameters:
    ///   - sourceURL:   The file about to be overwritten / deleted.
    ///   - relativePath: Relative path used to describe the file in the record.
    ///   - side:        Which side of the pair the file belongs to.
    ///   - pair:        The sync pair (provides backup folder location).
    /// - Returns: The inserted `BackupRecord`.
    @discardableResult
    func backup(
        sourceURL: URL,
        relativePath: String,
        side: SyncSide,
        pair: SyncPair
    ) throws -> BackupRecord {

        guard pair.backupEnabled else {
            throw BackupError.backupDisabled
        }

        guard let backupPath = pair.backupPath, !backupPath.isEmpty else {
            throw BackupError.noBackupFolder
        }

        // Generate unique backup name: originalName_YYYYMMDD_HHmmss.ext
        let backupName = BackupRecord.makeBackupFileName(for: sourceURL)
        let backupFolder = URL(fileURLWithPath: backupPath)
        let destinationURL = backupFolder.appendingPathComponent(backupName)

        // Get file metadata before moving
        let resourceValues = try sourceURL.resourceValues(forKeys: [
            .fileSizeKey, .contentModificationDateKey
        ])
        let size     = Int64(resourceValues.fileSize ?? 0)
        let checksum = pair.checksumEnabled ? (try? scanner.sha256(url: sourceURL)) : nil

        // Move file to backup folder
        try fileOperator.move(from: sourceURL, to: destinationURL)

        // Persist record
        guard let pairId = pair.id else { throw BackupError.invalidPairId }

        var record = BackupRecord(
            pairId: pairId,
            originalRelativePath: relativePath,
            originalSide: side,
            backupFileName: backupName,
            backupFolderPath: backupPath,
            backedUpAt: Date(),
            sizeBytes: size,
            checksum: checksum
        )

        try DatabaseManager.shared.write { db in
            try record.insert(db)
        }

        return record
    }

    // MARK: - Errors
    enum BackupError: LocalizedError {
        case backupDisabled
        case noBackupFolder
        case invalidPairId

        var errorDescription: String? {
            switch self {
            case .backupDisabled:  return "Secure backup is disabled for this pair."
            case .noBackupFolder:  return "No backup folder has been configured."
            case .invalidPairId:   return "Sync pair has not been saved yet."
            }
        }
    }
}
