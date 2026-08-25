// TodayTabHost — the shared frame around every game's Today tab (#1020).
//
// The retired HOME view owned three universal pieces on top of each game's
// own content: the resume pill, the themed banner slot, and — hanging off that
// banner slot — the ATT pre-prompt anchor. HOME is gone in v3.0, so those three
// move here, wrapped around whatever the app supplies as its Today content
// (design.md §2.1: Today is a tab identity now, not a route).
//
// **C-33 (BREAK) — the ATT anchor moves with them.** `screen-contracts.md`
// recorded ATT-PRIMER's entry point as "the HOME view's banner slot"; design.md
// §3.6.1 re-anchors it to the Today tab's first banner load. The semantics are
// unchanged — still the first ad-relevant context — and so is every existing
// behavior: the primer does not block Today's interaction, the one-shot
// `hasOffered` latch still gates it, a decline is never re-offered, and it only
// appears while ATT is `.notDetermined`. `ATTPrimerCoordinator` itself is NOT
// modified by #1020; only the call site moved.
//
// The banner wiring (tint tokens, `onAdContext` hook, padding) is carried over
// unchanged from that retired banner slot so this one renders identically.

public import SwiftUI
public import MonetizationCore
public import MonetizationUI
internal import GameShellUI

@MainActor
public struct TodayTabHost<Route: Hashable & Sendable, Content: View>: View {
    private let rootViewModel: GameRootViewModel<Route>
    private let adProvider: any AdProvider
    private let adGate: AdGate
    private let attPrimer: ATTPrimerCoordinator
    private let content: Content

    @Environment(\.theme) private var theme

    public init(
        rootViewModel: GameRootViewModel<Route>,
        adProvider: any AdProvider,
        adGate: AdGate,
        attPrimer: ATTPrimerCoordinator,
        @ViewBuilder content: () -> Content
    ) {
        self.rootViewModel = rootViewModel
        self.adProvider = adProvider
        self.adGate = adGate
        self.attPrimer = attPrimer
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

    // MARK: - BannerSlotView + the ATT anchor (#371 / #195 / #441 / C-33)

    /// ATT-primed themed banner slot. `onAdContext` fires once the gate opens —
    /// the first moment a personalized ad is about to load, which is the
    /// "first ad-relevant context" C-33 re-anchors the primer to.
    @ViewBuilder
    private var bannerSlot: some View {
        let onAdContext: (@Sendable () async -> Void)? = { [attPrimer] in
            await attPrimer.maybePresentOnAdContext()
        }
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            onAdContext: onAdContext,
            // #688 item 2: match the page background so an empty/loading slot is
            // invisible instead of reading as a mismatched seam in dark mode.
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
