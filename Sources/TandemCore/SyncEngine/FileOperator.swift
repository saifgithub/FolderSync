import Foundation

/// Low-level file operations used by the sync engine.
/// All operations are performed synchronously on the calling thread.
/// The caller (SyncManager) is responsible for running these off the main thread.
final class FileOperator {

    private let fm = FileManager.default

    // MARK: - Copy

    /// Copies `sourceURL` to `destinationURL`, creating intermediate directories as needed.
    /// If a file already exists at the destination it is replaced atomically.
    func copy(from sourceURL: URL, to destinationURL: URL) throws {
        try createParentDirectoryIfNeeded(for: destinationURL)

        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fm.copyItem(at: sourceURL, to: destinationURL)
        }
    }

    // MARK: - Delete

    /// Moves `fileURL` to trash rather than permanently deleting it.
    func trash(fileURL: URL) throws {
        var resultURL: NSURL?
        try fm.trashItem(at: fileURL, resultingItemURL: &resultURL)
    }

    /// Permanently deletes `fileURL`.
    func delete(fileURL: URL) throws {
        try fm.removeItem(at: fileURL)
    }

    // MARK: - Move (used by BackupManager)

    /// Moves `sourceURL` to `destinationURL` atomically, creating parent directories.
    func move(from sourceURL: URL, to destinationURL: URL) throws {
        try createParentDirectoryIfNeeded(for: destinationURL)
        try fm.moveItem(at: sourceURL, to: destinationURL)
    }

    // MARK: - Helpers

    func createParentDirectoryIfNeeded(for url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    /// Absolute URL for a relative path under a given root.
    func absoluteURL(relativePath: String, root: URL) -> URL {
        root.appendingPathComponent(relativePath)
    }
}
