import XCTest
@testable import FolderSyncCore

// MARK: - DiffEngine Tests

final class DiffEngineTests: XCTestCase {

    private let engine = DiffEngine()

    // Helper to make a ScannedFile
    private func file(_ path: String, size: Int64 = 1024, mod: Date = Date(), checksum: String? = nil) -> ScannedFile {
        ScannedFile(
            relativePath: path,
            absoluteURL: URL(fileURLWithPath: "/tmp/" + path),
            sizeBytes: size,
            modifiedAt: mod,
            checksum: checksum
        )
    }

    // Helper to make a TrackedFile snapshot
    private func snap(_ path: String, side: SyncSide, size: Int64 = 1024, mod: Date = Date(), checksum: String? = nil) -> TrackedFile {
        TrackedFile(pairId: 1, relativePath: path, side: side, sizeBytes: size, modifiedAt: mod, checksum: checksum)
    }

    // MARK: - Same

    func testSameFile_checksumMatch() {
        let leftScan  = ["docs/a.txt": file("docs/a.txt", checksum: "abc123")]
        let rightScan = ["docs/a.txt": file("docs/a.txt", checksum: "abc123")]
        let snapshots = [snap("docs/a.txt", side: .left, checksum: "abc123"),
                         snap("docs/a.txt", side: .right, checksum: "abc123")]

        let diffs = engine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: true)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .same)
    }

    // MARK: - New

    func testNewFileOnLeft_notInRightOrSnapshot() {
        let leftScan  = ["new.txt": file("new.txt")]
        let rightScan: [String: ScannedFile] = [:]
        let snapshots: [TrackedFile] = []

        let diffs = engine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: false)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .new(.left))
    }

    // MARK: - Deleted

    func testDeletedFromLeft_presentInSnapshotBothSides() {
        let leftScan: [String: ScannedFile] = [:]
        let rightScan = ["report.pdf": file("report.pdf")]
        let snapshots = [snap("report.pdf", side: .left),
                         snap("report.pdf", side: .right)]

        let diffs = engine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: false)
        XCTAssertEqual(diffs.count, 1)
        if case .deleted(let side) = diffs[0].status {
            XCTAssertEqual(side, .left)
        } else {
            XCTFail("Expected .deleted(.left), got \(diffs[0].status)")
        }
    }

    // MARK: - Updated

    func testUpdatedOnLeft_checksumChanged() {
        let now  = Date()
        let then = now.addingTimeInterval(-3600)

        let leftScan  = ["img.png": file("img.png", size: 2048, mod: now, checksum: "new")]
        let rightScan = ["img.png": file("img.png", size: 1024, mod: then, checksum: "old")]
        let snapshots = [snap("img.png", side: .left,  size: 1024, mod: then, checksum: "old"),
                         snap("img.png", side: .right, size: 1024, mod: then, checksum: "old")]

        let diffs = engine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: true)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .updated(newer: .left))
    }

    // MARK: - Clash

    func testClash_bothSidesChanged() {
        let base = Date().addingTimeInterval(-7200)
        let now  = Date()

        let leftScan  = ["data.csv": file("data.csv", size: 3000, mod: now, checksum: "newLeft")]
        let rightScan = ["data.csv": file("data.csv", size: 2500, mod: now, checksum: "newRight")]
        let snapshots = [snap("data.csv", side: .left,  size: 1000, mod: base, checksum: "orig"),
                         snap("data.csv", side: .right, size: 1000, mod: base, checksum: "orig")]

        let diffs = engine.diff(leftScan: leftScan, rightScan: rightScan, snapshots: snapshots, checksumEnabled: true)
        XCTAssertEqual(diffs.count, 1)
        XCTAssertEqual(diffs[0].status, .clash)
    }

    // MARK: - Summary

    func testSummaryTooltip_mixed() {
        let diffs: [FileDiff] = [
            FileDiff(relativePath: "a.txt", status: .same,           leftFile: nil, rightFile: nil, leftSnapshot: nil, rightSnapshot: nil),
            FileDiff(relativePath: "b.txt", status: .new(.left),     leftFile: nil, rightFile: nil, leftSnapshot: nil, rightSnapshot: nil),
            FileDiff(relativePath: "c.txt", status: .clash,          leftFile: nil, rightFile: nil, leftSnapshot: nil, rightSnapshot: nil),
            FileDiff(relativePath: "d.txt", status: .updated(newer: .right), leftFile: nil, rightFile: nil, leftSnapshot: nil, rightSnapshot: nil)
        ]
        let summary = engine.summary(of: diffs)
        XCTAssertEqual(summary.same,    1)
        XCTAssertEqual(summary.new,     1)
        XCTAssertEqual(summary.clashes, 1)
        XCTAssertEqual(summary.updated, 1)
        XCTAssertFalse(summary.tooltipString.isEmpty)
    }
}

// MARK: - ExclusionRule Tests

final class ExclusionRuleTests: XCTestCase {

    func testGlobRule_matchesTmpFiles() {
        let rule = ExclusionRule(pairId: 1, ruleType: .glob, pattern: "*.tmp", isEnabled: true)
        XCTAssertTrue(rule.matches(relativePath: "docs/temp.tmp"))
        XCTAssertFalse(rule.matches(relativePath: "docs/report.pdf"))
    }

    func testFilenameRule_exactMatch() {
        let rule = ExclusionRule(pairId: 1, ruleType: .filename, pattern: ".DS_Store", isEnabled: true)
        XCTAssertTrue(rule.matches(relativePath: "subdir/.DS_Store"))
        XCTAssertFalse(rule.matches(relativePath: "DS_Store.txt"))
    }

    func testFolderRule_subtreeExcluded() {
        let rule = ExclusionRule(pairId: 1, ruleType: .folder, pattern: "node_modules/", isEnabled: true)
        XCTAssertTrue(rule.matches(relativePath: "node_modules/lodash/index.js"))
        XCTAssertFalse(rule.matches(relativePath: "src/main.js"))
    }

    func testFilepathRule_specificFile() {
        let rule = ExclusionRule(pairId: 1, ruleType: .filepath, pattern: "config/secrets.json", isEnabled: true)
        XCTAssertTrue(rule.matches(relativePath: "config/secrets.json"))
        XCTAssertFalse(rule.matches(relativePath: "config/settings.json"))
    }

    func testDisabledRule_doesNotMatch() {
        let rule = ExclusionRule(pairId: 1, ruleType: .filename, pattern: ".DS_Store", isEnabled: false)
        XCTAssertFalse(rule.matches(relativePath: ".DS_Store"))
    }
}

// MARK: - BackupRecord naming

final class BackupRecordTests: XCTestCase {
    func testBackupFileName_includesTimestamp() {
        let url = URL(fileURLWithPath: "/tmp/report.pdf")
        let date = ISO8601DateFormatter().date(from: "2026-02-26T14:30:12Z")!
        let name = BackupRecord.makeBackupFileName(for: url, at: date)
        XCTAssertTrue(name.hasPrefix("report_"))
        XCTAssertTrue(name.hasSuffix(".pdf"))
        XCTAssertTrue(name.contains("20260226"))
    }
}
