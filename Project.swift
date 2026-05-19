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
]

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
        "App/Resources/Localizable.xcstrings"
    ],
    entitlements: .file(path: "App/Sudoku.entitlements"),
    dependencies: [
        .package(product: "SudokuUI"),
        .package(product: "AppComposition"),
    ],
    settings: .settings(base: swiftSettings)
)

let project = Project(
    name: "Sudoku",
    options: .options(
        defaultKnownRegions: ["en", "zh-Hant", "ja", "zh-Hans", "es", "th", "ko"],
        developmentRegion: "en"
    ),
    packages: [
        .local(path: "Packages/SudokuKit"),
    ],
    settings: .settings(
        base: swiftSettings,
        configurations: [
            .debug(name: "Debug"),
            .release(name: "Release"),
        ]
    ),
    targets: [sudokuTarget],
    schemes: [
        .scheme(
            name: "Sudoku",
            shared: true,
            buildAction: .buildAction(targets: ["Sudoku"]),
            runAction: .runAction(configuration: "Debug", executable: "Sudoku")
        ),
    ]
)
