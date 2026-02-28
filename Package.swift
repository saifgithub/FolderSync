// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tandem",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.0.0")
    ],
    targets: [
        // ── Core library — all app logic, importable by tests ───────────────
        .target(
            name: "TandemCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "Sources/TandemCore"
        ),

        // ── Executable — just the entry point ───────────────────────────────
        .executableTarget(
            name: "Tandem",
            dependencies: ["TandemCore"],
            path: "Sources/Tandem"
        ),

        // ── Tests ────────────────────────────────────────────────────────────
        .testTarget(
            name: "TandemTests",
            dependencies: ["TandemCore"],
            path: "Tests/TandemTests"
        )
    ]
)
