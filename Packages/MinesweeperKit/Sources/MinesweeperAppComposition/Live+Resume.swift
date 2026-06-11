// Live+Resume — #455 step 4 resume-seam wiring for `.live()`.
//
// Split out of Live.swift (which sits at the swiftlint file_length budget,
// same precedent as Live+Audio.swift). Builds the `fetchResume` closure the
// shared `GameRootViewModel` (#460) consumes: latest in-progress save →
// game-agnostic `ResumeCandidate<AppRoute>` → Home resume pill → the
// `.resumeBoard` route restores the exact board.

internal import Foundation
internal import GameAppKit
internal import MinesweeperPersistence
internal import MinesweeperUI

extension MinesweeperAppComposition {

    /// `fetchResume` for `GameRootViewModel<AppRoute>`. Throws propagate —
    /// the VM owns the error funnel (`GameRootViewModel.bootstrap.resume`)
    /// and degrades to no pill. The store already filters stale dailies.
    static func makeFetchResume(
        store: MinesweeperSavedGameStore
    ) -> () async throws -> ResumeCandidate<AppRoute>? {
        {
            guard let summary = try await store.latestInProgress() else { return nil }
            return ResumeCandidate(
                title: "Resume \(summary.difficulty.rawValue.capitalized)",
                subtitle: elapsed(summary.elapsedSeconds),
                route: .resumeBoard(
                    recordName: summary.recordName,
                    // Unknown wire value (a future mode?) degrades to the
                    // cautious default — practice never submits to GC (#329).
                    mode: GameMode(rawValue: summary.modeRaw) ?? .practice
                )
            )
        }
    }

    /// `"%d:%02d"` — mirrors Sudoku's `AppComposition.elapsed` (the exact
    /// string the pre-#460 shared ResumePill rendered).
    static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
