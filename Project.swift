import ProjectDescription

// MARK: - Sudoku App project (Phase 1.4)
//
// Source of truth for `App/Sudoku.xcodeproj`. Regenerate after edits with:
//
//     mise exec aqua:tuist/tuist -- tuist generate
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
    infoPlist: .file(path: "App/Info.plist"),
    sources: ["App/**/*.swift"],
    resources: [
        "App/Assets.xcassets",
        "App/Resources/PrivacyInfo.xcprivacy",
        "App/Resources/Localizable.xcstrings",
        // LicensePlist-generated Settings.bundle (App Store Acknowledgements
        // page). Source of truth: `license_plist.yml`. Regenerated on every
        // Xcode Cloud build via `ci_scripts/ci_post_clone.sh`; not committed
        // (.gitignore'd). Glob pattern so Tuist doesn't require the directory
        // to exist at `tuist generate` time on dev machines.
        .glob(pattern: "App/Resources/Settings.bundle/**")
    ],
    entitlements: .file(path: "App/Sudoku.entitlements"),
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

let project = Project(
    name: "Sudoku",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "ja", "zh-Hans", "es", "th", "ko"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "Packages/SudokuKit"),
        .local(path: "Packages/AppMonetizationKit"),
    ],
    settings: .settings(
        base: swiftSettings,
        configurations: [
            .debug(name: "Debug", xcconfig: "Tuist/Signing.xcconfig"),
            .release(name: "Release", xcconfig: "Tuist/Signing.xcconfig"),
        ]
    ),
    targets: [sudokuTarget],
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
            testAction: .testPlans(["App/Sudoku.xctestplan"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Sudoku",
                options: .options(
                    storeKitConfigurationPath: .relativeToManifest("App/Resources/Sudoku.storekit")
                )
            )
        ),
    ]
)
