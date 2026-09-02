// MinesweeperBoardView+Completion — completion CTA-hierarchy resolution
// (#1023). Extracted to a sibling file (repo convention: `+Feature.swift`
// rather than growing `MinesweeperBoardView.swift`, which already disables
// SwiftLint's `file_length` — new logic still gets its own file).
//
// Mirrors Sudoku's `BoardView+Completion.completionContext` / `DailyCompletionProgress`.

import SwiftUI
import GameShellUI
import MinesweeperEngine

// MARK: - Daily "more today?" resolution

/// Resolved once per Daily WIN via `MinesweeperBoardView.fetchDailyProgress`,
/// mirrors `SudokuUI.DailyCompletionProgress`.
public enum MinesweeperDailyCompletionProgress: Sendable, Equatable {
    /// Another difficulty is still open today.
    case moreToday(entry: MinesweeperDailyEntry)
    /// Nothing left to play today.
    case allDone
}

extension MinesweeperBoardView {
    /// §3.5's 4-row CTA table, minus the Daily/Practice-only rows that don't
    /// apply on a loss. A loss ALWAYS gets `.loss` (Try Again / Close),
    /// regardless of mode — MS's loss row is mode-agnostic (§3.5 doesn't
    /// split "MS 失敗" by Daily vs Practice). A WIN picks `.dailyMoreToday`/
    /// `.dailyAllDone` (Daily) from `dailyCompletionProgress`, or `.practice`
    /// (Practice), forwarding `onPlayAgain` unchanged (nil when no presenter
    /// is wired, same fallback as before #1023).
    func completionContext(
        closeAction: @escaping () -> Void,
        difficulty: Difficulty,
        didWin: Bool
    ) -> CompletionContext {
        guard didWin else {
            return .loss(onTryAgain: onPlayAgain.map { playAgain in
                {
                    closeAction()
                    playAgain(difficulty)
                }
            })
        }
        guard mode == .daily else {
            return .practice(onPlayAgain: onPlayAgain.map { playAgain in
                {
                    closeAction()
                    playAgain(difficulty)
                }
            })
        }
        switch dailyCompletionProgress {
        case .moreToday(let entry):
            guard let onDailyNext else { return .dailyAllDone }
            return .dailyMoreToday(
                nextDifficultyLabel: LocalizedStringKey(entry.difficulty.rawValue.capitalized),
                onNext: {
                    closeAction()
                    onDailyNext(entry)
                }
            )
        case .allDone:
            return .dailyAllDone
        }
    }
}
