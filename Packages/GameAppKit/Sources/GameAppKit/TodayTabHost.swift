// TodayTabHost — the shared frame around every game's Today tab (#1020).
//
// The retired HOME view owned two universal pieces on top of each game's own
// content: the resume pill and the themed banner slot. HOME is gone in v3.0,
// so both moved here, wrapped around whatever the app supplies as its Today
// content (design.md §2.1: Today is a tab identity now, not a route).
//
// **#1024 — the banner slot (and the ATT anchor riding on it, C-33) moved
// OUT again**, into `BannerAccessoryView` / `tabViewBottomAccessory` (design.md
// §2.4): the accessory now covers the whole tab shell (Today/Practice/Settings)
// with ONE shared banner instead of a separate one per screen. `TodayTabHost`
// keeps only the resume pill.

public import SwiftUI
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
}
