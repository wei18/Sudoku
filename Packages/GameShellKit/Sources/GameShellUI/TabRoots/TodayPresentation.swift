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
    /// CloudKit completion status is unknown; thumbnails still render
    /// (seed-derived, no CK dependency) but every card must be drawn as
    /// "not started" — the caller building `[Card]` is responsible for that
    /// degrade, not this enum.
    case degraded([Card])
    /// Sudoku only — no more daily puzzles left to generate for a stretch.
    case exhausted

    public var cards: [Card] {
        switch self {
        case .loading, .exhausted: []
        case .loaded(let cards), .allDone(let cards), .degraded(let cards): cards
        }
    }
}
