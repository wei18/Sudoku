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

    public init(adProvider: any AdProvider, adGate: AdGate) {
        self.adProvider = adProvider
        self.adGate = adGate
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
        .onDisappear {
            // Release the live banner's `GADBannerView` when the slot goes away
            // so the provider doesn't retain it for the handle's lifetime
            // (#221). No-op unless we hold a loaded handle.
            guard case let .loaded(handle) = status else { return }
            Task { await adProvider.dispose(handle: handle) }
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
            // TODO(v2.3.5): real GADBannerView wiring. Until the live AdMob
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
        // Kick the provider. `loadBanner` throws in v2.3.4; the failure
        // surfaces as the visible "Ad unavailable" caption rather than
        // being silently swallowed.
        do {
            try await adProvider.refreshBanner()
            status = await adProvider.bannerStatus
        } catch {
            status = .failed(reason: String(describing: error))
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
/// TODO(v2.3.5): replace this body with a `UIViewRepresentable` (iOS) /
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
