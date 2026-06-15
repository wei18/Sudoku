// Live+Resume — M4 resume-seam wiring for Game2048AppComposition.live().
//
// Split out of Live.swift (file_length 400 budget; same precedent as
// MinesweeperAppComposition/Live+Resume.swift). Builds the `fetchResume`
// closure the shared `GameRootViewModel` consumes: latest in-progress save →
// game-agnostic `ResumeCandidate<AppRoute>` → Home resume pill → the
// `.resumeBoard` route restores the exact board.

internal import Foundation
internal import GameAppKit
internal import Game2048Persistence
internal import Game2048UI

extension Game2048AppComposition {

    /// `fetchResume` for `GameRootViewModel<AppRoute>`. Throws propagate —
    /// the VM owns the error funnel and degrades to no pill. The store already
    /// filters stale dailies (record names dated yesterday are skipped).
    static func makeFetchResume(
        store: Game2048SavedGameStore
    ) -> () async throws -> ResumeCandidate<AppRoute>? {
        {
            guard let summary = try await store.latestInProgress() else { return nil }
            let mode = GameMode(rawValue: summary.modeRaw) ?? .practice
            return ResumeCandidate(
                title: "Resume \(mode == .daily ? "Daily" : "Classic")",
                subtitle: elapsed(summary.elapsedSeconds),
                route: .resumeBoard(recordName: summary.recordName, mode: mode)
            )
        }
    }

    /// `"%d:%02d"` — mirrors MinesweeperAppComposition.elapsed (the string
    /// the pre-#460 shared ResumePill rendered).
    static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
