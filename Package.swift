// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "FolderSync",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        // ── Core library — all app logic, importable by tests ───────────────
        .target(
            name: "FolderSyncCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/FolderSyncCore"
        ),

        // ── Executable — just the entry point ───────────────────────────────
        .executableTarget(
            name: "FolderSync",
            dependencies: ["FolderSyncCore"],
            path: "Sources/FolderSync"
        ),

        // ── Tests ────────────────────────────────────────────────────────────
        .testTarget(
            name: "FolderSyncTests",
            dependencies: ["FolderSyncCore"],
            path: "Tests/FolderSyncTests"
        )
    ]
)
