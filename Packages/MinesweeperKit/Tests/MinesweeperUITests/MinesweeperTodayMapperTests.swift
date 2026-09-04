// MinesweeperTodayMapperTests — pure unit coverage for
// `MinesweeperTodayMapper` (#1021 Phase B). No rendering, no CloudKit.

import Foundation
import Testing
@testable import MinesweeperUI

import MinesweeperEngine
import MinesweeperPersistence
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

    private static func summary(
        recordName: String,
        difficulty: Difficulty = .beginner,
        elapsedSeconds: Int = 0,
        stateBlob: Data? = nil
    ) -> MinesweeperSavedGameSummary {
        MinesweeperSavedGameSummary(
            recordName: recordName,
            difficulty: difficulty,
            seed: 1,
            modeRaw: "daily",
            elapsedSeconds: elapsedSeconds,
            lastModifiedAt: Date(),
            status: "inProgress",
            stateBlob: stateBlob
        )
    }

    // MARK: - `present` — the 3 reachable `MinesweeperDailyHubState` outputs

    @Test func idleMapsToLoading() {
        let result = MinesweeperTodayMapper.present(state: .idle, inProgress: nil, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func loadingMapsToLoading() {
        let result = MinesweeperTodayMapper.present(state: .loading, inProgress: nil, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func loadedWithMixedStatesStaysLoaded() {
        let cards = [
            Self.card(id: "a", isCompleted: false),
            Self.card(id: "b", isCompleted: true, bestTimeSeconds: 24),
            Self.card(id: "c", isFailed: true)
        ]
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        guard case .loaded(let models) = result else { Issue.record("expected .loaded, got \(result)"); return }
        #expect(models.count == 3)
        #expect(models[1].isCompleted)
        #expect(models[2].statusText == "Failed")
    }

    @Test func loadedWithAllCompletedBecomesAllDone() {
        let cards = (0..<3).map { Self.card(id: "\($0)", isCompleted: true, bestTimeSeconds: 60) }
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        guard case .allDone(let models) = result else { Issue.record("expected .allDone, got \(result)"); return }
        #expect(models.allSatisfy { $0.isCompleted })
    }

    /// #1021 CR3: MS's only reachable degrade is the phase-2 overlay fetch —
    /// must map to `.completionStatusUnknown` (silent), never `.loadFailed`
    /// (unreachable here — see `neverProducesLoadFailed` below).
    @Test func loadedWithPhase2DegradedForcesEveryCardNotStartedWithRealThumbnails() {
        let cards = [
            Self.card(id: "a", isCompleted: true, bestTimeSeconds: 60),
            Self.card(id: "b", isFailed: true),
            Self.card(id: "c")
        ]
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: true)
        guard case .degraded(let models, let reason) = result else { Issue.record("expected .degraded, got \(result)"); return }
        #expect(reason == .completionStatusUnknown)
        #expect(models.allSatisfy { !$0.isCompleted })
        #expect(models.allSatisfy { !$0.isSkeleton && $0.preview != nil })
        #expect(models.allSatisfy { $0.statusText.contains("Not started") })
    }

    /// #1021 CR3: `TodayPresentation.DegradedReason.loadFailed` is
    /// CONSTRUCTIBLE (it's a shared GameShellKit type — `Sudoku.TodayMapper`
    /// builds one for its own phase-1 failure), but structurally unreachable
    /// FROM THIS MAPPER: `present`'s only `.degraded` branch above is the
    /// phase-2 overlay fetch, which always passes `.completionStatusUnknown`
    /// — there is no MS state/flag combination that reaches `.loadFailed`
    /// (D21 — `dailyTrio(date:)` is synchronous and non-throwing, so MS has
    /// no phase-1 failure to represent). Mirrors `neverProducesExhausted`'s
    /// shape as a runtime double-check of that structural fact.
    @Test func neverProducesLoadFailed() {
        let states: [MinesweeperDailyHubState] = [
            .idle,
            .loading,
            .loaded([]),
            .loaded([Self.card(isCompleted: true)]),
            .loaded([Self.card(isFailed: true)])
        ]
        for state in states {
            for isDegraded in [false, true] {
                let result = MinesweeperTodayMapper.present(state: state, inProgress: nil, isPhase2Degraded: isDegraded)
                if case .degraded(_, let reason) = result {
                    #expect(reason == .completionStatusUnknown, "unexpected .loadFailed for \(state)/\(isDegraded)")
                }
            }
        }
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
                let result = MinesweeperTodayMapper.present(state: state, inProgress: nil, isPhase2Degraded: isDegraded)
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
            inProgress: nil,
            isPhase2Degraded: false
        )
        #expect(result.cards[0].statusText == "Solved · 3:12")
    }

    @Test func failedShowsFailedStatus() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(isFailed: true)]),
            inProgress: nil,
            isPhase2Degraded: false
        )
        #expect(result.cards[0].statusText == "Failed")
    }

    @Test func notStartedShowsDimensionsAndMineCount() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(difficulty: .expert)]),
            inProgress: nil,
            isPhase2Degraded: false
        )
        #expect(result.cards[0].statusText == "Not started · 16 × 30 · 99 mines")
    }

    // MARK: - In-progress card (#1021 Phase B ruling 2)

    @Test func inProgressMatchingRecordNameShowsElapsedTime() {
        let cards = [Self.card(id: "daily-2026-01-01-beginner")]
        let inProgress = Self.summary(recordName: "daily-2026-01-01-beginner", elapsedSeconds: 65)
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), inProgress: inProgress, isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "In progress · 1:05")
        // No decodable stateBlob → falls back to the not-started (empty) render, not nil.
        #expect(result.cards[0].preview != nil)
    }

    @Test func inProgressNotMatchingAnyCardIsIgnored() {
        let cards = [Self.card(id: "daily-2026-01-01-beginner")]
        let inProgress = Self.summary(recordName: "daily-2026-01-01-intermediate", elapsedSeconds: 65)
        let result = MinesweeperTodayMapper.present(state: .loaded(cards), inProgress: inProgress, isPhase2Degraded: false)
        #expect(!result.cards[0].statusText.contains("In progress"))
    }

    @Test func inProgressNeverShowsOnACompletedOrFailedCard() {
        let cards = [
            Self.card(id: "a", isCompleted: true, bestTimeSeconds: 10),
            Self.card(id: "b", isFailed: true)
        ]
        let result = MinesweeperTodayMapper.present(
            state: .loaded(cards),
            inProgress: Self.summary(recordName: "a"),
            isPhase2Degraded: false
        )
        #expect(!result.cards[0].statusText.contains("In progress"))
        #expect(!result.cards[1].statusText.contains("In progress"))
    }

    /// Deviation coverage: solved/failed thumbnails are a UNIFORM `.filled`
    /// board at the difficulty's true dimensions (no seed-only mine layout
    /// exists without a first click — see `MinesweeperTodayMapper`'s file
    /// header). Not-started is uniform `.empty`.
    @Test func solvedThumbnailIsUniformFilledAtTrueDimensions() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(difficulty: .intermediate, isCompleted: true, bestTimeSeconds: 1)]),
            inProgress: nil,
            isPhase2Degraded: false
        )
        let preview = result.cards[0].preview
        #expect(preview?.columns == Difficulty.intermediate.columns)
        #expect(preview?.rows == Difficulty.intermediate.rows)
        #expect(preview?.cells.allSatisfy { $0 == CellMark.filled } == true)
    }

    @Test func notStartedThumbnailIsUniformEmptyAtTrueDimensions() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(difficulty: .beginner)]),
            inProgress: nil,
            isPhase2Degraded: false
        )
        let preview = result.cards[0].preview
        #expect(preview?.columns == Difficulty.beginner.columns)
        #expect(preview?.cells.allSatisfy { $0 == CellMark.empty } == true)
    }

    @Test func completedCardCarriesTheCompletedAccessibilityIdentifier() {
        let result = MinesweeperTodayMapper.present(
            state: .loaded([Self.card(isCompleted: true), Self.card(id: "b")]),
            inProgress: nil,
            isPhase2Degraded: false
        )
        #expect(result.cards[0].accessibilityIdentifier == "minesweeper.dailyHub.card.completed")
        #expect(result.cards[1].accessibilityIdentifier == nil)
    }

    // MARK: - Loading skeleton (Leader ruling 1)

    @Test func skeletonCardsCarryPerDifficultyDimensions() {
        let skeletons = MinesweeperTodayMapper.skeletonCards()
        #expect(skeletons.count == 3)
        #expect(skeletons.allSatisfy { $0.isSkeleton })
        let dims = zip(skeletons, MinesweeperDaily.dailyDifficulties).allSatisfy { model, difficulty in
            model.preview?.columns == difficulty.columns && model.preview?.rows == difficulty.rows
        }
        #expect(dims)
    }
}
