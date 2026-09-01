// CompletionVariant — which behavioral flavor of the completion panel is
// showing (#1023 / docs/designs/v3/design.md §3.5).
//
// There are 4 production paths that all render the same shared completion
// card, but only ONE of them (the live overlay, right after a fresh solve) is
// allowed to play the win ritual + fire a haptic. The other 3 are re-showing
// an ALREADY-completed result — playing the ritual there would be a false
// report of a fresh accomplishment ("謊報", design.md §3.5). `CompletionVariant`
// is the single value every call site sets correctly to prevent that:
//   - `.liveSolve` — the in-board overlay, right after the solve/loss that
//     just happened. Plays the full ritual on a win (`CompletionMotionPlan`);
//     an MS loss also uses this variant (it's still "live"), it just doesn't
//     qualify for the WIN ritual (see `CompletionMotionPlan.plan`).
//   - `.review` — the pushed `.completion` re-view route, Sudoku's
//     `BoardLoaderView.completedRedirect`, and MS's
//     `MinesweeperDailyOpenGuardView.resolved(.completed)`. No ritual, no
//     haptic, panel does not "rise" (M10 skipped) — see `CompletionMotionPlan`.
public enum CompletionVariant: Sendable, Equatable {
    case liveSolve
    case review
}
