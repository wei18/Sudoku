// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - Shared dep shorthands
//
// SudokuEngine + GameState live in the sibling SudokuCoreKit package as of
// the 2026-05-26 module split (see `docs/foundations.md §2`). Every target
// that previously listed them as in-package string deps now pulls them via
// `.product(name:package:)` from SudokuCoreKit.

let sudokuEngineDep: Target.Dependency = .product(name: "SudokuEngine", package: "SudokuCoreKit")
let gameStateDep: Target.Dependency = .product(name: "GameState", package: "SudokuCoreKit")
// Telemetry extracted into sibling TelemetryKit package on 2026-05-26
// (Stage 2 of the module split). See `docs/foundations.md §2`.
let telemetryDep: Target.Dependency = .product(name: "Telemetry", package: "TelemetryKit")
// TelemetryTesting — FakeLogger / RecordingSink / MetricPayloadFixtures.
// Carved out of SudokuKitTesting/Telemetry/ on Stage 2 so test targets that
// only need the Telemetry-shaped fixtures don't pay for the broader
// SudokuKitTesting surface.
let telemetryTestingDep: Target.Dependency = .product(name: "TelemetryTesting", package: "TelemetryKit")
// Persistence + GameCenterClient extracted into sibling PersistenceKit /
// GameCenterKit packages on 2026-05-26 (Stage 3 of the module split). See
// `docs/foundations.md §2`. Their fixtures live in PersistenceTesting /
// GameCenterTesting library products on the same sibling packages.
let persistenceDep: Target.Dependency = .product(name: "Persistence", package: "PersistenceKit")
let gameCenterClientDep: Target.Dependency = .product(name: "GameCenterClient", package: "GameCenterKit")
let gameCenterTestingDep: Target.Dependency = .product(name: "GameCenterTesting", package: "GameCenterKit")

// MARK: - Production targets

let productionTargets: [Target] = [
    .target(name: "PuzzleStore", dependencies: [sudokuEngineDep, telemetryDep], swiftSettings: swiftSettings),
    .target(
        name: "SudokuUI",
        dependencies: [
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            // v2.3.3: RouteFactory holds AdProvider / IAPClient / AdGate
            // protocol deps so individual destination Views (v2.3.4-6) can
            // pull them at construction. SudokuUI does not depend on the
            // AdMob / StoreKit2 concrete-impl targets — those stay isolated
            // in AppComposition (foundations.md §9.1).
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "SudokuKitTesting",
        // `PersistenceTesting` pulled in for `PuzzleFixtures` (consumed by
        // `FakePuzzleProvider` in this target). PuzzleFixtures lives in
        // PersistenceTesting after Stage 3 carve-out because PersistenceTests
        // are its primary consumer; SudokuKitTesting reaches for it via the
        // existing SudokuKit → PersistenceKit dep arrow (no cycle).
        dependencies: [
            sudokuEngineDep,
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            .product(name: "PersistenceTesting", package: "PersistenceKit"),
            gameCenterClientDep,
            telemetryDep,
        ],
        swiftSettings: swiftSettings
    ),
    // Phase 9.1: production composition root. The App target is intentionally
    // thin and depends only on this product (which re-exports SudokuUI via
    // its public surface). Keeps the DI plumbing inside the SwiftPM package
    // where it's testable.
    .target(
        name: "AppComposition",
        dependencies: [
            sudokuEngineDep,
            gameStateDep,
            "PuzzleStore",
            persistenceDep,
            gameCenterClientDep,
            telemetryDep,
            "SudokuUI",
            // `.preview()` and `.tests()` factories pull from SudokuKitTesting
            // for the protocol fakes. Shipped in the binary; the `.live()`
            // factory does not reference them so dead-code elimination keeps
            // the cost bounded.
            "SudokuKitTesting",
            // Stage 3: GameCenter fakes carved out of SudokuKitTesting into
            // GameCenterTesting; `Preview.swift` consumes `FakeGameCenterClient`
            // for the `.preview()` factory.
            gameCenterTestingDep,
            // v2.3.2: monetization wiring. AppComposition.live builds
            // LiveAdMobAdProvider + LiveStoreKit2IAPClient + AdGate via
            // LiveMonetizationStateStore. Preview / tests use MonetizationTesting fakes.
            .product(name: "MonetizationCore", package: "AppMonetizationKit"),
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
            .product(name: "IAPStoreKit2", package: "AppMonetizationKit"),
            .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
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

// Convenience dep set used by tests that need to construct AdGate / monetization fakes.
let monetizationTestDeps: [Target.Dependency] = [
    .product(name: "MonetizationCore", package: "AppMonetizationKit"),
    .product(name: "MonetizationTesting", package: "AppMonetizationKit"),
]

let testTargets: [Target] = [
    testTarget("PuzzleStore", dependencies: ["PuzzleStore", telemetryTestingDep]),
    testTarget(
        "SudokuUI",
        dependencies: ["SudokuUI", persistenceDep, gameCenterClientDep, gameCenterTestingDep] + monetizationTestDeps
    ),
    // AppCompositionTests pulls in AdsAdMob so v2.3.7 BootOrderTests can drive
    // `MonetizationBootCoordinator` directly with recording bridges.
    testTarget(
        "AppComposition",
        dependencies: [
            "AppComposition",
            persistenceDep,
            gameCenterClientDep,
            gameCenterTestingDep,
            .product(name: "AdsAdMob", package: "AppMonetizationKit"),
        ] + monetizationTestDeps
    ),
]

// MARK: - ASCRegister CLI (additive tool target; not part of the App binary)
//
// Bootstraps Game Center achievements + leaderboards in App Store Connect
// via the ASC API. Pure Foundation + CryptoKit — no external deps. Lives in
// the SudokuKit package so it can share consistency tests with the
// production GameCenterClient IDs.

let ascRegisterTargets: [Target] = [
    .executableTarget(
        name: "ASCRegister",
        dependencies: [],
        path: "Sources/ASCRegister",
        resources: [.copy("Strings/gc-strings.xcstrings.patch")],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "ASCRegisterTests",
        dependencies: ["ASCRegister"],
        path: "Tests/ASCRegisterTests",
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "SudokuKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "PuzzleStore", targets: ["PuzzleStore"]),
        .library(name: "SudokuUI", targets: ["SudokuUI"]),
        .library(name: "SudokuKitTesting", targets: ["SudokuKitTesting"]),
        .library(name: "AppComposition", targets: ["AppComposition"]),
    ],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", from: "1.17.0"),
        // 2026-05-26 module split: SudokuEngine + GameState extracted into
        // sibling local package so a future Telemetry-only extraction is
        // unblocked. See `docs/foundations.md §2`.
        .package(name: "SudokuCoreKit", path: "../SudokuCoreKit"),
        // 2026-05-26 Stage 2 module split: Telemetry extracted into sibling
        // TelemetryKit package so it can be reused across apps. Telemetry is
        // pure value types + protocol seams, zero Apple framework imports —
        // suitable as a leaf package. See `docs/foundations.md §2`.
        .package(name: "TelemetryKit", path: "../TelemetryKit"),
        // 2026-05-26 Stage 3 module split: Persistence + GameCenterClient
        // extracted into sibling local packages. PersistenceKit hosts the
        // CloudKit Private-DB stack; GameCenterKit hosts the GameKit seam.
        // See `docs/foundations.md §2`.
        .package(name: "PersistenceKit", path: "../PersistenceKit"),
        .package(name: "GameCenterKit", path: "../GameCenterKit"),
        // v2.3.2: sibling local package providing MonetizationCore +
        // AdsAdMob (Google Mobile Ads bridge) + IAPStoreKit2 (StoreKit2 bridge)
        // + MonetizationTesting fakes. Lives one directory up under Packages/.
        .package(name: "AppMonetizationKit", path: "../AppMonetizationKit"),
    ],
    targets: productionTargets + testTargets + ascRegisterTargets,
    swiftLanguageModes: [.v6]
)
