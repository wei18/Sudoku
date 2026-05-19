// swift-tools-version: 6.2
import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets

let productionTargets: [Target] = [
    .target(name: "SudokuEngine", swiftSettings: swiftSettings),
    .target(name: "GameState", dependencies: ["SudokuEngine"], swiftSettings: swiftSettings),
    .target(name: "PuzzleStore", dependencies: ["SudokuEngine", "Telemetry"], swiftSettings: swiftSettings),
    .target(name: "Persistence", dependencies: ["GameState", "Telemetry"], swiftSettings: swiftSettings),
    .target(name: "GameCenterClient", dependencies: ["Telemetry", "Persistence"], swiftSettings: swiftSettings),
    // Telemetry depends on GameState ONLY to ship GameStateTelemetryAdapter:
    // GameState declares the local `GameStateTelemetry` seam + `GameStateEvent`
    // values; Telemetry provides the production adapter that maps those events
    // onto `TelemetryEvent` and forwards through the fan-out facade. GameState
    // does NOT import Telemetry (it stays on the protocol seam) so there is
    // no cycle. Direction-of-dependency reasoning: GameState is "deeper"
    // (no IO, pure logic) than Telemetry (Apple system imports), so this
    // direction is correct per design.md §How.1.
    .target(name: "Telemetry", dependencies: ["GameState"], swiftSettings: swiftSettings),
    .target(
        name: "SudokuUI",
        dependencies: ["GameState", "PuzzleStore", "Persistence", "GameCenterClient", "Telemetry"],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "SudokuKitTesting",
        dependencies: ["SudokuEngine", "GameState", "PuzzleStore", "Persistence", "GameCenterClient", "Telemetry"],
        swiftSettings: swiftSettings
    ),
    // Phase 9.1: production composition root. The App target is intentionally
    // thin and depends only on this product (which re-exports SudokuUI via
    // its public surface). Keeps the DI plumbing inside the SwiftPM package
    // where it's testable.
    .target(
        name: "AppComposition",
        dependencies: [
            "SudokuEngine",
            "GameState",
            "PuzzleStore",
            "Persistence",
            "GameCenterClient",
            "Telemetry",
            "SudokuUI",
            // `.preview()` and `.tests()` factories pull from SudokuKitTesting
            // for the protocol fakes. Shipped in the binary; the `.live()`
            // factory does not reference them so dead-code elimination keeps
            // the cost bounded.
            "SudokuKitTesting",
        ],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Test targets (one per production target, except SudokuKitTesting which
// IS the shared testing helpers consumed by these test targets.)

func testTarget(_ name: String, dependencies: [Target.Dependency]) -> Target {
    // Snapshot baselines are read by pointfreeco/swift-snapshot-testing
    // directly from the source tree via `#filePath`, so they don't need
    // to be bundled — but SwiftPM's "unhandled file" detection still flags
    // them. Exclude `__Snapshots__/` from the test target file scan to
    // keep `swift test` warning-free.
    .testTarget(
        name: "\(name)Tests",
        dependencies: dependencies + [
            "SudokuKitTesting",
            .product(name: "SnapshotTesting", package: "swift-snapshot-testing"),
        ],
        exclude: name == "SudokuUI" ? ["__Snapshots__"] : [],
        swiftSettings: swiftSettings
    )
}

let testTargets: [Target] = [
    testTarget("SudokuEngine", dependencies: ["SudokuEngine"]),
    testTarget("GameState", dependencies: ["GameState"]),
    testTarget("PuzzleStore", dependencies: ["PuzzleStore"]),
    testTarget("Persistence", dependencies: ["Persistence"]),
    testTarget("GameCenterClient", dependencies: ["GameCenterClient"]),
    testTarget("Telemetry", dependencies: ["Telemetry"]),
    testTarget("SudokuUI", dependencies: ["SudokuUI"]),
    testTarget("AppComposition", dependencies: ["AppComposition"]),
]

// MARK: - Package

let package = Package(
    name: "SudokuKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "SudokuEngine", targets: ["SudokuEngine"]),
        .library(name: "GameState", targets: ["GameState"]),
        .library(name: "PuzzleStore", targets: ["PuzzleStore"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "GameCenterClient", targets: ["GameCenterClient"]),
        .library(name: "Telemetry", targets: ["Telemetry"]),
        .library(name: "SudokuUI", targets: ["SudokuUI"]),
        .library(name: "SudokuKitTesting", targets: ["SudokuKitTesting"]),
        .library(name: "AppComposition", targets: ["AppComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
