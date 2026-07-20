// DailyHubViewModel+Testing — test-only seams, split out purely to keep
// DailyHubViewModel.swift under the 400-line `file_length` lint ceiling
// (same rationale as `DailyHubViewModel+BestTime.swift`). `isPhase2Pending`
// is `internal` on the main class specifically so this file can write it.
// #905: this whole extension is `internal`, not `public` — it is reachable
// only via `@testable import SudokuUI` (every consumer is an in-package
// test target), never from a normal `import SudokuUI`.

extension DailyHubViewModel {

    /// #878 (#874 F-4, re-opening #842's "deliberately not visual"
    /// tradeoff): seeds `isPhase2Pending` directly for previews / snapshot
    /// tests that want to pin the phase-2-pending card treatment
    /// (`DailyPuzzleCard`'s dim + dropped `.isButton` trait) without
    /// standing up a gated fetch fixture. Production never calls this — the
    /// real toggle inside `fillCompletionOverlay` is untouched.
    func setPhase2PendingForTesting(_ isPending: Bool) {
        self.isPhase2Pending = isPending
    }
}
