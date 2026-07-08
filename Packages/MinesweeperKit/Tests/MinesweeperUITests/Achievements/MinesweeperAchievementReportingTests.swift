// swiftlint:disable identifier_name
//
// MinesweeperAchievementReportingTests — ViewModel wiring for #700's
// `evaluateAchievementsIfWon()`: drives a real win and asserts the correct
// prefixed achievements are reported, that a practice win still reports the
// mode-agnostic achievements, and that a thrown `reportAchievement` error is
// swallowed without breaking gameplay (mirrors
// MinesweeperGameCenterSubmitTests' submit-error-swallowed precedent).

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState
import GameCenterClient
import GameCenterTesting

@MainActor
@Suite("MinesweeperGameViewModel — achievement reporting (#700)")
struct MinesweeperAchievementReportingTests {

    /// Same drive-to-win helper as MinesweeperGameCenterSubmitTests (kept
    /// file-local — small enough that sharing isn't worth a new target).
    private func driveToWin(_ vm: MinesweeperGameViewModel) async {
        await vm.reveal(row: 0, col: 0)
        var progressed = true
        while vm.status == .playing && progressed {
            progressed = false
            for r in 0..<vm.rows {
                for c in 0..<vm.columns {
                    let cell = vm.cell(row: r, col: c)
                    if !cell.isMine && cell.state != .revealed {
                        await vm.reveal(row: r, col: c)
                        progressed = true
                        if vm.status != .playing { return }
                    }
                }
            }
        }
    }

    private func ephemeralWinCountStore() -> MinesweeperWinCountStore {
        // swiftlint:disable:next force_unwrapping
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        return MinesweeperWinCountStore(defaults: defaults)
    }

    private func reportedAchievements(_ ops: [FakeGameCenterOperation]) -> [(id: String, percent: Double)] {
        ops.compactMap { op in
            if case let .reportAchievement(id, percent) = op { return (id, percent) }
            return nil
        }
    }

    @Test("A practice win reports mode-agnostic achievements (first sweep, volume, no-flags) but no daily-only ones")
    func practiceWinReportsModeAgnosticAchievements() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            gameCenter: fake,
            winCountStore: ephemeralWinCountStore()
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let reported = reportedAchievements(await fake.operations)
        let ids = Set(reported.map(\.id))
        #expect(ids.contains("com.wei18.minesweeper.achievement.first_sweep"))
        #expect(ids.contains("com.wei18.minesweeper.achievement.wins.complete_10"))
        #expect(ids.contains("com.wei18.minesweeper.achievement.wins.complete_50"))
        #expect(ids.contains("com.wei18.minesweeper.achievement.wins.complete_200"))
        #expect(ids.contains("com.wei18.minesweeper.achievement.skill.no_flags"))
        // Daily-only achievements must never fire for a practice win.
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.complete_one"))
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.full_spectrum"))
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.streak_7"))
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.streak_30"))
        // First win: 1/10 volume progress.
        let volume10 = reported.first { $0.id == "com.wei18.minesweeper.achievement.wins.complete_10" }
        #expect(volume10?.percent == 10)
    }

    @Test("A daily win reports Daily Debut in addition to the mode-agnostic set")
    func dailyWinReportsDailyDebut() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .daily,
            gameCenter: fake,
            winCountStore: ephemeralWinCountStore()
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let ids = Set(reportedAchievements(await fake.operations).map(\.id))
        #expect(ids.contains("com.wei18.minesweeper.achievement.daily.complete_one"))
        #expect(ids.contains("com.wei18.minesweeper.achievement.first_sweep"))
        // No personalRecordStore wired → full-spectrum/streak facts stay empty/0.
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.full_spectrum"))
        #expect(!ids.contains("com.wei18.minesweeper.achievement.daily.streak_7"))
    }

    @Test("Expert difficulty additionally reports Expert Cleared (and Lightning Sweep if fast enough)")
    func expertWinReportsExpertCleared() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .expert,
            seed: 7,
            mode: .practice,
            gameCenter: fake,
            winCountStore: ephemeralWinCountStore()
        )

        await driveToWin(vm)
        #expect(vm.status == .won)

        let ids = Set(reportedAchievements(await fake.operations).map(\.id))
        #expect(ids.contains("com.wei18.minesweeper.achievement.expert.first_win"))
    }

    @Test("Placing a flag, even if later removed, disqualifies No Flags Needed")
    func flagPlacedThenRemovedStillDisqualifies() async {
        let fake = FakeGameCenterClient()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            gameCenter: fake,
            winCountStore: ephemeralWinCountStore()
        )

        // Seed mines via the first reveal, then place-and-remove a flag on an
        // untouched cell before sweeping the rest.
        await vm.reveal(row: 0, col: 0)
        var flagTarget: (Int, Int)?
        outer: for r in 0..<vm.rows {
            for c in 0..<vm.columns {
                let cell = vm.cell(row: r, col: c)
                if !cell.isMine && cell.state != .revealed {
                    flagTarget = (r, c)
                    break outer
                }
            }
        }
        if let (r, c) = flagTarget {
            await vm.toggleFlag(row: r, col: c)
            await vm.toggleFlag(row: r, col: c)
        }

        await driveToWin(vm)
        #expect(vm.status == .won)

        let ids = Set(reportedAchievements(await fake.operations).map(\.id))
        #expect(!ids.contains("com.wei18.minesweeper.achievement.skill.no_flags"))
    }

    @Test("A thrown reportAchievement error is swallowed and does not break the win")
    func reportAchievementErrorIsSwallowed() async {
        let fake = FakeGameCenterClient()
        await fake.setReportAchievementError(.achievementReportFailed(reason: "network down"))
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            gameCenter: fake,
            winCountStore: ephemeralWinCountStore()
        )

        await driveToWin(vm)

        #expect(vm.status == .won)
        // Every achievement the evaluator emitted was still ATTEMPTED (the
        // error is thrown *after* the fake records the op), matching
        // submitScore's swallow-but-attempt-once posture.
        let reported = reportedAchievements(await fake.operations)
        #expect(reported.count == 5) // firstSweep + 3 volume + noFlags (beginner, practice)
    }

    @Test("Refreshing the already-won board neither re-reports nor inflates the win tally")
    func doesNotDoubleReportOnRepublish() async {
        let fake = FakeGameCenterClient()
        let store = ephemeralWinCountStore()
        let vm = MinesweeperGameViewModel(
            difficulty: .beginner,
            seed: 42,
            mode: .practice,
            gameCenter: fake,
            winCountStore: store
        )
        await driveToWin(vm)
        #expect(vm.status == .won)
        let firstCount = reportedAchievements(await fake.operations).count
        #expect(store.currentCount == 1)

        // A refresh() after the win re-fetches the (still-won) snapshot.
        // Evaluation only runs on the live reveal() transition (#700): the
        // cumulative tally must not inflate on a refresh over a won board.
        await vm.refresh()
        let secondCount = reportedAchievements(await fake.operations).count
        #expect(secondCount == firstCount)
        #expect(store.currentCount == 1)
    }
}

// swiftlint:enable identifier_name
