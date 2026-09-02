// MinesweeperTodayMapperTests — pure unit coverage for
// `MinesweeperTodayMapper` (#1021 Phase B). No rendering, no CloudKit.

import Foundation
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
internal import GameShellUI

@Suite("MinesweeperTodayMapper (#1021 Phase B)")
struct MinesweeperTodayMapperTests {

    private static func card(
        id: String = "fixture",
        difficulty: Difficulty = .beginner,
        isCompleted: Bool = false,
        isFailed: Bool = false,
        bestTimeSeconds: Int? = nil
    ) -> MinesweeperDailyCard {
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: id, difficulty: difficulty, seed: 1),
            isCompleted: isCompleted,
            isFailed: isFailed,
            bestTimeSeconds: bestTimeSeconds
        )
    }

    // MARK: - `present` — the 3 reachable `MinesweeperDailyHubState` outputs

    @Test func idleMapsToLoading() {
        let result = MinesweeperTodayMapper.present(state: .idle, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func loadingMapsToLoading() {
        let result = MinesweeperTodayMapper.present(state: .loading, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func loadedWithMixedStatesStaysLoaded() {
        let cards = [
            Self.card(id: "a", isCompleted: false),
            Self.card(id: "b", isCompleted: true, bestTimeSeconds: 24),
            Self.card(id: "c", isFailed: true)
        ]
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), isPhase2Degraded: false)
        guard case .loaded(let models) = result else { Issue.record("expected .loaded, got \(result)"); return }
        #expect(models.count == 3)
        #expect(models[1].isCompleted)
        #expect(models[2].statusText == "Failed")
    }

    @Test func loadedWithAllCompletedBecomesAllDone() {
        let cards = (0..<3).map { Self.card(id: "\($0)", isCompleted: true, bestTimeSeconds: 60) }
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), isPhase2Degraded: false)
        guard case .allDone(let models) = result else { Issue.record("expected .allDone, got \(result)"); return }
        #expect(models.allSatisfy { $0.isCompleted })
    }

    @Test func loadedWithPhase2DegradedForcesEveryCardNotStartedWithRealThumbnails() {
        let cards = [
            Self.card(id: "a", isCompleted: true, bestTimeSeconds: 60),
            Self.card(id: "b", isFailed: true),
            Self.card(id: "c")
        ]
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), isPhase2Degraded: true)
        guard case .degraded(let models) = result else { Issue.record("expected .degraded, got \(result)"); return }
        #expect(models.allSatisfy { !$0.isCompleted })
        #expect(models.allSatisfy { !$0.isSkeleton && $0.preview != nil })
        #expect(models.allSatisfy { $0.statusText.contains("Not started") })
    }

    /// D21 (design.md §3.1): MS's daily generation is pure and non-throwing,
    /// so `.exhausted` is structurally unreachable — `MinesweeperDailyHubState`
    /// has no such case, and `present`'s switch has no default branch (an
    /// exhaustive switch over exactly `.idle`/`.loading`/`.loaded`), so a new
    /// case would fail to COMPILE here rather than silently falling through
    /// to an `.exhausted` branch that doesn't exist. This test iterates every
    /// reachable state × degraded-flag combination and asserts the RESULT is
    /// never `.exhausted` as a runtime double-check of that structural fact.
    @Test func neverProducesExhausted() {
        let states: [MinesweeperDailyHubState] = [
            .idle,
            .loading,
            .loaded([]),
            .loaded([Self.card(isCompleted: true)]),
            .loaded([Self.card(isFailed: true)])
        ]
        for state in states {
            for isDegraded in [false, true] {
                let result = MinesweeperTodayMapper.present(state: state, isPhase2Degraded: isDegraded)
                if case .exhausted = result {
                    Issue.record("MinesweeperTodayMapper.present produced .exhausted for \(state)/\(isDegraded)")
                }
            }
        }
    }

    // MARK: - Status text + thumbnail rules (spec B/C, incl. the documented deviation)

    @Test func completedWithBestTimeShowsSolvedAndTime() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(isCompleted: true, bestTimeSeconds: 192)]),
            isPhase2Degraded: false
        )
        #expect(result.cards[0].statusText == "Solved · 3:12")
    }

    @Test func failedShowsFailedStatus() {
        let result = MinesweeperTodayMapper.present(state: .loaded([Self.card(isFailed: true)]), isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "Failed")
    }

    @Test func notStartedShowsDimensionsAndMineCount() {
        let result = MinesweeperTodayMapper.present(state: .loaded([Self.card(difficulty: .expert)]), isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "Not started · 16 × 30 · 99 mines")
    }

    /// Deviation coverage: solved/failed thumbnails are a UNIFORM `.filled`
    /// board at the difficulty's true dimensions (no seed-only mine layout
    /// exists without a first click — see `MinesweeperTodayMapper`'s file
    /// header). Not-started is uniform `.empty`.
    @Test func solvedThumbnailIsUniformFilledAtTrueDimensions() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(difficulty: .intermediate, isCompleted: true, bestTimeSeconds: 1)]),
            isPhase2Degraded: false
        )
        let preview = result.cards[0].preview
        #expect(preview?.columns == Difficulty.intermediate.columns)
        #expect(preview?.rows == Difficulty.intermediate.rows)
        #expect(preview?.cells.allSatisfy { $0 == .filled } == true)
    }

    @Test func notStartedThumbnailIsUniformEmptyAtTrueDimensions() {
        let result = MinesweeperTodayMapper.present(state: .loaded([Self.card(difficulty: .beginner)]), isPhase2Degraded: false)
        let preview = result.cards[0].preview
        #expect(preview?.columns == Difficulty.beginner.columns)
        #expect(preview?.cells.allSatisfy { $0 == .empty } == true)
    }

    @Test func completedCardCarriesTheCompletedAccessibilityIdentifier() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(isCompleted: true), Self.card(id: "b")]),
            isPhase2Degraded: false
        )
        #expect(result.cards[0].accessibilityIdentifier == "minesweeper.dailyHub.card.completed")
        #expect(result.cards[1].accessibilityIdentifier == nil)
    }
}
