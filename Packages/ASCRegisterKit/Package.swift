// swift-tools-version: 6.2

import PackageDescription

// MARK: - Shared settings (foundations.md §1: Swift 6 + complete concurrency)

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

// MARK: - ASCRegisterKit
//
// macOS-only developer CLI for App Store Connect API ops (Game Center
// leaderboard / achievement registration, IAP localization plan/apply).
// Extracted from SudokuKit on 2026-06-03 (issue #254) so tooling deps no
// longer sit in the shipped app library's build graph.
//
// Pure Foundation + CryptoKit — no external deps, no SudokuKit library
// product dependency (ConfigConsistencyTests deliberately hard-codes the
// expected Game Center IDs rather than importing GameCenterClient, to keep
// this package a leaf with zero arrows into the app graph).
//
// Faithful single-target relocation: the issue's aspirational
// ASCRegister / ASCClient / ASCConfig 3-way split is deferred (the sources
// are tightly coupled; splitting buys no build-graph win for a dev tool).

let package = Package(
    name: "ASCRegisterKit",
    platforms: [
        .macOS(.v26),
    ],
    targets: [
        .executableTarget(
            name: "ASCRegister",
            dependencies: [],
            path: "Sources/ASCRegister",
            resources: [
                .copy("Strings/gc-strings.xcstrings.patch"),
                .copy("Strings/iap-strings.xcstrings.patch"),
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "ASCRegisterTests",
            dependencies: ["ASCRegister"],
            path: "Tests/ASCRegisterTests",
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
