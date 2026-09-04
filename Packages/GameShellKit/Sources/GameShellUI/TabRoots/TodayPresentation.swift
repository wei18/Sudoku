// TodayPresentation — TODAY's per-app state variants (#1021 Phase A,
// design.md §3.1 state table). Distinct from `HubLoadState` (the generic
// idle/loading/loaded/empty/failed shape `DailyHubShellView` already
// switches on): this enum carries TODAY-specific presentation semantics
// (`allDone`, `degraded`) that a future Phase wires into the shell's own
// state machine — it does not replace or extend `HubLoadState` itself.
//
// Sudoku maps all five cases. Minesweeper maps four: its daily generation is
// pure and non-throwing, so `.exhausted` is structurally unreachable there
// (design.md §3.1, D21).

public enum TodayPresentation<Card: Identifiable & Sendable>: Sendable {
    case loading
    case loaded([Card])
    /// Today's puzzles are all complete — render `TodayAllDoneBlock`
    /// ADDITIONALLY, above the header (approved decision, #1021 CR2 M3: an
    /// earlier doc pass said this REPLACES the three cards; it does not).
    /// The 3 cards stay in the shell's normal card grid below, still
    /// tappable — completed cards route to the review flow like any other
    /// completed card. `cards` here is what the caller actually renders.
    case allDone([Card])
    /// Cards still render (seed-derived thumbnails, no CK dependency) but
    /// every card must be drawn as "not started" — the caller building
    /// `[Card]` is responsible for that degrade, not this enum. `reason`
    /// distinguishes WHY (#1021 CR3, design.md §3.1's `degraded` row):
    /// `.completionStatusUnknown` degrades silently (real thumbnails, only
    /// the checkmark is unknown); `.loadFailed` additionally needs a visible
    /// caption — see `TodayLoadFailureCaption` — because there is no puzzle
    /// data behind these cards at all.
    case degraded([Card], reason: DegradedReason)
    /// Sudoku only — no more daily puzzles left to generate for a stretch.
    case exhausted

    /// #1021 CR3: kept as its own type (not a `Bool` threaded through views)
    /// so every consumer switches over it exhaustively instead of guessing
    /// what a bare flag means at the call site.
    public enum DegradedReason: Sendable, Equatable {
        /// Phase-2 (completion overlay) fetch failed. Real puzzle data is in
        /// hand — only which cards are already solved is unknown. Silent:
        /// no caption, matches design.md §3.1's accepted quiet degrade.
        case completionStatusUnknown
        /// Phase-1 (the trio fetch itself) failed. No puzzle data exists for
        /// this session at all — the caller renders skeleton placeholders
        /// and MUST surface a visible caption (#768's "recoverable inline
        /// failure" precedent, reversed by #1021 CR2's silent regression).
        case loadFailed
    }

    public var cards: [Card] {
        switch self {
        case .loading, .exhausted: []
        case .loaded(let cards), .allDone(let cards), .degraded(let cards, reason: _): cards
        }
    }
}
