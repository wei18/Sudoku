// MinesweeperReminderPrimerGatingTests — #814 daily-WIN-only gate for the
// completion reminder primer affordance.
//
// The rule lives in `MinesweeperBoardView.shouldOfferReminderPrimer(mode:didWin:)`
// (a nonisolated static, extracted as a test seam per the `tapModeStore`
// precedent, #796): the primer is a retention hook for the DAILY habit, so a
// Practice game (no "tomorrow's boards" moment) and a loss (wrong tone for a
// retention ask) must never offer it. Sudoku's equivalent gate is
// `SudokuLeaderboardRouting.isDaily` — daily-only by construction, since a
// Sudoku completion is always a solve; MS adds the explicit win leg because
// its terminal state can be a loss.

import Testing
@testable import MinesweeperUI

@Suite("Reminder primer gating (#814) — daily win only")
struct MinesweeperReminderPrimerGatingTests {

    @Test("a daily WIN offers the primer")
    func dailyWinOffers() {
        #expect(MinesweeperBoardView.shouldOfferReminderPrimer(mode: .daily, didWin: true))
    }

    @Test("a daily LOSS never offers the primer")
    func dailyLossDoesNot() {
        #expect(!MinesweeperBoardView.shouldOfferReminderPrimer(mode: .daily, didWin: false))
    }

    @Test("a practice win never offers the primer")
    func practiceWinDoesNot() {
        #expect(!MinesweeperBoardView.shouldOfferReminderPrimer(mode: .practice, didWin: true))
    }

    @Test("a practice loss never offers the primer")
    func practiceLossDoesNot() {
        #expect(!MinesweeperBoardView.shouldOfferReminderPrimer(mode: .practice, didWin: false))
    }
}
