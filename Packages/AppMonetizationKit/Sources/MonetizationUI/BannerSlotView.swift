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
//     hides every slot. It sits outside the creative's trailing edge, never
//     overlapping it (AdMob policy forbids app content over the creative;
//     #1084) — pinned by `BannerSlotGeometryKey`, read only by tests.
//     `BannerSlotBandLayout` insets the pair by `horizontalPadding`,
//     shrinking that inset symmetrically (never below 0) once the host is
//     narrower than `creative + ✕ + one inset` — the constraint is "the ✕
//     stays fully on-screen", not "the ✕ stays inside the visible band"
//     (PM's final ruling, #1084).
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
    /// `horizontalPadding` doubles as `BannerSlotBandLayout`'s nominal
    /// padding (#1084 PM ruling): the Layout itself carves out this inset,
    /// shrinking below it only when the host is too narrow to keep the ✕
    /// fully on-screen at the full inset.
    private let horizontalPadding: CGFloat
    private let verticalPadding: CGFloat

    /// Banner height contract (design.md v2 §How.3). Exactly 50pt visible.
    private static let bannerHeight: CGFloat = 50

    /// AdMob's standard banner creative (design.md v2 §How.6; #1084). Also
    /// the source of truth `AdsAdMob.BannerViewRepresentable.sizeThatFits`
    /// returns — the two sides must agree by construction, not by reading
    /// the SDK's `AdSize` at layout time (#1084 sim A/B: that read can be
    /// `.zero`, leaving the hosted `BannerView` invisible).
    public static let creativeSize = CGSize(width: 320, height: 50)
    /// Minimum tap target for the ✕, outside the creative's bounds (#1084).
    public static let dismissTargetSize: CGFloat = 44

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
        // uiux-bugfix-plan P1-6: `.opacity(0.7)` on a warm paper background
        // left the ✕ glyph nearly invisible after crop — full-strength
        // `.secondary` instead (#1084).
        dismissTint: Color = .secondary,
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
            // Horizontal inset is `BannerSlotBandLayout`'s job now (#1084) —
            // only the vertical inset stays a plain `.padding()` here.
            banner(session: session, id: registration.id)
                .padding(.vertical, verticalPadding)
        }
    }

    // MARK: - Banner

    private func banner(session: BannerSessionModel, id: BannerSlotID) -> some View {
        // #1084: the creative is pinned to its native 320×50 size. The ✕
        // sits in the gutter past the creative's trailing edge, never the
        // creative itself, so a mistap can never open the ad (AdMob policy).
        // `BannerSlotBandLayout` places both at a horizontal inset that is
        // `horizontalPadding` when the available width allows it, shrinking
        // symmetrically only when it can't (PM ruling, #1084).
        BannerSlotBandLayout(
            nominalPadding: horizontalPadding,
            creativeWidth: Self.creativeSize.width,
            dismissTargetSize: Self.dismissTargetSize,
            bannerHeight: Self.bannerHeight
        ) {
            // The visible band background, proposed the padded-in width
            // (`bounds.width − 2×padding`) by `placeSubviews` — NOT the
            // Layout's full, un-padded width — so it never bleeds into the
            // horizontal inset (#1084 review fix 1) and its `.slot` anchor
            // reads that same padded-in rect, not a tautological fixed size
            // (#1084 review fix 2). Non-interactive; declared first so the
            // real content (below, holding the interactive ✕) paints on
            // top of it.
            RoundedRectangle(cornerRadius: 8)
                .fill(backgroundColor)
                .allowsHitTesting(false)
                .layoutValue(key: BannerSlotBandRoleKey.self, value: .band)
                .anchorPreference(key: BannerSlotGeometryKey.self, value: .bounds) { [.slot: $0] }

            statusContent(session: session, id: id)
                .frame(width: Self.creativeSize.width, height: Self.creativeSize.height)
                // #1084 review: even if the bridge ever misreports the
                // creative's size, clip it to 320×50 so it can never paint
                // underneath the ✕.
                .clipped()
                .anchorPreference(key: BannerSlotGeometryKey.self, value: .bounds) { [.creative: $0] }
                .overlay(alignment: .trailing) {
                    dismissButton(session: session)
                        // Pins the ✕'s leading edge to the creative's
                        // trailing edge instead of the ✕'s own trailing edge.
                        .alignmentGuide(.trailing) { $0[.leading] }
                }
        }
        .accessibilityElement(children: .contain)
        // #895: was a raw Swift string — VoiceOver announced English on all
        // 7 locales.
        .accessibilityLabel(String(localized: "Advertisement", bundle: .main))
        // #931: stable, locale-independent anchor so E2E can query the slot's
        // shown/hidden state. Only present while the banner renders — a hidden
        // slot has no element at all, which IS the discriminator.
        .accessibilityIdentifier("monetization.banner.slot")
        // The accessibility element's own frame now spans the Layout's full,
        // un-padded width (host width) rather than just the padded-in band —
        // accepted as-is (#1084 review round); VoiceOver still reads the
        // right label and identifier at the right visible location.
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
                // uiux-bugfix-plan P1-6: 12pt read too small/low-contrast
                // after crop; 16pt inside the 44×44pt target (#1084).
                .font(.system(size: 16))
                .foregroundStyle(dismissTint)
                // #1084: 44×44pt hit target. Framing + `.contentShape` must
                // live on the label — `.buttonStyle(.plain)` otherwise shrinks
                // the hit-test region to the drawn glyph (swiftui-interaction-footguns).
                .frame(width: Self.dismissTargetSize, height: Self.dismissTargetSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // #895: was a raw Swift string — VoiceOver announced English on all
        // 7 locales.
        .accessibilityLabel(String(localized: "Dismiss ad", bundle: .main))
        .anchorPreference(key: BannerSlotGeometryKey.self, value: .bounds) { [.dismiss: $0] }
    }
}

// MARK: - BannerSlotBandLayout (#1084)

/// Which of `BannerSlotBandLayout`'s two subviews a child is — tagged via
/// `.layoutValue(key:value:)` since `placeSubviews` must propose the band a
/// different width than the content (#1084 review fix 1 and 2: the band must
/// stop at the padded-in width, not bleed into the horizontal inset or fill
/// the Layout's full un-padded width).
private enum BannerSlotBandRole: Sendable {
    /// The visible band background — proposed exactly the padded-in width
    /// (`bounds.width − 2×padding`), so its `.slot` anchor reads that rect.
    case band
    /// The creative + ✕ pair — proposed `.unspecified` so each keeps its own
    /// declared, fixed size.
    case content
}

private struct BannerSlotBandRoleKey: LayoutValueKey {
    static let defaultValue: BannerSlotBandRole = .content
}

/// Arranges the visible band background and the creative + ✕ pair at a
/// horizontal inset that is `nominalPadding` while `width ≥ needed +
/// nominalPadding` (380pt at the shipped constants: 320 + 44 + 16), shrinking
/// symmetrically (never below 0) below that. The constraint PM ruled on is
/// "the ✕ stays fully on-screen", not "the ✕ stays inside the band" — see
/// `padding(for:)`. A custom `Layout`, not `onGeometryChange` + `@State`: the
/// state-loop approach draws one frame at the wrong padding before
/// correcting on the next layout pass (PM ruling, #1084).
///
/// `sizeThatFits` always returns a concrete, finite size — including for an
/// unconstrained ("ideal") proposal — which is also what keeps
/// `NSHostingView.fittingSize` (the pre-existing `BannerSlotViewTests`
/// `measuredHeight` / `pauseKeepsLease` measurement path) from degenerating
/// to a zero height the way a bare `.frame(maxWidth: .infinity)` chain does.
private struct BannerSlotBandLayout: Layout {
    let nominalPadding: CGFloat
    let creativeWidth: CGFloat
    let dismissTargetSize: CGFloat
    let bannerHeight: CGFloat

    /// The creative and the ✕ side by side, with no gap between them.
    private var needed: CGFloat { creativeWidth + dismissTargetSize }

    /// `nominalPadding` while `width ≥ needed + nominalPadding` (PM's final
    /// ruling, #1084: the constraint is "the ✕ stays fully on-screen", not
    /// "the ✕ stays inside the band" — a ONE-SIDED comfort check, not
    /// `needed + 2×nominalPadding`. At 393pt (the most common iPhone width)
    /// this keeps the full 16pt left padding instead of shrinking to 14.5pt,
    /// which would visibly mismatch 402pt's 16pt for no reason; the ✕ then
    /// sits a few points past the band's own trailing edge but still well
    /// inside the screen. Below `needed + nominalPadding`, the padding
    /// shrinks symmetrically, clamped at 0.
    private func padding(for width: CGFloat) -> CGFloat {
        let comfortable = needed + nominalPadding
        guard width < comfortable else { return nominalPadding }
        return max(0, (width - needed) / 2)
    }

    /// The comfortable width at the full nominal padding on both sides —
    /// `sizeThatFits`'s ideal, and the fallback `resolvedBannerBandWidth`
    /// substitutes for a `nil` or non-finite proposal.
    private var idealWidth: CGFloat { needed + 2 * nominalPadding }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: resolvedBannerBandWidth(proposal: proposal.width, ideal: idealWidth), height: bannerHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let padding = padding(for: bounds.width)
        let origin = CGPoint(x: bounds.minX + padding, y: bounds.minY)
        for subview in subviews {
            switch subview[BannerSlotBandRoleKey.self] {
            case .band:
                // Stops at the padded-in width — never the Layout's full,
                // un-padded width (#1084 review fix 1 and 2).
                let bandWidth = max(0, bounds.width - 2 * padding)
                subview.place(
                    at: origin,
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: bandWidth, height: bannerHeight)
                )
            case .content:
                subview.place(at: origin, anchor: .topLeading, proposal: .unspecified)
            }
        }
    }
}

/// Resolves a proposed width to a concrete, finite value: `proposal` itself
/// when it's present and finite, `ideal` otherwise — covering both a `nil`
/// proposal (an unconstrained/"ideal" query) and a non-finite one (e.g.
/// `.infinity`, which a horizontal `ScrollView` can propose to its content
/// along the scroll axis). Without this, `BannerSlotBandLayout.sizeThatFits`
/// would propagate `.infinity`/`NaN`, contradicting its own "always a
/// concrete, finite size" doc comment (#1084 review fix 3).
///
/// `internal`, not `private`, purely as a test seam: `BannerSlotBandLayout`
/// itself stays `private`, but this pure function is unit-tested directly
/// with a literal `.infinity` argument, since no host inside
/// `BannerSlotDismissPlacementTests`'s headless macOS harness actually
/// produces a literal `.infinity` proposal (confirmed empirically — a
/// horizontal `ScrollView` and `.fixedSize(horizontal:)` both resolve to a
/// concrete or `nil` proposal there instead).
internal func resolvedBannerBandWidth(proposal: CGFloat?, ideal: CGFloat) -> CGFloat {
    guard let proposal, proposal.isFinite else { return ideal }
    return proposal
}

// MARK: - Geometry preference (#1084, test-only)

/// The three named parts `BannerSlotGeometryKey` reports bounds for.
public enum BannerSlotGeometryPart: Hashable, Sendable {
    case slot
    case creative
    case dismiss
}

/// Anchor bounds for the slot band, the creative, and the ✕ — read only by
/// `BannerSlotDismissPlacementTests` to prove the ✕ never overlaps the
/// creative (#1084). Declaring it has zero effect on what's rendered.
public struct BannerSlotGeometryKey: PreferenceKey {
    public static var defaultValue: [BannerSlotGeometryPart: Anchor<CGRect>] { [:] }

    public static func reduce(
        value: inout [BannerSlotGeometryPart: Anchor<CGRect>],
        nextValue: () -> [BannerSlotGeometryPart: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
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
