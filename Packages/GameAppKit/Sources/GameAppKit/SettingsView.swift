// SettingsView — native Form with Account / Statistics / Storage / About.
//
// #832: unified from `SudokuUI.SettingsView` + `MinesweeperUI.SettingsView`,
// which had structurally diverged (Sudoku was `SettingsViewModel`-driven with
// a `.task { await viewModel.bootstrap() }`; Minesweeper took primitive
// `version:`/`clearCache:` params with no view model or bootstrap). This is
// the richer (Sudoku) shape, parameterized by `generatorVersionLabel` on
// `SettingsViewModel` for the one genuinely Sudoku-only row — Minesweeper now
// gains the same bootstrap/clear-cache seam it had drifted away from (its
// `latestInProgress()` already returns `nil` today per #455 parity notes, so
// this is a behavior no-op for MS until its save-flow lands, matching prior
// documented behavior exactly).
//
// Lives in GameAppKit (not SettingsKit/SettingsUI) because it needs
// `MonetizationUI` (Purchases rows) + `GameCenterClient` (dashboard fallback)
// + `Persistence`/`Telemetry` (the view model) — SettingsUI is deliberately
// near-zero-dep (must NOT import MonetizationUI/GameCenter, per its
// Package.swift header) and stays the shared *assembly* (`SettingsScreen`)
// this wrapper configures.
//
// Per docs/designs/08-settings.md. No branding; HIG default Form chrome.
//
// v2.3.6: a new "Remove Ads" Section hosts two rows (Remove Ads CTA hidden
// once purchased; Restore Purchases always visible). Both rows flip to a
// `ProgressView` while the underlying async call is in flight.
//
// v2.4.6: purchase/restore success/failure and clear-cache confirmation
// surface via `ToastController` (bottom-center capsule, mounted on
// `RootView`) instead of orphan `Label` rows in the Form. `latestMessage`
// on the controller stays as the VoiceOver source of truth; the visual
// surface is the toast overlay.

// `@Environment(\.theme)` (the Theme env key from GameShellUI) is read only in
// the view bodies, not in any public signature, so this import is internal.
internal import GameShellUI
public import SettingsUI
public import MonetizationUI
public import SwiftUI
// #560: shared `GameCenterDashboard.present()`.
internal import GameCenterClient
// #744: `TelemetryEvent` appears in this type's public `telemetryEmit` init
// param (mirrors `SettingsScreen`'s decoupled emit closure).
public import Telemetry

public struct SettingsView<Banner: View>: View {
    @Bindable private var viewModel: SettingsViewModel
    private let monetizationController: MonetizationStateController?
    // #287: optional so previews / tests mount a byte-identical Settings screen
    // without the reminder section. Live wiring injects one + its copy so the
    // shared `ReminderSettingsSection` (enable / prime permission / time picker)
    // renders.
    private let reminderSettings: ReminderSettingsEntry?
    // #331: shared Notices section inputs. Defaulted so previews / tests mount
    // a byte-identical screen without the section; each app's composition root
    // injects the app-specific URLs + copyright + acknowledgements deep-link.
    private let notices: SettingsNoticesConfig?
    // #330 P2: the shared audio settings model (volumes / mute / music / haptics).
    // `nil` in previews / tests → no audio section, byte-identical screen. Live
    // wiring injects one whose setters fan out to the running `LiveSoundPlayer`.
    private let audioSettings: AudioSettingsModel?
    // Epic 5: optional banner slot below the Form. SettingsKit / GameShellUI
    // must NOT import MonetizationUI; the actual BannerSlotView is injected by
    // each app's LiveRouteFactory. EmptyView default keeps previews/tests inert.
    private let banner: Banner
    // #685: the Game Center row previously called `GameCenterDashboard.present()`
    // directly with no signed-out guard — a silent no-op when unauthenticated.
    // Injected so the live wiring can route through
    // `GameRootViewModel.presentGameCenterOrAlert`, matching the Home
    // leaderboard card's fallback. `nil` (default) preserves the old
    // ungated behavior for previews / tests that don't wire a root VM.
    private let presentGameCenter: (@MainActor () -> Void)?
    // #744: this app's numeric App Store Connect id, resolved from Bundle.main
    // at the composition root (mirroring the `appVersion` read) and forwarded
    // to `SettingsScreen`, which hides Share App / Write a Review when
    // nil/unresolved. `nil` default preserves the byte-identical screen for
    // previews / tests.
    private let appStoreID: String?
    // #744: Game Center "Invite Friends" entry point, mirrors `presentGameCenter`'s
    // shape. `nil` default (previews / tests) keeps the row absent.
    private let presentInviteFriends: (@MainActor () -> Void)?
    // #744: decoupled telemetry emit, forwarded to `SettingsScreen`. No-op
    // default keeps previews / tests side-effect-free.
    private let telemetryEmit: @Sendable (TelemetryEvent) -> Void
    @Environment(\.theme) private var theme

    /// #714: resolves the Game Center row's tap action, asserting in
    /// debug/test if `presentGameCenter` was never injected — the exact
    /// pre-#685 bug shape (unguarded `GameCenterDashboard.present()`), so a
    /// future Live.swift refactor that drops the injection fails CI instead
    /// of silently regressing. Mirrors `GameHomeViewModel.select`'s
    /// `presentLeaderboard` assert. `public` (not `internal`) — #832: both
    /// apps' test targets now drive this directly to prove the injected
    /// closure, not the fallback, actually fires.
    @MainActor
    public func resolvedOnGameCenter() {
        assert(
            presentGameCenter != nil,
            "presentGameCenter not wired — Settings Game Center row falls back to the unguarded pre-#685 GameCenterDashboard.present()"
        )
        (presentGameCenter ?? { GameCenterDashboard.present() })()
    }

    public init(
        viewModel: SettingsViewModel,
        monetizationController: MonetizationStateController? = nil,
        reminderSettings: ReminderSettingsEntry? = nil,
        notices: SettingsNoticesConfig? = nil,
        audioSettings: AudioSettingsModel? = nil,
        presentGameCenter: (@MainActor () -> Void)? = nil,
        appStoreID: String? = nil,
        presentInviteFriends: (@MainActor () -> Void)? = nil,
        telemetryEmit: @escaping @Sendable (TelemetryEvent) -> Void = { _ in },
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.viewModel = viewModel
        self.monetizationController = monetizationController
        self.reminderSettings = reminderSettings
        self.notices = notices
        self.audioSettings = audioSettings
        self.presentGameCenter = presentGameCenter
        self.appStoreID = appStoreID
        self.presentInviteFriends = presentInviteFriends
        self.telemetryEmit = telemetryEmit
        self.banner = banner()
    }

    public var body: some View {
        // #421: the shared assembly (shell + 5 sections in order) lives in
        // `SettingsUI.SettingsScreen`. This wrapper supplies the config + the
        // two injected slots (Purchases rows, the optional Sudoku-only
        // Generator About row) and the host-specific `.task` side-effects.
        SettingsScreen(
            version: viewModel.appVersion,
            tint: theme.accent.primary.resolved,
            clearCache: { await viewModel.clearCache() },
            reminderSettings: reminderSettings.map {
                // #287: shared Reminders section — same building block both apps
                // mount; map the entry into the shell's config.
                SettingsScreenReminderConfig(
                    model: $0.model,
                    copy: $0.copy,
                    primerCopy: $0.primerCopy,
                    deniedCopy: $0.deniedCopy
                )
            },
            // #330 P2: the shared audio section (renders only when non-nil).
            audioSettings: audioSettings,
            notices: notices,
            // Game Center entry: present Apple's native GC dashboard (no leaderboard
            // focus — opens the full listing). #560: shared `GameCenterDashboard`
            // in GameCenterClient. #685: signed-out taps now raise the same
            // alert as the Home leaderboard card instead of silently no-op'ing.
            onGameCenter: resolvedOnGameCenter,
            // #744: `presentInviteFriends` is forwarded straight through — the
            // composition root already wraps it in the same
            // `presentGameCenterOrAlert` signed-out guard before injecting it.
            appStoreID: appStoreID,
            presentInviteFriends: presentInviteFriends,
            telemetryEmit: telemetryEmit,
            // Purchases slot — the app's MonetizationUI rows. GameShellUI never
            // imports MonetizationUI; the whole conditional Section lives here.
            purchases: {
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
            // #277/#832: the Generator row is Sudoku-only. Rendered only when
            // the view model carries a label (Sudoku's composition root passes
            // `GeneratorVersion.v1.rawValue`; Minesweeper passes nothing).
            aboutExtraRows: {
                if let generatorVersionLabel = viewModel.generatorVersionLabel {
                    SettingsAboutExtraRow(
                        systemImage: "gearshape",
                        title: "Generator",
                        value: generatorVersionLabel,
                        tintColor: theme.accent.primary.resolved
                    )
                }
            },
            // Epic 5: banner injected by each app's LiveRouteFactory; EmptyView
            // in previews/tests.
            banner: { banner }
        )
        .task { await viewModel.bootstrap() }
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}
