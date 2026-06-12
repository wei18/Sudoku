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
// App targets: see per-target definitions below for bundle ids. Both
// targets ship iOS 26 + macOS 26.

let swiftSettings: SettingsDictionary = [
    "SWIFT_VERSION": "6.0",
    "SWIFT_STRICT_CONCURRENCY": "complete",
    "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
    "SWIFT_UPCOMING_FEATURE_INTERNAL_IMPORTS_BY_DEFAULT": "YES",
    // Automatic signing. DEVELOPMENT_TEAM is supplied by Tuist/Signing.xcconfig
    // (gitignored — see Tuist/Signing.xcconfig.example for the template).
    "CODE_SIGN_STYLE": "Automatic",
]

// AppIcon: iOS uses `AppIcon.appiconset` (single 1024 universal with Light /
// Dark / Tinted appearances — Apple compositor handles the squircle mask).
// macOS uses a dedicated `AppIcon-macOS.appiconset` with the full 16…1024
// size ladder. Restored 2026-06-02 — Xcode 26 / macOS Sequoia's asset
// catalog editor still requires the explicit per-size ladder for AppKit,
// no Single Size option for macOS. The earlier simplification (PR #225)
// produced the "AppIcon has N unassigned children" warning on macOS even
// after Tinted was added back. Sibling 16/32/…/512 PNGs are downscaled
// from the 1024 master via `sips -Z` per `app-icon-rasterize` skill.
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
    infoPlist: .file(path: "App/Sudoku/Info.plist"),
    sources: ["App/Sudoku/**/*.swift"],
    resources: [
        "App/Sudoku/Assets.xcassets",
        "App/Sudoku/Resources/PrivacyInfo.xcprivacy",
        "App/Sudoku/Resources/Localizable.xcstrings",
        // Localized Info.plist keys (NSUserTrackingUsageDescription — ATT
        // system-dialog string, Path B framing). #371: the Info.plist literal
        // stays as base fallback; this catalog supplies all 7 locales.
        "App/Sudoku/Resources/InfoPlist.xcstrings",
        // #330 P3: zen-wood gameplay audio (SFX + looping BGM). Filename stems
        // match each `soundKey` LiveSoundPlayer resolves from `Bundle.main`
        // (place / complete / error / win SFX + `gameplay` BGM).
        "App/Sudoku/Resources/Audio/**",
        // LicensePlist-generated Settings.bundle (App Store Acknowledgements
        // page). Source of truth: `App/Sudoku/license_plist.yml`. Regenerated
        // on every Xcode Cloud build via `ci_scripts/ci_post_clone.sh`; not
        // committed (.gitignore'd). Glob pattern so Tuist doesn't require the
        // directory to exist at `tuist generate` time on dev machines.
        .glob(pattern: "App/Sudoku/Resources/Settings.bundle/**")
    ],
    entitlements: .file(path: "App/Sudoku/Sudoku.entitlements"),
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
        // #330 P1: explicit App-target link so the GameAudioKit engine is in the
        // bundle. P1 only defines the package; gameplay triggers + composition
        // wiring land in P2.
        .package(product: "GameAudio"),
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
    infoPlist: .file(path: "App/Minesweeper/Info.plist"),
    sources: ["App/Minesweeper/**/*.swift"],
    resources: [
        "App/Minesweeper/Assets.xcassets",
        "App/Minesweeper/Resources/PrivacyInfo.xcprivacy",
        "App/Minesweeper/Resources/Localizable.xcstrings",
        // Localized Info.plist keys (NSUserTrackingUsageDescription — ATT
        // system-dialog string, Path B framing). #371: the Info.plist literal
        // stays as base fallback; this catalog supplies all 7 locales.
        "App/Minesweeper/Resources/InfoPlist.xcstrings",
        // #330 P3: zen-wood gameplay audio (SFX + looping BGM). Filename stems
        // match each `soundKey` LiveSoundPlayer resolves from `Bundle.main`
        // (reveal / flag / floodClear / explosion / win SFX + `bgm` BGM).
        "App/Minesweeper/Resources/Audio/**",
        // LicensePlist-generated Settings.bundle (App Store Acknowledgements
        // page). Source of truth: `App/Minesweeper/license_plist.yml`.
        // Regenerated on every Xcode Cloud build via `ci_scripts/ci_post_clone.sh`;
        // not committed (.gitignore'd). Glob pattern so Tuist doesn't require the
        // directory to exist at `tuist generate` time on dev machines.
        .glob(pattern: "App/Minesweeper/Resources/Settings.bundle/**"),
    ],
    entitlements: .file(path: "App/Minesweeper/Minesweeper.entitlements"),
    dependencies: [
        .package(product: "MinesweeperUI"),
        .package(product: "MinesweeperAppComposition"),
        // #330 P1: explicit App-target link so the GameAudioKit engine is in the
        // bundle. P1 only defines the package; gameplay triggers + composition
        // wiring land in P2.
        .package(product: "GameAudio"),
    ],
    settings: .settings(base: appTargetSettings)
)

// Tiles2048 app target — SDD-004 Milestone 2 skeleton. Mirrors `minesweeperTarget`'s
// shape with per-app values: bundleId `com.wei18.tiles2048`, source/resource paths
// under `Tiles2048/`, entitlements with the separate iCloud container
// `iCloud.com.wei18.tiles2048`. Only depends on the local Game2048Kit products
// today — full monetization and platform wiring (banner / IAP / GC / audio) lands
// in Milestones 3–4.
let tiles2048Target = Target.target(
    name: "Tiles2048",
    destinations: [.iPhone, .iPad, .mac],
    product: .app,
    bundleId: "com.wei18.tiles2048",
    deploymentTargets: .multiplatform(iOS: "26.0", macOS: "26.0"),
    infoPlist: .file(path: "App/Tiles2048/Info.plist"),
    sources: ["App/Tiles2048/**/*.swift"],
    resources: [
        "App/Tiles2048/Assets.xcassets",
        "App/Tiles2048/Resources/PrivacyInfo.xcprivacy",
        "App/Tiles2048/Resources/Localizable.xcstrings",
        // Localized Info.plist keys (NSUserTrackingUsageDescription — ATT
        // system-dialog string, Path B framing). Info.plist literal stays as
        // base fallback; this catalog supplies all 7 locales (mirrors #371).
        "App/Tiles2048/Resources/InfoPlist.xcstrings",
        // M3/M4: add Audio/** when zen-wood (or 2048-appropriate) assets land.
        // LicensePlist-generated Settings.bundle (App Store Acknowledgements
        // page). Source of truth: `App/Tiles2048/license_plist.yml`.
        // Regenerated on every Xcode Cloud build via `ci_scripts/ci_post_clone.sh`;
        // not committed (.gitignore'd). Glob pattern so Tuist doesn't require the
        // directory to exist at `tuist generate` time on dev machines.
        .glob(pattern: "App/Tiles2048/Resources/Settings.bundle/**"),
    ],
    entitlements: .file(path: "App/Tiles2048/Tiles2048.entitlements"),
    dependencies: [
        .package(product: "Game2048UI"),
        .package(product: "Game2048AppComposition"),
        // M3/M4: add explicit App-target links for GameAudio, MonetizationCore,
        // AdsAdMob, IAPStoreKit2 so the xcframework slices embed correctly
        // (mirrors the explicit dep pattern from sudokuTarget / minesweeperTarget).
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
        .local(path: "Packages/GameShellKit"),
        .local(path: "Packages/GameAudioKit"),
        // SDD-004: Tiles2048 UI + composition shell.
        .local(path: "Packages/Game2048Kit"),
        // macOS-only ASC API dev CLI (issue #254). Surfaced here so it's
        // discoverable in the generated workspace; no app target depends on
        // it (it's tooling, not part of either app binary).
        .local(path: "Packages/ASCRegisterKit"),
    ],
    // Per-config xcconfigs. Each wrapper `#include?`s two gitignored leaf
    // xcconfigs:
    //   - Tuist/Signing.xcconfig — DEVELOPMENT_TEAM (XCC: $CI_TEAM_ID).
    //   - Tuist/AdMob.xcconfig — ADMOB_APP_ID + ADMOB_BANNER_UNIT_ID
    //     (XCC: per-app env vars, see ci_post_clone.sh).
    // The wrappers are committed (no secrets); their templates live at
    // Tuist/Signing.xcconfig.example + Tuist/AdMob.xcconfig.example.
    settings: .settings(
        base: swiftSettings,
        configurations: [
            .debug(name: "Debug", xcconfig: "Tuist/Config-Debug.xcconfig"),
            .release(name: "Release", xcconfig: "Tuist/Config-Release.xcconfig"),
        ]
    ),
    targets: [sudokuTarget, minesweeperTarget, tiles2048Target],
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
            testAction: .testPlans(["App/Sudoku/Sudoku.xctestplan"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Sudoku",
                options: .options(
                    storeKitConfigurationPath: .relativeToManifest("App/Sudoku/Resources/Sudoku.storekit")
                )
            )
        ),
        .scheme(
            name: "Minesweeper",
            shared: true,
            buildAction: .buildAction(targets: ["Minesweeper"]),
            testAction: .testPlans(["App/Minesweeper/Minesweeper.xctestplan"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Minesweeper",
                options: .options(
                    storeKitConfigurationPath: .relativeToManifest("App/Minesweeper/Resources/Minesweeper.storekit")
                )
            )
        ),
        // SDD-004 Milestone 2: Tiles2048 scheme. No .xctestplan yet (M3/M4 adds
        // the Game2048UITests snapshot suite + AppCompositionTests shape-coverage).
        // No StoreKit config yet (M3/M4 wires the IAP product catalog).
        .scheme(
            name: "Tiles2048",
            shared: true,
            buildAction: .buildAction(targets: ["Tiles2048"]),
            runAction: .runAction(
                configuration: "Debug",
                executable: "Tiles2048"
            )
        ),
    ]
)
