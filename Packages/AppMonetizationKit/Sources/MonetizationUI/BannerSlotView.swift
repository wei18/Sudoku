// BannerSlotView — the shared render slot for the v2 monetization banner (#441).
//
// Extracted into MonetizationUI from SudokuUI's `BannerSlotView` +
// MinesweeperUI's `MinesweeperBannerSlotView` so both apps share ONE slot
// (mirrors the #435 `PauseOverlayView` extraction; per
// minesweeper-mirrors-sudoku + reusable-targets-over-duplication).
//
// Contract (design.md v2 §How.3):
//   - Exactly 50pt visible when shown; 0pt (EmptyView) when hidden — no
//     shimmer / skeleton / teaser (Brand "calm" contract).
//   - #723 layout stability: when the gate's LAST resolution this session
//     allowed ads (`AdGate.lastKnownShouldShowBanner == true`), the slot
//     occupies its 50pt from the FIRST layout — before the async gate
//     re-resolution and before any ad loads — so the surrounding screen
//     (e.g. the Sudoku board) never reflows when the banner content
//     arrives. Loading only fills the already-reserved rect; it never
//     resizes it. Gate-denied (Remove Ads purchased / dismissed today)
//     still collapses to EmptyView. Before the session's first-ever
//     resolution the hint is `nil` and the slot keeps the legacy
//     collapsed-while-pending behavior (cold-launch first screen only).
//   - Dismiss ✕ writes through to `AdGate.recordBannerDismissed` AND hides the
//     slot for the rest of the session.
//   - Honest status captions: loading (ProgressView), failed ("Ad unavailable"),
//     suppressed / disposed (collapse).
//   - `.loaded(handle)` now renders the REAL banner from `bannerHost` (#441).
//     When no host is wired (fakes / macOS NoopAdProvider) it shows nothing
//     inside the rect rather than lying with a placeholder.
//
// Theme decoupling: this module must not depend on the apps' `Theme` protocol
// (Package.swift — MonetizationUI → MonetizationCore only). Colours are DI'd as
// `Color` params with sensible system defaults (mirrors `ToastView`). Both apps'
// Home/Board callers pass their own theme tokens; the Daily/Practice/Settings
// callers (both apps) still rely on the defaults below — #688 item 2 made the
// default `backgroundColor` transparent so those un-themed slots blend with
// whatever page background sits behind them instead of drawing a mismatched
// system-gray seam.
//
// SDK isolation: the real banner view crosses the AdsAdMob border as an
// `AnyView` via `BannerViewProviding` — `GoogleMobileAds` never leaks here
// (foundations.md §9.1).

public import MonetizationCore
public import SwiftUI

@MainActor
public struct BannerSlotView: View {
    private let adProvider: any AdProvider
    private let adGate: AdGate

    /// Live banner-view source. `nil` for providers that serve no real ad
    /// (fakes / macOS NoopAdProvider) — the `.loaded` branch then renders
    /// nothing inside the rect instead of a placeholder.
    private let bannerHost: (any BannerViewProviding)?

    /// Optional ad-context hook (Sudoku's ATT pre-prompt, #371 / #195). Invoked
    /// once the gate opens — the first moment a personalized ad is about to
    /// load. Injected as a closure so MonetizationUI stays free of SudokuUI's
    /// `ATTPrimerCoordinator`. Minesweeper passes `nil` (no ATT flow).
    private let onAdContext: (@Sendable () async -> Void)?

    // DI'd colours (theme decoupling — see file header).
    private let backgroundColor: Color
    private let progressTint: Color
    private let captionColor: Color
    private let dismissTint: Color

    /// Banner height contract (design.md v2 §How.3). Exactly 50pt visible,
    /// 0pt when hidden — no in-between skeleton state.
    private static let bannerHeight: CGFloat = 50

    @State private var shouldShow: Bool?
    @State private var status: AdBannerStatus = .notInitialized
    @State private var dismissed: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    /// Test/preview-only override for the `.loading`/`.notInitialized` visual
    /// (#732): the live `ProgressView` is a genuinely timing-dependent spin
    /// animation, so board-banner snapshot fixtures that capture it are
    /// environment-sensitive across machines/worktrees. `nil` (default)
    /// preserves production's real spinner untouched; a caller (snapshot
    /// tests only) can inject a static placeholder via
    /// `.environment(\.bannerSlotLoadingPreview, ...)` from OUTSIDE this
    /// view, so no production call site needs to change.
    @Environment(\.bannerSlotLoadingPreview) private var loadingPreview

    /// Gate-aware reload seam (#341).
    private let reloadCoordinator: BannerReloadCoordinator

    public init(
        adProvider: any AdProvider,
        adGate: AdGate,
        bannerHost: (any BannerViewProviding)? = nil,
        onAdContext: (@Sendable () async -> Void)? = nil,
        // #688 item 2: was `Color.secondary.opacity(0.12)` — a translucent
        // system-gray overlay that reads as a mismatched seam against a
        // custom (non-system) page background, especially in dark mode.
        // Transparent by default so an unthemed caller's slot blends with
        // whatever sits behind it instead of announcing its own tint.
        backgroundColor: Color = .clear,
        progressTint: Color = .accentColor,
        captionColor: Color = .secondary,
        dismissTint: Color = Color.secondary.opacity(0.7)
    ) {
        self.adProvider = adProvider
        self.adGate = adGate
        self.bannerHost = bannerHost
        self.onAdContext = onAdContext
        self.backgroundColor = backgroundColor
        self.progressTint = progressTint
        self.captionColor = captionColor
        self.dismissTint = dismissTint
        self.reloadCoordinator = BannerReloadCoordinator(adProvider: adProvider, adGate: adGate)
        // #723: seed the show/hide decision from the gate's synchronous
        // session hint so a slot mounted after the gate has resolved once
        // (Board entered from Home, hub screens, …) reserves its 50pt from
        // the very first layout. `nil` (nothing resolved yet this session)
        // keeps the legacy collapsed-pending default; the authoritative
        // async resolution in `resolveGateAndLoad` overwrites this either way.
        _shouldShow = State(initialValue: adGate.lastKnownShouldShowBanner)
    }

    public var body: some View {
        Group {
            if dismissed || shouldShow == false {
                EmptyView()
            } else if shouldShow == true {
                banner
            } else {
                // Gate decision pending AND no session hint (`shouldShow` is
                // seeded from `AdGate.lastKnownShouldShowBanner` in init, so
                // this branch only runs before the session's first-ever
                // resolution — #723). Reserve zero space; the slot
                // materializes once `shouldShow == true` resolves.
                EmptyView()
            }
        }
        .task { await resolveGateAndLoad() }
        .onChange(of: status) { oldStatus, _ in
            // Defensive: dispose the previously-loaded handle if it is ever
            // replaced or dropped. Since #341, `status` is written again on a
            // foreground re-poll (`repollGate`), so this DOES fire when a reload
            // yields a new handle; same-handle reloads short-circuit below. It
            // guards the dispose path WITHOUT reviving the raw `.onDisappear`
            // dispose, which thrashed on transient SwiftUI teardown (#276).
            guard case let .loaded(handle) = oldStatus else { return }
            if case .loaded(handle) = status { return } // same handle, no churn
            Task { await adProvider.dispose(handle: handle) }
        }
        .onChange(of: dismissed) { _, isDismissed in
            // Gate closed for the session (user tapped ✕). Release the held
            // banner so the provider drops its retained banner view (#221).
            guard isDismissed, case let .loaded(handle) = status else { return }
            Task { await adProvider.dispose(handle: handle) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-poll seam (#341). On returning to the foreground, re-evaluate
            // the gate: if it has reopened (e.g. the calendar day rolled over
            // since a dismiss), reload so the banner reappears instead of
            // staying gone until app relaunch. The coordinator consults
            // `AdGate` first, so a purchaser / dismissed-today / tamper case
            // returns `.suppressed` and the provider is never touched.
            guard newPhase == .active else { return }
            Task { await repollGate() }
        }
    }

    // MARK: - Banner

    private var banner: some View {
        ZStack(alignment: .topTrailing) {
            statusContent
                .frame(maxWidth: .infinity)
                .frame(height: Self.bannerHeight)
                .background(backgroundColor, in: .rect(cornerRadius: 8))

            dismissButton
                .padding(6)
        }
        .accessibilityElement(children: .contain)
        // #895: was a raw Swift string — VoiceOver announced English on all
        // 7 locales.
        .accessibilityLabel(String(localized: "Advertisement", bundle: .main))
    }

    @ViewBuilder
    private var statusContent: some View {
        switch status {
        case .loading, .notInitialized:
            if let loadingPreview {
                loadingPreview
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(progressTint)
            }
        case let .loaded(handle):
            // The real banner view, type-erased across the AdsAdMob border
            // (#441). When no host is wired (fakes / macOS NoopAdProvider) we
            // render nothing inside the rect rather than a placeholder.
            if let view = bannerHost?.bannerView(for: handle) {
                view
            } else {
                EmptyView()
            }
        case .failed:
            Text("Ad unavailable")
                .font(.caption)
                .foregroundStyle(captionColor)
        case .suppressed:
            // AdGate handles suppression; reaching here means the provider
            // disagreed with the gate. Render nothing inside the rect so
            // we don't show a stale state.
            EmptyView()
        case .disposed:
            // The held handle was released (gate closed / dismissed); the slot
            // is already collapsing. Render nothing rather than a stale ad.
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button {
            Task { await dismissTapped() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(dismissTint)
        }
        .buttonStyle(.plain)
        // #895: was a raw Swift string — VoiceOver announced English on all
        // 7 locales.
        .accessibilityLabel(String(localized: "Dismiss ad", bundle: .main))
    }

    // MARK: - Lifecycle

    private func resolveGateAndLoad() async {
        let now = Date()
        let allowed = await adGate.shouldShowBanner(now: now)
        shouldShow = allowed
        guard allowed else { return }
        // Gate open == a personalized ad is about to load == the first moment
        // ATT actually matters (#371 / #195). Sudoku injects its ATT primer
        // here; Minesweeper passes nil. Idempotent — the closure latches.
        await onAdContext?()
        // Kick the provider via the reload seam. A failed load surfaces as the
        // visible "Ad unavailable" caption (its `.failed` status) rather than
        // being silently swallowed.
        status = await reloadCoordinator.reloadIfGateOpen(now: now)
    }

    /// Foreground re-poll (#341). If the gate has reopened since the last
    /// resolution (new calendar day after a dismiss), clear the session
    /// `dismissed` latch and reload so the slot reappears. If the gate is
    /// still closed (purchased / dismissed-today / tamper), the coordinator
    /// returns `.suppressed` without touching the provider and we leave the
    /// slot hidden.
    private func repollGate() async {
        let reloaded = await reloadCoordinator.reloadIfGateOpen(now: Date())
        guard reloaded != .suppressed else { return }
        status = reloaded
        shouldShow = true
        if dismissed {
            withAnimation(.easeInOut(duration: 0.18)) { dismissed = false }
        }
    }

    private func dismissTapped() async {
        await adGate.recordBannerDismissed(now: Date())
        withAnimation(.easeInOut(duration: 0.18)) {
            dismissed = true
        }
    }
}

// MARK: - Loading-preview environment override (#732)

private struct BannerSlotLoadingPreviewKey: EnvironmentKey {
    // Always `nil` — no actual shared mutable state — so `nonisolated(unsafe)`
    // is safe here and avoids isolating the whole `EnvironmentKey` conformance
    // to `@MainActor` (which `AnyView?`'s non-Sendable payload would otherwise
    // force).
    nonisolated(unsafe) static let defaultValue: AnyView? = nil
}

public extension EnvironmentValues {
    /// See `BannerSlotView.loadingPreview`. `nil` by default — only snapshot
    /// tests set this, from outside `BannerSlotView`'s own view tree.
    var bannerSlotLoadingPreview: AnyView? {
        get { self[BannerSlotLoadingPreviewKey.self] }
        set { self[BannerSlotLoadingPreviewKey.self] = newValue }
    }
}
