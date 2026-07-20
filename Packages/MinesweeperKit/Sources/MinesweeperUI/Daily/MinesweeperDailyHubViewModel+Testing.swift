// MinesweeperDailyHubViewModel+Testing — test-only seams, split out to
// mirror `SudokuUI.DailyHubViewModel+Testing`'s shape (#905). `state`,
// `weekStrip`, `isPhase2Pending`, and `hasBootstrapped` are `internal`/
// `internal(set)` on the main class specifically so this file can write
// them. #905: this whole extension is `internal`, not `public` — it is
// reachable only via `@testable import MinesweeperUI` (every consumer is an
// in-package test target), never from a normal `import MinesweeperUI`.

extension MinesweeperDailyHubViewModel {

    /// Seed state for previews / snapshot tests that bypass the async fetch.
    /// Latches `hasBootstrapped` so the view's `.task { bootstrap() }` becomes a
    /// no-op and the seeded state survives `NSHostingView` capture — mirrors
    /// `MinesweeperCompletionViewModel.setStateForTesting`. Production never
    /// calls this; the live `bootstrap()` path is untouched.
    func setStateForTesting(_ state: MinesweeperDailyHubState) {
        self.state = state
        self.hasBootstrapped = true
    }

    /// #774: seed the week strip for previews / snapshot tests, mirroring
    /// `setStateForTesting` (which latches `hasBootstrapped`, so the view's
    /// `.task { bootstrap() }` can't overwrite this either). Production never
    /// calls this; the live `fillCompletionAndFailureOverlay` path is untouched.
    func setWeekStripForTesting(_ snapshot: MinesweeperDailyStripSnapshot) {
        self.weekStrip = snapshot
    }

    /// #878 (#874 F-4, re-opening #842's no-affordance tradeoff): seeds
    /// `isPhase2Pending` directly for previews / snapshot tests, mirroring
    /// `SudokuUI.DailyHubViewModel.setPhase2PendingForTesting`. Needed
    /// because `setStateForTesting` above bypasses `bootstrap()` entirely
    /// and leaves `isPhase2Pending` at its default `true` — every existing
    /// snapshot/ASC-screenshot fixture built via `setStateForTesting` now
    /// calls this with `false` to keep representing the SETTLED loaded
    /// state, not a mid-fetch one. Production never calls this.
    func setPhase2PendingForTesting(_ isPending: Bool) {
        self.isPhase2Pending = isPending
    }
}
