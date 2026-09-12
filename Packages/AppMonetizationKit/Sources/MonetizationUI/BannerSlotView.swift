// BannerSlotView — the shared render slot for the v2 monetization banner (#441).
//
// Extracted into MonetizationUI from SudokuUI's `BannerSlotView` +
// MinesweeperUI's `MinesweeperBannerSlotView` so both apps share ONE slot
// (mirrors the #435 `PauseOverlayView` extraction; per
// minesweeper-mirrors-sudoku + reusable-targets-over-duplication).
//
// Contract (design.md v2 §How.3; #1058 slot-model spec rev 3.2):
//   - A PURE renderer. Everything that decides whether and what to show lives
//     in the session-scoped `BannerSessionModel` injected as `\.bannerSession`:
//     gate, provider readiness, the ATT primer, loads, repoll, dismiss. This
//     view carries no lifecycle modifiers and no `@State` — those never run on
//     a view whose body renders nothing, which is exactly how #1058 shipped.
//   - Registration is a `DynamicProperty` (`BannerSlotRegistration`), installed
//     on the view node whether or not the body renders anything.
//   - Exactly 50pt visible when shown; zero subviews when hidden (session gate
//     closed or pending, host-suppressed, provider suppressed) — a parent with
//     non-zero spacing adds no gap around a hidden slot.
//   - `isSuppressed` is the host's own quiet state (a paused or finished
//     board). The slot's identity and its loaded handle survive it.
//   - Honest status captions: loading (ProgressView), failed ("Ad unavailable"),
//     loaded (the real banner from `session.bannerView(for:)`, or nothing when
//     the provider hosts no view).
//   - ✕ calls `session.dismiss()`, which records today's dismissal and then
//     hides every slot.
//
// Theme decoupling: this module must not depend on the apps' `Theme` protocol
// (Package.swift — MonetizationUI → MonetizationCore only). Colours are DI'd as
// `Color` params with system defaults (mirrors `ToastView`).
//
// SDK isolation: the real banner view crosses the AdsAdMob border as an
// `AnyView` via `BannerViewProviding` — `GoogleMobileAds` never leaks here
// (foundations.md §9.1).

public import SwiftUI

@MainActor
public struct BannerSlotView: View {
    private var registration: BannerSlotRegistration

    /// The host's quiet state (paused / terminal board). Renders nothing while
    /// `true`, without ending the slot's registration.
    private let isSuppressed: Bool

    // DI'd colours (theme decoupling — see file header).
    private let backgroundColor: Color
    private let progressTint: Color
    private let captionColor: Color
    private let dismissTint: Color

    /// Outer inset applied ONLY to the visible banner, never to the hidden
    /// state, so a hidden slot contributes zero size to its parent. A caller
    /// must not chain `.padding(...)` onto the whole `BannerSlotView` value.
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    /// Banner height contract (design.md v2 §How.3). Exactly 50pt visible.
    private static let bannerHeight: CGFloat = 50

    /// Test/preview-only override for the `.loading`/`.notInitialized` visual
    /// (#732): the live `ProgressView` is a timing-dependent spin animation, so
    /// board-banner snapshot fixtures inject a static placeholder via
    /// `.environment(\.bannerSlotLoadingPreview, ...)`. `nil` in production.
    @Environment(\.bannerSlotLoadingPreview) private var loadingPreview

    public init(
        isSuppressed: Bool,
        // #688 item 2: transparent by default so an unthemed caller's slot
        // blends with whatever sits behind it instead of announcing its own tint.
        backgroundColor: Color = .clear,
        progressTint: Color = .accentColor,
        captionColor: Color = .secondary,
        dismissTint: Color = Color.secondary.opacity(0.7),
        horizontalPadding: CGFloat = 0,
        verticalPadding: CGFloat = 0
    ) {
        self.registration = BannerSlotRegistration()
        self.isSuppressed = isSuppressed
        self.backgroundColor = backgroundColor
        self.progressTint = progressTint
        self.captionColor = captionColor
        self.dismissTint = dismissTint
        self.horizontalPadding = horizontalPadding
        self.verticalPadding = verticalPadding
    }

    public var body: some View {
        if let session = registration.session, session.isVisible, !isSuppressed {
            banner(session: session, id: registration.id)
                .padding(.horizontal, horizontalPadding)
                .padding(.vertical, verticalPadding)
        }
    }

    // MARK: - Banner

    private func banner(session: BannerSessionModel, id: BannerSlotID) -> some View {
        ZStack(alignment: .topTrailing) {
            statusContent(session: session, id: id)
                .frame(maxWidth: .infinity)
                .frame(height: Self.bannerHeight)
                .background(backgroundColor, in: .rect(cornerRadius: 8))

            dismissButton(session: session)
                .padding(6)
        }
        .accessibilityElement(children: .contain)
        // #895: was a raw Swift string — VoiceOver announced English on all
        // 7 locales.
        .accessibilityLabel(String(localized: "Advertisement", bundle: .main))
        // #931: stable, locale-independent anchor so E2E can query the slot's
        // shown/hidden state. Only present while the banner renders — a hidden
        // slot has no element at all, which IS the discriminator.
        .accessibilityIdentifier("monetization.banner.slot")
    }

    @ViewBuilder
    private func statusContent(session: BannerSessionModel, id: BannerSlotID) -> some View {
        switch session.status(for: id) {
        case .loading, .notInitialized:
            if let loadingPreview {
                loadingPreview
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(progressTint)
            }
        case .loaded:
            // The real banner view, type-erased across the AdsAdMob border
            // (#441). A provider with no view host renders nothing inside the
            // rect rather than a placeholder.
            if let view = session.bannerView(for: id) {
                view
            } else {
                EmptyView()
            }
        case .failed:
            // #901: explicit `bundle: .main` — catalogs live in the app target.
            Text("Ad unavailable", bundle: .main)
                .font(.caption)
                .foregroundStyle(captionColor)
        case .suppressed, .disposed:
            EmptyView()
        }
    }

    private func dismissButton(session: BannerSessionModel) -> some View {
        Button {
            Task { await session.dismiss() }
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
