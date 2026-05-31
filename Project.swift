import ProjectDescription

// MARK: - Game project (multi-target umbrella)
//
// Source of truth for `Game.xcodeproj` (generated at repo root). Regenerate
// after edits with:
//
//     mise exec aqua:tuist/tuist -- tuist generate
//
// The project name is `Game` so a future second app (Minesweeper — see
// `meetings/2026-05-31_minesweeper-rfc.md`) can join as a sibling target
// under the same umbrella rather than guest in a project named after Sudoku.
//
// foundations.md §1: Swift 6 language mode + complete concurrency checking.
// foundations.md §2: App target is thin — depends on the local SwiftPM package
// `Packages/SudokuKit` (entry product: `SudokuUI`). Real code lives in the package.
// plan.md §1.4: bundle id `com.wei18.sudoku`, iOS 26 + macOS 26.

let swiftSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
    "SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT": "YES",
    // Automatic signing. DEVELOPMENT_TEAM is supplied by Tuist/Signing.xcconfig
    // (gitignored — see Tuist/Signing.xcconfig.example for the template).
    "CODE_SIGN_STYLE": "Automatic",
]

// Per-platform AppIcon: iOS uses `AppIcon.appiconset` (single 1024 universal
// with light / dark / tinted appearances), macOS uses a dedicated
// `AppIcon-macOS.appiconset` with the full 16…1024 size ladder. Without the
// SDK-scoped override, Xcode 26 emits the "AppIcon has N unassigned children"
// archive warning because `idiom: universal` entries don't satisfy the macOS
// AppKit icon ladder requirement.
let appTargetSettings: SettingsDictionary = swiftSettings.merging([
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
    "ASSETCATALOG_COMPILER_APPICON_NAME[sdk=macosx*]": "AppIcon-macOS",
]) { _, new in new }

let sudokuTarget = Target.target(
    name: "Sudoku",
    destinations: [.iPhone, .iPad, .mac],
    product: .app,
    bundleId: "com.wei18.sudoku",
    deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
    infoPlist: .file(path: "Sudoku/Info.plist"),
    sources: ["Sudoku/**/*.swift"],
    resources: [
        "Sudoku/Assets.xcassets",
        "Sudoku/Resources/PrivacyInfo.xcprivacy",
        "Sudoku/Resources/Localizable.xcstrings",
        // LicensePlist-generated Settings.bundle (App Store Acknowledgements
        // page). Source of truth: `license_plist.yml`. Regenerated on every
        // Xcode Cloud build via `ci_scripts/ci_post_clone.sh`; not committed
        // (.gitignore'd). Glob pattern so Tuist doesn't require the directory
        // to exist at `tuist generate` time on dev machines.
        .glob(pattern: "Sudoku/Resources/Settings.bundle/**")
    ],
    entitlements: .file(path: "Sudoku/Sudoku.entitlements"),
    dependencies: [
        .package(product: "SudokuUI"),
        .package(product: "AppComposition"),
        // v2.3.2: explicit App-target links so Google Mobile Ads + StoreKit2
        // bridge binaries are embedded in the .app bundle. AppComposition
        // already pulls these transitively, but Tuist surfaces them at the
        // App target so the linker discovers the .xcframework slices.
        .package(product: "MonetizationCore"),
        .package(product: "AdsAdMob"),
        .package(product: "IAPStoreKit2"),
    ],
    settings: .settings(base: appTargetSettings)
)

// Minesweeper app target — PR D skeleton. Mirrors `sudokuTarget`'s shape with
// per-app values: bundleId `com.wei18.minesweeper`, source/resource paths
// under `Minesweeper/`, entitlements with the separate iCloud container
// `iCloud.com.wei18.minesweeper`. Only depends on the local MinesweeperKit
// products today — monetization wiring (banner / IAP) lands in follow-up.
let minesweeperTarget = Target.target(
    name: "Minesweeper",
    destinations: [.iPhone, .iPad, .mac],
    product: .app,
    bundleId: "com.wei18.minesweeper",
    deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
    infoPlist: .file(path: "Minesweeper/Info.plist"),
    sources: ["Minesweeper/**/*.swift"],
    resources: [
        "Minesweeper/Assets.xcassets",
        "Minesweeper/Resources/PrivacyInfo.xcprivacy",
        "Minesweeper/Resources/Localizable.xcstrings",
    ],
    entitlements: .file(path: "Minesweeper/Minesweeper.entitlements"),
    dependencies: [
        .package(product: "MinesweeperUI"),
        .package(product: "MinesweeperAppComposition"),
    ],
    settings: .settings(base: appTargetSettings)
)

let project = Project(
    name: "Game",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "ja", "zh-Hans", "es", "th", "ko"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "Packages/SudokuKit"),
        .local(path: "Packages/AppMonetizationKit"),
        .local(path: "Packages/MinesweeperKit"),
    ],
    settings: .settings(
        base: swiftSettings,
        configurations: [
            .debug(name: "Debug", xcconfig: "Tuist/Signing.xcconfig"),
            .release(name: "Release", xcconfig: "Tuist/Signing.xcconfig"),
        ]
    ),
    targets: [sudokuTarget, minesweeperTarget],
    schemes: [
        .scheme(
            name: "Sudoku",
            shared: true,
            buildAction: .buildAction(targets: ["Sudoku"]),
            // Wire all SPM-package test targets via an .xctestplan file
            // (Tuist 4.194's TargetReference is string-only and cannot
            // qualify targets across SPM package projects; the xctestplan
            // JSON references them via `containerPath: container:Packages/<pkg>`
            // which xcodebuild resolves through the workspace). See issue #184.
            testAction: .testPlans(["Sudoku/Sudoku.xctestplan"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Sudoku",
                options: .options(
                    storeKitConfigurationPath: .relativeToManifest("Sudoku/Resources/Sudoku.storekit")
                )
            )
        ),
        .scheme(
            name: "Minesweeper",
            shared: true,
            buildAction: .buildAction(targets: ["Minesweeper"]),
            testAction: .testPlans(["Minesweeper/Minesweeper.xctestplan"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Minesweeper"
            )
        ),
    ]
)
