// TodayTabHost — the shared frame around every game's Today tab (#1020).
//
// The retired HOME view owned three universal pieces on top of each game's
// own content: the resume pill, the themed banner slot, and — hanging off that
// banner slot — the ATT pre-prompt anchor. HOME is gone in v3.0, so the resume
// pill and banner slot move here, wrapped around whatever the app supplies as
// its Today content (design.md §2.1: Today is a tab identity now, not a route).
//
// **C-33 (BREAK) — the ATT anchor.** `screen-contracts.md` recorded
// ATT-PRIMER's entry point as "the HOME view's banner slot"; design.md §3.6.1
// re-anchored it to the Today tab's first banner load. Since #1058 the primer
// is requested by the session's `BannerSessionModel` readiness task (its
// `onAdContext` hook, wired in `makeGameApp`), not by this host's slot. The
// semantics are unchanged — still the first ad-relevant context — and so is
// every existing behavior: the primer does not block Today's interaction, the
// one-shot `hasOffered` latch still gates it, a decline is never re-offered,
// and it only appears while ATT is `.notDetermined`. `ATTPrimerCoordinator`
// itself is NOT modified; only the call site moved.
//
// The banner styling (tint tokens, padding) is carried over unchanged from that
// retired banner slot so this one renders identically.

public import SwiftUI
internal import MonetizationUI
internal import GameShellUI

@MainActor
public struct TodayTabHost<Route: Hashable & Sendable, Content: View>: View {
    private let rootViewModel: GameRootViewModel<Route>
    private let content: Content

    @Environment(\.theme) private var theme

    public init(
        rootViewModel: GameRootViewModel<Route>,
        @ViewBuilder content: () -> Content
    ) {
        self.rootViewModel = rootViewModel
        self.content = content()
    }

    public var body: some View {
        VStack(spacing: 0) {
            resumeHeader
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            bannerSlot
        }
        .background(theme.surface.background.resolved)
        // Stable, non-localized anchor for the landing assertion in host-driven
        // E2E flows ("left the board, landed back on the app's root screen") in
        // any locale. Replaces the retired HOME scaffold's "game.home.root"
        // (#935) — both apps mount this same host as their Today tab's root, so
        // one identifier serves both (mirror principle).
        .accessibilityIdentifier("game.today.root")
    }

    // MARK: - ResumePill header (#387 / #554)

    /// Renders only when a resume candidate exists. `resumeTapped()` pushes onto
    /// the SELECTED tab's stack — normally Today's, since that is where the pill
    /// is shown.
    @ViewBuilder
    private var resumeHeader: some View {
        if let candidate = rootViewModel.resumeCandidate {
            ResumePill(title: candidate.title, subtitle: candidate.subtitle) {
                rootViewModel.resumeTapped()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: - BannerSlotView (#371 / #195 / #441)

    /// Themed banner slot. Whether it shows is the environment's
    /// `BannerSessionModel`'s decision (#1058); Today never suppresses it.
    private var bannerSlot: some View {
        BannerSlotView(
            isSuppressed: false,
            // #688 item 2: match the page background so an empty/loading slot is
            // invisible instead of reading as a mismatched seam in dark mode.
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7),
            // Padding lives inside `BannerSlotView` so a hidden slot collapses
            // to zero height instead of leaving a padded gap.
            horizontalPadding: 16,
            verticalPadding: 12
        )
    }
}
