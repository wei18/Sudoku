// SettingsView — Minesweeper Settings.
//
// Wraps `SettingsUI.SettingsScreen` to inherit the shared grouped-Form
// chrome (PR X4).
//
// MS monetization wire Phase 3 (2026-06-03): mounts the shared
// `RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow` from
// `MonetizationUI` (PR #249) under a `Section("Purchases")`. The host
// passes a `MonetizationStateController` constructed against the MS ASC
// productId. Tint is `theme.accent.primary.resolved` (#688 item 5a — was
// `.accentColor`; MinesweeperTheme has shipped real accent tokens since
// #278 Phase 2, so the "no theme tokens yet" premise was stale).
//
// #277: drops the "Coming soon" stub. About(Version) + Storage(Clear cache)
// now reuse the shared `GameShellUI.SettingsAboutVersionRow` /
// `SettingsStorageSection` — the same building blocks Sudoku adopts. The host
// (LiveRouteFactory) supplies the version string (Bundle.main) and an async
// clear-cache closure wired to MS persistence via `PersistenceProtocol`.
// Clear-cache is parity-only until MS save-flow lands (latestInProgress()
// returns nil today), but it IS wired to the real protocol method, not a
// fake button. Tint is `theme.accent.primary.resolved` (#688 item 5a).
//
// #572: `MinesweeperReminderSettingsEntry` deleted; `SettingsView` now uses
// the shared `ReminderSettingsEntry` from SettingsUI (same fields, same behavior).

public import SwiftUI
// #688 item 5a: `@Environment(\.theme)` (the Theme env key), private-only use.
internal import GameShellUI
public import MonetizationUI
// refactor/settingskit-target (2026-06-09): `SettingsScreen` /
// `SettingsNoticesConfig` + the reminders UI types moved out of GameShellUI into
// SettingsUI. `public` because `SettingsNoticesConfig` + copy types appear in
// public signatures.
public import SettingsUI
// #560: shared `GameCenterDashboard.present()` (was the per-app copy).
internal import GameCenterClient
// #744: `TelemetryEvent` appears in this type's public `telemetryEmit` init
// param (mirrors `SettingsScreen`'s decoupled emit closure).
public import Telemetry

public struct SettingsView<Banner: View>: View {
    private let version: String
    private let clearCache: @MainActor () async -> Void
    private let monetizationController: MonetizationStateController?
    // #331: shared Notices section inputs, app-injected by the host. Defaulted
    // nil so previews / tests keep the byte-identical screen.
    private let notices: SettingsNoticesConfig?
    // #287 / #572: shared Reminders entry (enable / prime permission / fire-time).
    // Migrated from `MinesweeperReminderSettingsEntry` to the shared
    // `ReminderSettingsEntry` (SettingsUI). Same fields — byte-identical screen.
    // Defaulted nil so previews / tests mount a byte-identical screen without the
    // section; the host (LiveRouteFactory) injects one wired to RemindersKit Live.
    private let reminderSettings: ReminderSettingsEntry?
    // #330 P2: shared Sound section model (mute / volumes / BGM / haptics).
    // Defaulted nil so previews / tests keep the byte-identical screen without the
    // section; the host (LiveRouteFactory) injects the live-player-backed model.
    private let audioSettings: AudioSettingsModel?
    // Epic 5: optional banner slot below the Form. SettingsKit / GameShellUI
    // must NOT import MonetizationUI; the actual BannerSlotView is injected by
    // LiveRouteFactory. EmptyView default keeps previews/tests inert.
    private let banner: Banner
    // #685: the Game Center row previously called `GameCenterDashboard.present()`
    // directly with no signed-out guard — a silent no-op when unauthenticated.
    // Injected so the live wiring can route through
    // `GameRootViewModel.presentGameCenterOrAlert`, matching the Home
    // leaderboard card's fallback. `nil` (default) preserves the old
    // ungated behavior for previews / tests that don't wire a root VM.
    private let presentGameCenter: (@MainActor () -> Void)?
    // #744: this app's numeric App Store Connect id, resolved from Bundle.main
    // at the composition root (LiveRouteFactory, mirroring the `version`
    // read) and forwarded to `SettingsScreen`, which hides Share App / Write
    // a Review when nil/unresolved. `nil` default preserves the byte-identical
    // screen for previews / tests.
    private let appStoreID: String?
    // #744: Game Center "Invite Friends" entry point, mirrors `presentGameCenter`'s
    // shape. `nil` default (previews / tests) keeps the row absent.
    private let presentInviteFriends: (@MainActor () -> Void)?
    // #744: decoupled telemetry emit, forwarded to `SettingsScreen`. No-op
    // default keeps previews / tests side-effect-free.
    private let telemetryEmit: @Sendable (TelemetryEvent) -> Void

    // #688 item 5a: read only here (row inits still take a resolved
    // `tintColor:`/`tint:` Color param, mirroring Sudoku's SettingsView).
    @Environment(\.theme) private var theme

    /// #714: resolves the Game Center row's tap action, asserting in
    /// debug/test if `presentGameCenter` was never injected — the exact
    /// pre-#685 bug shape (unguarded `GameCenterDashboard.present()`), so a
    /// future Live.swift refactor that drops the injection fails CI instead
    /// of silently regressing. Mirrors `GameHomeViewModel.select`'s
    /// `presentLeaderboard` assert (and Sudoku's `SettingsView` twin).
    /// `internal` (not `private`) so `MinesweeperSettingsViewTests` can
    /// invoke it directly and prove the injected closure — not the
    /// fallback — actually fires.
    @MainActor
    func resolvedOnGameCenter() {
        assert(
            presentGameCenter != nil,
            "presentGameCenter not wired — Settings Game Center row falls back to the unguarded pre-#685 GameCenterDashboard.present()"
        )
        (presentGameCenter ?? { GameCenterDashboard.present() })()
    }

    public init(
        version: String = "1.0.0",
        clearCache: @escaping @MainActor () async -> Void = {},
        monetizationController: MonetizationStateController? = nil,
        notices: SettingsNoticesConfig? = nil,
        reminderSettings: ReminderSettingsEntry? = nil,
        audioSettings: AudioSettingsModel? = nil,
        presentGameCenter: (@MainActor () -> Void)? = nil,
        appStoreID: String? = nil,
        presentInviteFriends: (@MainActor () -> Void)? = nil,
        telemetryEmit: @escaping @Sendable (TelemetryEvent) -> Void = { _ in },
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.version = version
        self.clearCache = clearCache
        self.monetizationController = monetizationController
        self.notices = notices
        self.reminderSettings = reminderSettings
        self.audioSettings = audioSettings
        self.presentGameCenter = presentGameCenter
        self.appStoreID = appStoreID
        self.presentInviteFriends = presentInviteFriends
        self.telemetryEmit = telemetryEmit
        self.banner = banner()
    }

    public var body: some View {
        // #421: the shared assembly (shell + 5 sections in order) now lives in
        // `GameShellUI.SettingsScreen`. MS supplies its config + the Purchases
        // slot, injects NO About extra rows (no generator), and tints with
        // `theme.accent.primary.resolved` (#688 item 5a — mirrors Sudoku's
        // SettingsView; was `.accentColor`).
        SettingsScreen(
            version: version,
            tint: theme.accent.primary.resolved,
            clearCache: clearCache,
            reminderSettings: reminderSettings.map {
                // #287: same building block Sudoku mounts; map the entry into
                // the shell's config. After #572 this is a direct pass-through
                // since ReminderSettingsEntry == SettingsScreenReminderConfig fields.
                SettingsScreenReminderConfig(
                    model: $0.model,
                    copy: $0.copy,
                    primerCopy: $0.primerCopy,
                    deniedCopy: $0.deniedCopy
                )
            },
            audioSettings: audioSettings,
            notices: notices,
            // Game Center entry: present Apple's native GC dashboard (no leaderboard
            // focus). #560: shared `GameCenterDashboard` in GameCenterClient. #685:
            // signed-out taps now raise the same alert as the Home leaderboard card
            // instead of silently no-op'ing.
            onGameCenter: resolvedOnGameCenter,
            // #744: `presentInviteFriends` is forwarded straight through — the
            // composition root already wraps it in the same
            // `presentGameCenterOrAlert` signed-out guard `presentGameCenter`
            // uses before injecting it (see MinesweeperAppComposition.Live's
            // `makeRouteFactory`).
            appStoreID: appStoreID,
            presentInviteFriends: presentInviteFriends,
            telemetryEmit: telemetryEmit,
            purchases: {
                // Purchases slot — the app's MonetizationUI rows. GameShellUI never
                // imports MonetizationUI; the whole conditional Section lives here.
                if let controller = monetizationController {
                    Section("Purchases") {
                        if controller.hasPurchasedRemoveAds {
                            AdsRemovedRow(tintColor: theme.accent.primary.resolved)
                        } else {
                            RemoveAdsRow(
                                controller: controller,
                                tintColor: theme.accent.primary.resolved
                            )
                        }
                        RestorePurchasesRow(
                            controller: controller,
                            tintColor: theme.accent.primary.resolved
                        )
                    }
                }
            },
            banner: {
                // Epic 5: banner injected by LiveRouteFactory; EmptyView in previews/tests.
                self.banner
            }
        )
        // No `aboutExtraRows` — MS has no generator row (EmptyView default).
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
