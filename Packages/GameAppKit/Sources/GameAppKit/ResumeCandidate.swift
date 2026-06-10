// ResumeCandidate — game-agnostic resume DTO at the GameAppKit seam (#455).
//
// The Home "Resume" pill only needs a label + a destination; that is
// genuinely game-agnostic. Each game maps its per-game persisted state (e.g.
// Sudoku's `SavedGameSummary`) into this DTO inside its own `fetchResume`
// closure, so `GameRootViewModel` is no longer coupled to any Sudoku-typed
// persistence surface. See docs/superpowers/specs/2026-06-10-resume-seam-design.md.
//
// `Route: Hashable & Sendable` so the unconditional `Sendable` conformance
// compiles; both apps' `AppRoute` are value-type enums and already satisfy it.

public struct ResumeCandidate<Route: Hashable & Sendable>: Sendable, Equatable {
    /// Game-mapped, e.g. "Resume Beginner" / "Resume Easy".
    public let title: String
    /// e.g. "3:42".
    public let subtitle: String
    /// Where tapping the pill navigates.
    public let route: Route

    public init(title: String, subtitle: String, route: Route) {
        self.title = title
        self.subtitle = subtitle
        self.route = route
    }
}
