// BannerSlotView — render slot for the v2 monetization banner.
//
// Per plan.md v2.3.4. Honest about its presence: when `AdGate` says no banner
// should show, the slot collapses to `EmptyView()` (0pt). When it should show
// but the provider has not yet returned a loaded handle, the slot reserves
// exactly 50pt of vertical space — no shimmer/skeleton/teaser (Brand audit
// "calm" contract; design-system.md).
//
// v2.3.4 ships UI wiring only; the underlying `LiveAdMobBridge.loadBanner`
// throws until v2.3.5 lands the real `GADBannerView` SDK wrapping. The
// `.loaded` branch therefore renders a static placeholder rect rather than
// an actual ad until that ships — see `AdMobBannerView` below.

public import MonetizationCore
public import SwiftUI

@MainActor
public struct BannerSlotView: View {
    private let adProvider: any AdProvider
    private let adGate: AdGate

    /// Banner height contract (design.md v2 §How.3). Exactly 50pt visible,
    /// 0pt when hidden — no in-between skeleton state.
    private static let bannerHeight: CGFloat = 50

    /// Gate decision (nil until `.task` resolves). Drives whether the slot
    /// renders any content at all.
    @State private var shouldShow: Bool?

    /// Latest provider status. Drives which subview (loading / placeholder /
    /// failed caption) appears inside the 50pt rect.
    @State private var status: AdBannerStatus = .notInitialized

    /// User tapped ✕. Locally hides the slot for the rest of the session
    /// in addition to the `AdGate.recordBannerDismissed` write-through.
    @State private var dismissed: Bool = false

    @Environment(\.theme) private var theme
    @Environment(\.scenePhase) private var scenePhase

    /// Gate-aware reload seam (#341). Re-evaluates `AdGate` and re-loads only
    /// when the gate is open — and never touches the provider when it's closed
    /// (purchased / dismissed-today / clock-tamper), keeping Remove-Ads intact.
    private let reloadCoordinator: BannerReloadCoordinator

    /// ATT pre-prompt trigger (#371 / #195). When the gate is open — i.e. a
    /// personalized ad is about to load, the first moment ATT actually matters —
    /// we offer the priming sheet (idempotent, once per launch). nil on hosts
    /// that don't drive ATT (Minesweeper has its own banner view; it never
    /// passes this, so MS never prompts ATT).
    private let attPrimer: ATTPrimerCoordinator?

    public init(
        adProvider: any AdProvider,
        adGate: AdGate,
        attPrimer: ATTPrimerCoordinator? = nil
    ) {
        self.adProvider = adProvider
        self.adGate = adGate
        self.attPrimer = attPrimer
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
            // foreground re-poll (`repollGate`), so this branch DOES fire when a
            // reload yields a new handle; same-handle reloads short-circuit
            // below. It guards the dispose path WITHOUT reviving the raw
            // `.onDisappear` dispose, which thrashed on transient SwiftUI
            // teardown (TabView switch, List recycling, split-view churn) (#276).
            guard case let .loaded(handle) = oldStatus else { return }
            if case .loaded(handle) = status { return } // same handle, no churn
            Task { await adProvider.dispose(handle: handle) }
        }
        .onChange(of: dismissed) { _, isDismissed in
            // Gate closed for the session (user tapped ✕). Release the held
            // banner so the provider drops its retained `GADBannerView` (#221).
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
                .background(theme.surface.placeholder.resolved, in: .rect(cornerRadius: 8))

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
                .tint(theme.accent.primary.resolved)
        case .loaded:
            // Deferred: real GADBannerView wiring. Until the live AdMob
            // bridge lands, render the same honest placeholder rect we use
            // for the deferred state so the slot doesn't lie to the user.
            AdMobBannerView()
        case .failed:
            Text("Ad unavailable")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
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
                .foregroundStyle(theme.accent.muted.resolved.opacity(0.7))
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
        // #371 / #195: the gate is open == a personalized ad is about to load ==
        // the first moment ATT actually matters. Offer the priming sheet here
        // (post-Home, contextual; never at cold launch). Idempotent — the
        // coordinator latches after one offer per launch.
        await attPrimer?.maybePresentOnAdContext()
        // Kick the provider via the reload seam. `loadBanner` throws in v2.3.4;
        // the failure surfaces as the visible "Ad unavailable" caption (its
        // `.failed` status) rather than being silently swallowed.
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
        // `.suppressed` means the gate is still closed (purchased /
        // dismissed-today / tamper) — leave the slot exactly as it is.
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

// MARK: - AdMobBannerView (placeholder)

/// SwiftUI wrapper around `GADBannerView` (Google Mobile Ads).
///
/// v2.3.4 ships the UI slot but the real SDK wiring lands in v2.3.5 alongside
/// `LiveAdMobBridge.loadBanner` (currently throws). Today this renders a
/// static "Ad will load here (v2.3.5)" rectangle so the slot is honest about
/// its deferred state — Brand "calm" contract forbids shimmer/teaser.
///
/// Deferred: replace this body with a `UIViewRepresentable` (iOS) /
/// `NSViewRepresentable` (macOS) wrapping a real `GADBannerView`. The bridge
/// already isolates the `import GoogleMobileAds` line (foundations.md §9.1)
/// so the import never leaks here.
struct AdMobBannerView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Text("Ad will load here (v2.3.5)")
            .font(.caption2)
            .foregroundStyle(theme.text.tertiary.resolved)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
