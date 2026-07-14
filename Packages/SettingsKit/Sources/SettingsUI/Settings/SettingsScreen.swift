// SettingsScreen — the shared Settings page BODY (#421).
//
// Extracted from SudokuUI.SettingsView + MinesweeperUI.SettingsView, whose
// `body` assembled the SAME shared GameShellUI blocks in the SAME order inside
// `SettingsShellView(title: "Settings")`:
//   1. Purchases    — injected `purchases` slot (the app's MonetizationUI rows)
//   2. Reminders    — `ReminderSettingsSection` (when `reminderSettings != nil`)
//   3. About        — `SettingsAboutVersionRow` + injected `aboutExtraRows` slot
//   4. Notices      — `SettingsNoticesSection` (when `notices != nil`)
//   5. Storage      — `SettingsStorageSection(clearCache:)`
//
// This is the shared *assembly*; each app keeps its OWN `SettingsView` wrapper
// that builds the config + slots and supplies the host-specific `.task`
// side-effects (Sudoku's ViewModel bootstrap, the monetization controller
// bootstrap). Everything app-divergent is INJECTED:
//   - `purchases` (@ViewBuilder) — the app's MonetizationUI Purchases rows.
//     GameShellUI must NOT import MonetizationUI; this stays a view slot so the
//     shell never gains an IAP / GameCenter / AdMob dependency (mirrors #418's
//     leaderboard-as-value-type decoupling).
//   - `aboutExtraRows` (@ViewBuilder, default EmptyView) — Sudoku injects its
//     Sudoku-only "Generator" row here; Minesweeper injects nothing.
//   - `banner` (@ViewBuilder, default EmptyView) — the app-injected
//     `BannerSlotView` (Epic 5). SettingsKit must NOT import MonetizationUI /
//     AppMonetizationKit; the actual slot is injected at the RouteFactory level.
//   - `version`, `reminderSettings`, `notices`, `clearCache`, `tint` — injected
//     config exactly as the prior wrappers passed them.
//
// Section titles ("Purchases" / "About" / …) stay `LocalizedStringKey` literals
// resolved from each host app's own `Localizable.xcstrings` (Bundle.main),
// byte-identical to the prior wrappers — no catalog change.

public import SwiftUI
// #744: `TelemetryEvent` appears in this type's public `telemetryEmit` init
// param — mirrors `ReminderPrimerCoordinator`'s decoupled `emit` closure
// (SettingsKit already depends on TelemetryKit for that type).
public import Telemetry

public struct SettingsScreen<Purchases: View, AboutExtraRows: View, Banner: View>: View {
    private let purchases: () -> Purchases
    private let reminderSettings: SettingsScreenReminderConfig?
    private let audioSettings: AudioSettingsModel?
    private let version: String
    private let aboutExtraRows: () -> AboutExtraRows
    private let notices: SettingsNoticesConfig?
    private let clearCache: @MainActor () async -> Void
    private let tint: Color
    private let banner: () -> Banner
    // Game Center entry point: when non-nil the shared `Section("Game Center")`
    // row is rendered. The action is injected per-app so SettingsKit never
    // imports GameKit. Every game passes `{ GameCenterDashboard.present() }`
    // (the shared dashboard from GameCenterClient, #560).
    // `nil` (default) keeps previews / tests byte-identical.
    private let onGameCenter: (@MainActor () -> Void)?
    // #744: this app's numeric App Store Connect id, resolved ONCE by the
    // composition root from `Bundle.main` (mirrors the `version` param's
    // `CFBundleShortVersionString` read) and injected here so SettingsKit
    // never touches Bundle.main itself (test-host flakiness — see
    // `AppStoreLinks`'s header comment). `nil`/invalid hides the Share App /
    // Write a Review rows entirely (not disabled) — same "absent, not
    // disabled" language as the Game Center invite-friends row below.
    private let appStoreID: String?
    // #744: Game Center "Invite Friends" entry point. Mirrors `onGameCenter`'s
    // per-app-injected-closure shape so SettingsKit never imports GameKit.
    // The row additionally requires `#available(iOS 26.0, macOS 26.0, *)` —
    // ABSENT (not disabled) below that floor, per the issue's owner decision
    // against a weak "opens the dashboard instead" fallback.
    private let presentInviteFriends: (@MainActor () -> Void)?
    // #744: decoupled telemetry emit for the three new rows below — the host
    // bridges this to `Telemetry.observe`, mirroring
    // `ReminderPrimerCoordinator.emit`. No-op default keeps previews / tests
    // side-effect-free.
    private let telemetryEmit: @Sendable (TelemetryEvent) -> Void
    @Environment(\.openURL) private var openURL

    public init(
        version: String,
        tint: Color,
        clearCache: @escaping @MainActor () async -> Void,
        reminderSettings: SettingsScreenReminderConfig? = nil,
        audioSettings: AudioSettingsModel? = nil,
        notices: SettingsNoticesConfig? = nil,
        onGameCenter: (@MainActor () -> Void)? = nil,
        appStoreID: String? = nil,
        presentInviteFriends: (@MainActor () -> Void)? = nil,
        telemetryEmit: @escaping @Sendable (TelemetryEvent) -> Void = { _ in },
        @ViewBuilder purchases: @escaping () -> Purchases,
        @ViewBuilder aboutExtraRows: @escaping () -> AboutExtraRows = { EmptyView() },
        @ViewBuilder banner: @escaping () -> Banner = { EmptyView() }
    ) {
        self.version = version
        self.tint = tint
        self.clearCache = clearCache
        self.reminderSettings = reminderSettings
        self.audioSettings = audioSettings
        self.notices = notices
        self.onGameCenter = onGameCenter
        self.appStoreID = appStoreID
        self.presentInviteFriends = presentInviteFriends
        self.telemetryEmit = telemetryEmit
        self.purchases = purchases
        self.aboutExtraRows = aboutExtraRows
        self.banner = banner
    }

    public var body: some View {
        SettingsShellView(title: "Settings", sections: {
            // 1. Purchases — injected MonetizationUI rows. The slot is the whole
            // `Section("Purchases") { ... }` (or EmptyView when no controller),
            // built by the host, so the conditional + the IAP coupling stay in
            // the app and out of GameShellUI.
            purchases()

            // 1b. Game Center — shared section; action injected per-app so
            // SettingsKit never imports GameKit. Omitted when `onGameCenter`
            // is nil (previews / tests).
            if let onGameCenter {
                Section("Game Center") {
                    Button(action: onGameCenter) {
                        Label("Game Center", systemImage: "trophy")
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.gameCenter")

                    // #744: invite-friends row — ABSENT (not disabled) below
                    // iOS 26 / macOS 26, and when the host never injected a
                    // presenter (previews / tests / an OS below the floor at
                    // the composition root).
                    if #available(iOS 26.0, macOS 26.0, *), let presentInviteFriends {
                        Button {
                            telemetryEmit(.inviteFriendsTapped)
                            presentInviteFriends()
                        } label: {
                            Label("Invite Friends", systemImage: "person.badge.plus")
                                .foregroundStyle(tint)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("settings.inviteFriends")
                    }
                }
            }

            // 2. Reminders — shared section (enable / prime permission / fire
            // time). Same building block both apps mount; injected copy.
            if let reminderSettings {
                ReminderSettingsSection(
                    model: reminderSettings.model,
                    tintColor: tint,
                    copy: reminderSettings.copy,
                    primerCopy: reminderSettings.primerCopy,
                    deniedCopy: reminderSettings.deniedCopy
                )
            }

            // 2b. Sound — shared audio section (mute / volumes / BGM / haptics).
            // Same building block both apps mount; rendered only when an audio
            // model is injected (#330 P1; nil keeps existing call sites compiling).
            if let audioSettings {
                AudioSettingsSection(model: audioSettings, tintColor: tint)
            }

            // 3. About — shared Version row + injected extra rows. Sudoku passes
            // its Sudoku-only "Generator" row via `aboutExtraRows`; MS passes
            // nothing (EmptyView default), so its About section holds only the
            // version row — byte-identical to before.
            Section("About") {
                SettingsAboutVersionRow(version: version, tintColor: tint)
                aboutExtraRows()

                // #744: Share App + Write a Review — About-adjacent, right
                // after the version row. Both hidden (not disabled) when
                // `appStoreID` is missing/unresolved — a disabled row with no
                // working destination offers no useful affordance, and this
                // mirrors the invite-friends row's "absent" language above.
                if let shareURL = AppStoreLinks.shareURL(appStoreID: appStoreID) {
                    ShareLink(item: shareURL) {
                        Label("Share App", systemImage: "square.and.arrow.up")
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    // `ShareLink` has no completion callback for "the share
                    // sheet was invoked" (only the system share sheet itself
                    // reports item-level completion, which SwiftUI doesn't
                    // surface) — a simultaneous tap gesture is the standard
                    // pattern for observing a ShareLink tap without
                    // interfering with its own gesture recognition.
                    .simultaneousGesture(TapGesture().onEnded {
                        telemetryEmit(.shareAppTapped)
                    })
                    .accessibilityIdentifier("settings.shareApp")
                }
                if let reviewURL = AppStoreLinks.reviewURL(appStoreID: appStoreID) {
                    Button {
                        telemetryEmit(.writeReviewTapped)
                        openURL(reviewURL)
                    } label: {
                        Label("Write a Review", systemImage: "star")
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.writeReview")
                }
            }

            // 4. Notices — shared section; URLs + copyright injected via config.
            if let notices {
                SettingsNoticesSection(tintColor: tint, config: notices)
            }

            // 5. Storage — shared section. Wires the host-supplied clearCache.
            SettingsStorageSection(clearCache: clearCache)
        }, banner: banner)
    }
}

// MARK: - Reminder config

/// Bundle of the shared `ReminderSettingsModel` + the host-localized copy the
/// `ReminderSettingsSection` needs. Unifies the previously-duplicated
/// `SudokuUI.ReminderSettingsEntry` / `MinesweeperUI.MinesweeperReminderSettingsEntry`
/// (identical field-for-field) into one shell-owned value. Built at each app's
/// composition root so all reminder wiring stays there; the screen receives a
/// ready-to-mount value. Not `Sendable` — carries `LocalizedStringKey` copy
/// built + consumed on `@MainActor`.
public struct SettingsScreenReminderConfig {
    public let model: ReminderSettingsModel
    public let copy: ReminderSettingsCopy
    public let primerCopy: ReminderPrimerCopy
    public let deniedCopy: ReminderDeniedCopy

    public init(
        model: ReminderSettingsModel,
        copy: ReminderSettingsCopy,
        primerCopy: ReminderPrimerCopy,
        deniedCopy: ReminderDeniedCopy
    ) {
        self.model = model
        self.copy = copy
        self.primerCopy = primerCopy
        self.deniedCopy = deniedCopy
    }
}
