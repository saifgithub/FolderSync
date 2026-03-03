import Foundation

/// Low-level file operations used by the sync engine.
/// All operations are performed synchronously on the calling thread.
/// The caller (SyncManager) is responsible for running these off the main thread.
final class FileOperator {

    private let fm = FileManager.default

    // MARK: - Copy

    /// Copies `sourceURL` to `destinationURL`, creating intermediate directories as needed.
    /// If a file already exists at the destination it is replaced atomically.
    /// The destination's modification date is explicitly stamped to match the source so that
    /// the DB snapshot (which stores the source's modifiedAt) stays in sync with disk reality.
    func copy(from sourceURL: URL, to destinationURL: URL) throws {
        try createParentDirectoryIfNeeded(for: destinationURL)

        // Capture source modification date BEFORE the copy — replaceItemAt does not
        // guarantee the resulting file keeps the source's modification date.
        let srcMod = (try? sourceURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate

        if fm.fileExists(atPath: destinationURL.path) {
            _ = try fm.replaceItemAt(destinationURL, withItemAt: sourceURL)
        } else {
            try fm.copyItem(at: sourceURL, to: destinationURL)
        }

        // Stamp destination mod date to exactly match source.
        // This keeps the file on disk, the pre-copy scan metadata, and the DB snapshot
        // all in agreement so the next scan does not see a false "updated" diff.
        if let mod = srcMod {
            try? fm.setAttributes([.modificationDate: mod], ofItemAtPath: destinationURL.path)
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
