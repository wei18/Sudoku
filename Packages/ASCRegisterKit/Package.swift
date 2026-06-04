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
// leaderboard / achievement registration, IAP localization plan/apply,
// app-listing metadata plan/apply).
// Extracted from SudokuKit on 2026-06-03 (issue #254) so tooling deps no
// longer sit in the shipped app library's build graph.
//
// Mostly Foundation + CryptoKit. The single third-party dep is Yams
// (issue #310): the `metadata` subcommand reads the per-locale
// `listing.yaml` + per-app `app-meta.yaml` files, whose `|` block scalars
// (with embedded blank lines) + nested `review_information:` map make a
// hand-rolled reader fiddly + risky. Yams is the de-facto Swift YAML lib
// (SwiftLint / Sourcery), pure-Swift, SwiftPM, macOS-clean. It stays out of
// the shipped App's build graph — ASCRegisterKit is a dev-only leaf package
// with zero arrows into the app graph (ConfigConsistencyTests hard-codes the
// expected Game Center IDs rather than importing GameCenterClient).
//
// Faithful single-target relocation: the issue's aspirational
// ASCRegister / ASCClient / ASCConfig 3-way split is deferred (the sources
// are tightly coupled; splitting buys no build-graph win for a dev tool).

let package = Package(
    name: "ASCRegisterKit",
    platforms: [
        .macOS(.v26),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .executableTarget(
            name: "ASCRegister",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
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
