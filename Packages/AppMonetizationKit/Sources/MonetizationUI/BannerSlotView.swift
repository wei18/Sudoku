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
// `Color` params with sensible system defaults (mirrors `ToastView`). Sudoku
// passes its theme tokens; Minesweeper relies on the defaults.
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

    /// Gate-aware reload seam (#341).
    private let reloadCoordinator: BannerReloadCoordinator

    public init(
        adProvider: any AdProvider,
        adGate: AdGate,
        bannerHost: (any BannerViewProviding)? = nil,
        onAdContext: (@Sendable () async -> Void)? = nil,
        backgroundColor: Color = Color.secondary.opacity(0.12),
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
    }

    public var body: some View {
        Group {
            if dismissed || shouldShow == false {
                EmptyView()
            } else if shouldShow == true {
                banner
            } else {
                // Gate decision pending. Reserve zero space; the slot only
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
        .accessibilityLabel("Advertisement")
    }

    @ViewBuilder
    private var statusContent: some View {
        switch status {
        case .loading, .notInitialized:
            ProgressView()
                .controlSize(.small)
                .tint(progressTint)
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
        .accessibilityLabel("Dismiss ad")
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
