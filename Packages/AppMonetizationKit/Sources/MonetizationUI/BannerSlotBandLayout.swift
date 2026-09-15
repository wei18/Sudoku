// BannerSlotBandLayout — the Layout that places `BannerSlotView`'s visible
// band background and its creative + ✕ pair (#1084).
//
// Extracted out of BannerSlotView.swift (#1080): adding the externally-owned-
// lease init there pushed that file to 402 lines, over the repo's
// `file_length` ceiling (400, SwiftLint `--strict`) — same move CLAUDE.md
// documents for `Live.swift`-style files ("extract Live+Feature.swift
// instead of growing it"). Pure move, no behavior change: `BannerSlotBandRole`,
// `BannerSlotBandRoleKey` and `BannerSlotBandLayout` go from `private` (file-
// scoped) to `internal` (module-scoped) ONLY because `BannerSlotView.swift`'s
// `banner(session:id:)` constructs `BannerSlotBandLayout` and tags subviews
// with `BannerSlotBandRoleKey` — neither becomes `public`.

import SwiftUI

/// Which of `BannerSlotBandLayout`'s two subviews a child is — tagged via
/// `.layoutValue(key:value:)` since `placeSubviews` must propose the band a
/// different width than the content (#1084 review fix 1 and 2: the band must
/// stop at the padded-in width, not bleed into the horizontal inset or fill
/// the Layout's full un-padded width).
enum BannerSlotBandRole: Sendable {
    /// The visible band background — proposed exactly the padded-in width
    /// (`bounds.width − 2×padding`), so its `.slot` anchor reads that rect.
    case band
    /// The creative + ✕ pair — proposed `.unspecified` so each keeps its own
    /// declared, fixed size.
    case content
}

struct BannerSlotBandRoleKey: LayoutValueKey {
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
struct BannerSlotBandLayout: Layout {
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
/// itself stays `internal` (not `public`, #1080's file split), but this pure
/// function is unit-tested directly with a literal `.infinity` argument,
/// since no host inside `BannerSlotDismissPlacementTests`'s headless macOS
/// harness actually produces a literal `.infinity` proposal (confirmed
/// empirically — a horizontal `ScrollView` and `.fixedSize(horizontal:)`
/// both resolve to a concrete or `nil` proposal there instead).
internal func resolvedBannerBandWidth(proposal: CGFloat?, ideal: CGFloat) -> CGFloat {
    guard let proposal, proposal.isFinite else { return ideal }
    return proposal
}
