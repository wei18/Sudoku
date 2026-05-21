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
// Dep direction (design.md §How.1):
//   MonetizationCore   ← zero external dep
//   AdsAdMob           → MonetizationCore (+ GoogleMobileAds, added in v2.2)
//   IAPStoreKit2       → MonetizationCore (+ StoreKit, Apple framework)
//   MonetizationTesting → MonetizationCore

let productionTargets: [Target] = [
    .target(name: "MonetizationCore", swiftSettings: swiftSettings),
    .target(
        name: "AdsAdMob",
        dependencies: [
            "MonetizationCore",
            .product(name: "GoogleMobileAds", package: "swift-package-manager-google-mobile-ads"),
        ],
        swiftSettings: swiftSettings
    ),
    .target(name: "IAPStoreKit2", dependencies: ["MonetizationCore"], swiftSettings: swiftSettings),
    .target(name: "MonetizationTesting", dependencies: ["MonetizationCore"], swiftSettings: swiftSettings),
]

// MARK: - Test targets

let testTargets: [Target] = [
    .testTarget(
        name: "MonetizationCoreTests",
        dependencies: ["MonetizationCore", "MonetizationTesting"],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "AdsAdMobTests",
        dependencies: ["AdsAdMob", "MonetizationTesting"],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "IAPStoreKit2Tests",
        dependencies: ["IAPStoreKit2", "MonetizationTesting"],
        swiftSettings: swiftSettings
    ),
    .testTarget(
        name: "MonetizationTestingTests",
        dependencies: ["MonetizationTesting"],
        swiftSettings: swiftSettings
    ),
]

// MARK: - Package

let package = Package(
    name: "AppMonetizationKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "MonetizationCore", targets: ["MonetizationCore"]),
        .library(name: "AdsAdMob", targets: ["AdsAdMob"]),
        .library(name: "IAPStoreKit2", targets: ["IAPStoreKit2"]),
        .library(name: "MonetizationTesting", targets: ["MonetizationTesting"]),
    ],
    dependencies: [
        // foundations.md §9.1: third-party SDK is isolated to AdsAdMob target only.
        // Pinned to 11.x — first major aligned with Swift 6 toolchain era. Allow
        // semver-major drift via `from:`; bridge seam (AdMobBridge) shields the
        // rest of the package from API churn.
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads",
            from: "11.0.0"
        ),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)

// swiftlint:enable trailing_comma
