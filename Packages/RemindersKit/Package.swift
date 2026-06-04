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
// RemindersKit is a leaf sibling local package: the shared local-notification
// reminder mechanism consumed by both Sudoku and Minesweeper (see
// meetings/2026-06-03_notification-reminders-proposal.md §4 — shared-target
// design; GitHub #287).
//
// Game-agnostic by construction: the scheduling / permission machinery is 100%
// generic, and the only app-specific bits (copy + which reminder kinds are
// enabled) are injected as value types. Mirrors the GameShellKit /
// reusable-targets-over-duplication discipline.
//
// Restricted-import rule (swiftpm-modularization): `UserNotifications` is
// imported ONLY in the `Reminders/Live` files (`LiveNotificationAuthorizer`,
// `LiveReminderScheduler`). UI / logic layers see only the protocol seams —
// same discipline as CloudKit→Persistence, GoogleMobileAds→AdsAdMob.
//
// Dep direction: RemindersKit is a leaf — no in-house deps. The host
// composition root injects a telemetry callback (proposal §4.6); `Reminders`
// does NOT import `Telemetry`.

let package = Package(
    name: "RemindersKit",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
    ],
    products: [
        .library(name: "Reminders", targets: ["Reminders"]),
        .library(name: "RemindersTesting", targets: ["RemindersTesting"]),
    ],
    targets: [
        .target(
            name: "Reminders",
            swiftSettings: swiftSettings
        ),
        // RemindersTesting — shared fakes (FakeReminderScheduler +
        // FakeNotificationAuthorizing). Records calls + scriptable status so any
        // consumer (RemindersTests + app composition tests) can assert call shape
        // without touching the system notification center.
        .target(
            name: "RemindersTesting",
            dependencies: [
                "Reminders",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "RemindersTests",
            dependencies: [
                "Reminders",
                "RemindersTesting",
            ],
            swiftSettings: swiftSettings
        ),
    ],
    swiftLanguageModes: [.v6]
)
