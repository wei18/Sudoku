// swift-tools-version: 6.2

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
//   MonetizationUI     → MonetizationCore (+ SwiftUI). Hosts the shared
//                       `MonetizationStateController`, `ToastController` /
//                       `ToastView`, and Settings IAP rows extracted from
//                       SudokuUI in the MS monetization wire Phase 1
//                       (2026-06-02). Theme decoupled via `tintColor: Color`
//                       init params — no Theme protocol dep here.

let productionTargets: [Target] = [
    .target(name: "MonetizationCore", swiftSettings: swiftSettings),
    .target(
        name: "MonetizationUI",
        dependencies: ["MonetizationCore"],
        swiftSettings: swiftSettings
    ),
    .target(
        name: "AdsAdMob",
        dependencies: [
            "MonetizationCore",
            // Both products ship iOS-only xcframeworks (Google does not provide
            // macOS binary slices). Gate the link-time dependency on iOS so
            // macOS builds — which include the AdsAdMob source via the App's
            // `[.iPhone, .iPad, .mac]` destinations — link cleanly. The
            // `#if canImport(GoogleMobileAds)` / `canImport(UserMessagingPlatform)`
            // guards in this target's sources already handle symbol absence.
            // UMP is declared as a direct dep here (rather than picked up
            // transitively from GoogleMobileAds) so we can attach the same
            // `.iOS` platform condition.
            .product(
                name: "GoogleMobileAds",
                package: "swift-package-manager-google-mobile-ads",
                condition: .when(platforms: [.iOS])
            ),
            .product(
                name: "GoogleUserMessagingPlatform",
                package: "swift-package-manager-google-user-messaging-platform",
                condition: .when(platforms: [.iOS])
            ),
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
    .testTarget(
        name: "MonetizationUITests",
        dependencies: ["MonetizationUI", "MonetizationTesting"],
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
        .library(name: "MonetizationUI", targets: ["MonetizationUI"]),
        .library(name: "AdsAdMob", targets: ["AdsAdMob"]),
        .library(name: "IAPStoreKit2", targets: ["IAPStoreKit2"]),
        .library(name: "MonetizationTesting", targets: ["MonetizationTesting"]),
    ],
    dependencies: [
        // foundations.md §9.1: third-party SDK is isolated to AdsAdMob target only.
        // Pinned to 13.x — first major exposing Swift-native API names
        // (`MobileAds.shared`, `ConsentForm`, `ConsentInformation`). v13.0
        // raised the minimum deployment target and removed a swathe of
        // deprecated ObjC-prefixed surface; our `.iOS(.v26)` floor exceeds the
        // v13 min iOS 13 requirement. Bridge seam (`AdMobBridge`) shields the
        // rest of the package from future API churn.
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-mobile-ads",
            from: "13.0.0"
        ),
        // UMP is also pulled in transitively by GoogleMobileAds, but we declare
        // it directly so the AdsAdMob target can attach `.condition(.when(platforms: [.iOS]))`
        // to its product dependency. Without this direct declaration the
        // transitive UMP target still links unconditionally on macOS and the
        // build fails on the missing macOS slice in UserMessagingPlatform.xcframework.
        // UMP 3.0 introduced the Swift-native names matching GoogleMobileAds 13.x.
        .package(
            url: "https://github.com/googleads/swift-package-manager-google-user-messaging-platform.git",
            from: "3.0.0"
        ),
    ],
    targets: productionTargets + testTargets,
    swiftLanguageModes: [.v6]
)
