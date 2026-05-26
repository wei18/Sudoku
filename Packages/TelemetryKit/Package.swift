// swift-tools-version: 6.2

// swiftlint:disable trailing_comma

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Production targets
//
// TelemetryKit is the third sibling local package extracted from SudokuKit
// (Stage 2 of the staged module split — see docs/foundations.md §2 演進 +
// meetings/2026-05-26_module-split-proposal.md).
//
// Why extract: Telemetry is a leaf module — pure values + protocol seam,
// zero Apple framework imports (no UIKit / CloudKit / GameKit). Extracting
// makes it reusable across other apps (current trigger: 2nd-app reuse,
// user decision 2026-05-26).
//
// Dep direction:
//   SudokuCoreKit (SudokuEngine + GameState)  ← TelemetryKit (Telemetry)
//   - Telemetry's `GameStateTelemetryAdapter` maps `GameStateEvent` → `TelemetryEvent`
//   - GameState defines the seam; Telemetry provides the adapter
//   - GameState does NOT import Telemetry (one-way arrow preserved)

let package = Package(
    name: "TelemetryKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Telemetry", targets: ["Telemetry"]),
        // Test-support library — shared fixtures (FakeLogger / MetricPayloadFixtures /
        // RecordingSink) extracted from SudokuKitTesting. Consumed by TelemetryTests
        // here AND by SudokuKit's Persistence + AppComposition test targets via
        // `.product(name: "TelemetryTesting", package: "TelemetryKit")`.
        .library(name: "TelemetryTesting", targets: ["TelemetryTesting"]),
    ],
    dependencies: [
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
    ],
    targets: [
        .target(
            name: "Telemetry",
            dependencies: [
                .product(name: "SudokuEngine", package: "SudokuCoreKit"),
                .product(name: "GameState", package: "SudokuCoreKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "TelemetryTesting",
            dependencies: [
                "Telemetry",
                .product(name: "GameState", package: "SudokuCoreKit"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "TelemetryTests",
            dependencies: [
                "Telemetry",
                "TelemetryTesting",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
