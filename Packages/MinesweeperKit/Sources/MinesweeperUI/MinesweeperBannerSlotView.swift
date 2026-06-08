// MinesweeperBannerSlotView — MS mirror of SudokuKit's `BannerSlotView`.
//
// Mirrors the Sudoku slot's contract (50pt visible / 0pt collapsed, no
// shimmer, dismiss button writes through to `AdGate.recordBannerDismissed`,
// `.failed` surfaces an "Ad unavailable" caption). Styling uses plain SwiftUI
// primitives instead of the SudokuUI theme tokens — MS has no theme system
// yet, so theme-token reuse would require extracting the theme env out of
// SudokuUI (out of U15 scope; tracked in impl-notes D1 as a future
// consolidation candidate).
//
// Behaviour is intentionally byte-equivalent to Sudoku's BannerSlotView so
// any future migration to a shared `MonetizationUI.BannerSlotView` is a
// straight code-move + theme-tint injection.

internal import MonetizationCore
internal import SwiftUI

@MainActor
internal struct MinesweeperBannerSlotView: View {
    private let adProvider: any AdProvider
    private let adGate: AdGate

    /// Banner height contract (mirrors Sudoku §How.3). 50pt visible, 0pt
    /// when hidden — no in-between skeleton state.
    private static let bannerHeight: CGFloat = 50

    @State private var shouldShow: Bool?
    @State private var status: AdBannerStatus = .notInitialized
    @State private var dismissed: Bool = false

    @Environment(\.scenePhase) private var scenePhase

    /// Gate-aware reload seam (#341). Mirror of Sudoku's slot.
    private let reloadCoordinator: BannerReloadCoordinator

    internal init(adProvider: any AdProvider, adGate: AdGate) {
        self.adProvider = adProvider
        self.adGate = adGate
        self.reloadCoordinator = BannerReloadCoordinator(adProvider: adProvider, adGate: adGate)
    }

    internal var body: some View {
        Group {
            if dismissed || shouldShow == false {
                EmptyView()
            } else if shouldShow == true {
                banner
            } else {
                EmptyView()
            }
        }
        .task { await resolveGateAndLoad() }
        .onChange(of: status) { oldStatus, _ in
            // Mirror of Sudoku's slot. Defensive: `status` is written once today
            // so this does not fire — it guards the dispose path for a future
            // re-poll/refresh WITHOUT reviving the raw `.onDisappear` dispose,
            // which thrashed on transient SwiftUI teardown (#276).
            guard case let .loaded(handle) = oldStatus else { return }
            if case .loaded(handle) = status { return } // same handle, no churn
            Task { await adProvider.dispose(handle: handle) }
        }
        .onChange(of: dismissed) { _, isDismissed in
            // Gate closed for the session — release the held banner (#221).
            guard isDismissed, case let .loaded(handle) = status else { return }
            Task { await adProvider.dispose(handle: handle) }
        }
        .onChange(of: scenePhase) { _, newPhase in
            // Re-poll seam (#341). Mirror of Sudoku's slot: on foreground,
            // re-evaluate the gate so a next-day reopen reloads the banner.
            // Coordinator consults `AdGate` first, so a purchaser / dismissed-
            // today / tamper case returns `.suppressed` and the provider is
            // never touched.
            guard newPhase == .active else { return }
            Task { await repollGate() }
        }
    }

    private var banner: some View {
        ZStack(alignment: .topTrailing) {
            statusContent
                .frame(maxWidth: .infinity)
                .frame(height: Self.bannerHeight)
                .background(.regularMaterial, in: .rect(cornerRadius: 8))

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
        case .loaded:
            // Placeholder pending real GADBannerView UIViewRepresentable —
            // same status as Sudoku's slot (`AdMobBannerView`). The honest
            // caption avoids the calm-contract "shimmer/teaser" footgun.
            Text("Ad loaded")
                .font(.caption2)
                .foregroundStyle(.secondary)
        case .failed:
            Text("Ad unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .suppressed:
            EmptyView()
        case .disposed:
            // Mirror of Sudoku's slot — held handle released, slot collapsing.
            EmptyView()
        }
    }

    private var dismissButton: some View {
        Button {
            Task { await dismissTapped() }
        } label: {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.secondary.opacity(0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Dismiss ad")
    }

    private func resolveGateAndLoad() async {
        let now = Date()
        let allowed = await adGate.shouldShowBanner(now: now)
        shouldShow = allowed
        guard allowed else { return }
        status = await reloadCoordinator.reloadIfGateOpen(now: now)
    }

    /// Foreground re-poll (#341). Mirror of Sudoku's slot.
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
