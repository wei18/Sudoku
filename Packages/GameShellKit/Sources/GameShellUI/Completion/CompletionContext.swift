// CompletionContext — the completion panel's CTA hierarchy (#1023 /
// docs/designs/v3/design.md §3.5's 4-row table). Exactly one case per row:
// which primary/secondary buttons `CompletionOverlayScaffold` renders is a
// pure function of this value, independent of `CompletionVariant` (variant
// controls ritual/haptic, this controls what the buttons say and do — a
// `review` re-view of a Daily-all-done result still shows "See you tomorrow",
// it just doesn't replay the ritual to get there).
//
// `dailyAllDone`'s reminder opt-in is NOT rendered here — it's the existing
// per-card `reminderPrimer` footer content (SudokuKit/MinesweeperKit's own
// `CompletionView`/`MinesweeperCompletionView`), unchanged by this issue.
// "See you tomorrow" is the ONE value-toned CTA in the entire flow (§3.5) —
// its action is the same as Close (there is nothing else to do), so no
// separate onClose-vs-primary distinction is needed for that case.
public import SwiftUI

public enum CompletionContext {
    /// Daily solved, at least one other difficulty is still open today.
    /// Primary "Next: <difficulty>" advances; secondary "Done" closes. Only
    /// ever constructed when the call site has a real presenter for the next
    /// puzzle — when it doesn't (or "more today" hasn't been resolved yet),
    /// the call site falls back to `.dailyAllDone` instead of passing a
    /// dead closure here.
    case dailyMoreToday(nextDifficultyLabel: LocalizedStringKey, onNext: () -> Void)
    /// Daily solved, nothing left to play today. Primary "See you tomorrow"
    /// closes — the flow's one value-toned CTA (§3.5). No secondary button;
    /// the reminder opt-in (when unauthorized) is the existing card footer.
    case dailyAllDone
    /// Practice solved. `nil` (no presenter wired at this call site — e.g. a
    /// `review` re-view) renders Close-only, preserving the pre-#1023
    /// single-button layout; non-nil renders "Play Again" above "Close".
    case practice(onPlayAgain: (() -> Void)?)
    /// MS loss. `nil` renders Close-only (same fallback as `.practice`);
    /// non-nil renders "Try Again" above "Close".
    case loss(onTryAgain: (() -> Void)?)
}
