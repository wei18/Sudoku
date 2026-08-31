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
//
// `boardPreview` (#1017): a game-agnostic `BoardPreview?` built by each app's
// own `fetchResume` closure from its already-fetched saved payload
// (Sudoku's `boardState`, MS's `stateBlob`) — see design.md §3.6's ⚠️ 型別
// constraint. `ResumeCandidate` may depend on `GameShellUI` (it already
// depends on Persistence-shaped per-app data); `GameShellUI` itself stays
// zero-dependency and never sees this type. `nil` when the payload is
// missing or fails to parse — the pill still renders text-only (design.md
// §3.6, degrade rule).

public import GameShellUI

public struct ResumeCandidate<Route: Hashable & Sendable>: Sendable, Equatable {
    /// Game-mapped, e.g. "Resume Beginner" / "Resume Easy".
    public let title: String
    /// e.g. "3:42".
    public let subtitle: String
    /// Where tapping the pill navigates.
    public let route: Route
    /// Board snapshot for a thumbnail (#1021's rendering job, not this
    /// type's). `nil` when the per-app mapper couldn't build one.
    public let boardPreview: BoardPreview?

    public init(title: String, subtitle: String, route: Route, boardPreview: BoardPreview? = nil) {
        self.title = title
        self.subtitle = subtitle
        self.route = route
        self.boardPreview = boardPreview
    }
}
