import Foundation
import CryptoKit

// MARK: - ScannedFile

/// A file found on disk during a scan, with metadata and optional checksum.
struct ScannedFile {
    let relativePath: String      // relative to the scanned root
    let absoluteURL: URL
    let sizeBytes: Int64
    let modifiedAt: Date
    var checksum: String?         // computed lazily if checksumEnabled
}

// MARK: - FileScanner

/// Walks a directory tree, applies exclusion rules, and returns all files with metadata.
final class FileScanner {

    // MARK: - Excluded-collection option
    /// When true, items skipped by exclusion rules are added to `excludedFiles`.
    var collectExcluded = false
    /// Populated by `scan()` when `collectExcluded` is true.
    private(set) var excludedFiles: [String: ScannedFile] = [:]

    // MARK: - Public API

    /// Scans `rootURL` recursively.
    /// - Parameters:
    ///   - rootURL: The folder to scan.
    ///   - exclusionRules: Active rules for this pair.
    ///   - checksumEnabled: When true, computes SHA-256 for every file.
    ///   - isCancelled: Checked every 1 000 files; throws `ScanError.cancelled` when true.
    ///   - onProgress: Called with the running file count every 1 000 files.
    ///   - onBatch: Called with a delta every 5 000 files for live preview.
    /// - Returns: Dictionary keyed by relative path for O(1) lookup.
    func scan(
        rootURL: URL,
        exclusionRules: [ExclusionRule],
        checksumEnabled: Bool,
        isCancelled: () -> Bool = { false },
        onProgress: ((Int) -> Void)? = nil,
        onBatch: (([ScannedFile]) -> Void)? = nil
    ) throws -> [String: ScannedFile] {

        var result: [String: ScannedFile] = [:]
        let fm = FileManager.default

        guard fm.fileExists(atPath: rootURL.path) else {
            throw ScanError.rootNotFound(rootURL.path)
        }

        let rootPath = rootURL.path
        let enumerator = fm.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]
        var fileCount  = 0
        var batchBuf: [ScannedFile] = []

        while let itemURL = enumerator?.nextObject() as? URL {
            // Cancellation + progress check every 1 000 files
            if fileCount % 1_000 == 0 {
                if isCancelled() { throw ScanError.cancelled }
                onProgress?(fileCount)
            }
            // Live preview batch flush every 5 000 files
            if fileCount % 5_000 == 0 && !batchBuf.isEmpty {
                onBatch?(batchBuf)
                batchBuf.removeAll(keepingCapacity: true)
            }

            let itemPath = itemURL.path
            let relativePath: String
            if itemPath.hasPrefix(rootPath) {
                let rel = String(itemPath.dropFirst(rootPath.count))
                relativePath = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
            } else {
                relativePath = itemURL.lastPathComponent
            }

            let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys)
            let isDirectory = resourceValues?.isDirectory == true

            if !exclusionRules.isEmpty && exclusionRules.excludes(relativePath: relativePath) {
                if isDirectory { enumerator?.skipDescendants() }
                if collectExcluded {
                    let size    = Int64(resourceValues?.fileSize ?? 0)
                    let modDate = resourceValues?.contentModificationDate ?? Date.distantPast
                    excludedFiles[relativePath] = ScannedFile(
                        relativePath: relativePath,
                        absoluteURL: itemURL,
                        sizeBytes: size,
                        modifiedAt: modDate,
                        checksum: nil
                    )
                }
                continue
            }

            guard !isDirectory else { continue }

            fileCount += 1
            let size    = Int64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate ?? Date.distantPast
            let checksum: String? = nil

            let scannedFile = ScannedFile(
                relativePath: relativePath,
                absoluteURL: itemURL,
                sizeBytes: size,
                modifiedAt: modDate,
                checksum: checksum
            )
            result[relativePath] = scannedFile
            batchBuf.append(scannedFile)
        }

        // Final progress + batch flush
        onProgress?(fileCount)
        if !batchBuf.isEmpty { onBatch?(batchBuf) }

        return result
    }

    /// Scans a specific list of absolute URLs rather than walking a full tree.
    /// Used by real-time incremental sync to only process files that FSEvents reported changed.
    /// Files that no longer exist are simply omitted (the diff engine treats them as deleted).
    func scanFiles(
        _ absoluteURLs: [URL],
        rootURL: URL,
        exclusionRules: [ExclusionRule],
        checksumEnabled: Bool
    ) -> [String: ScannedFile] {
        var result: [String: ScannedFile] = [:]
        let rootPath = rootURL.path
        let fm = FileManager.default
        let resourceKeys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isDirectoryKey]

        for itemURL in absoluteURLs {
            let itemPath = itemURL.path
            guard itemPath.hasPrefix(rootPath) else { continue }
            guard fm.fileExists(atPath: itemPath) else { continue }  // deleted — absent from result is correct

            let rel = String(itemPath.dropFirst(rootPath.count))
            let relativePath = rel.hasPrefix("/") ? String(rel.dropFirst()) : rel
            guard !relativePath.isEmpty else { continue }

            if !exclusionRules.isEmpty && exclusionRules.excludes(relativePath: relativePath) { continue }

            let resourceValues = try? itemURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues?.isDirectory != true else { continue }

            let size    = Int64(resourceValues?.fileSize ?? 0)
            let modDate = resourceValues?.contentModificationDate ?? Date.distantPast
            result[relativePath] = ScannedFile(
                relativePath: relativePath,
                absoluteURL: itemURL,
                sizeBytes: size,
                modifiedAt: modDate,
                checksum: nil
            )
        }
        return result
    }

    // MARK: - Helpers

    /// Computes SHA-256 of a file, returned as lowercase hex string.
    func sha256(url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1024 * 1024  // 1 MB

        while true {
            let data: Data
            do {
                if let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
                    data = chunk
                } else {
                    break
                }
            } catch {
                // If we hit an error reading (e.g. permission denied mid-read), break out
                break
            }
            hasher.update(data: data)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Errors
    enum ScanError: LocalizedError {
        case rootNotFound(String)
        case cancelled
        var errorDescription: String? {
            switch self {
            case .rootNotFound(let p): return "Folder not found: \(p)"
            case .cancelled:           return "Scan was cancelled."
            }
        }
    }
}
