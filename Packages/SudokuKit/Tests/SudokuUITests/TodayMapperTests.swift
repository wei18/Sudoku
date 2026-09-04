// TodayMapperTests — pure unit coverage for `TodayMapper` (#1021 Phase B).
// No rendering, no CloudKit — every input is hand-built.

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import SudokuEngine
import SudokuKitTesting
import SudokuPersistence
internal import GameShellUI

@Suite("TodayMapper (#1021 Phase B)")
struct TodayMapperTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private static func trio() -> [DailyCard] {
        FakePuzzleProvider.defaultDailyTrio(date: fixedDate).map { DailyCard(envelope: $0, isCompleted: false) }
    }

    // MARK: - `present` — all 5 `DailyHubState` outputs

    @Test func idleMapsToLoading() {
        let result = TodayMapper.present(state: .idle, inProgress: nil, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func loadingMapsToLoading() {
        let result = TodayMapper.present(state: .loading, inProgress: nil, isPhase2Degraded: false)
        guard case .loading = result else { Issue.record("expected .loading, got \(result)"); return }
    }

    @Test func exhaustedMapsToExhausted() {
        let result = TodayMapper.present(state: .exhausted, inProgress: nil, isPhase2Degraded: false)
        guard case .exhausted = result else { Issue.record("expected .exhausted, got \(result)"); return }
    }

    /// #1021 CR2 M7: this mapping used to be dead — `DailyHubView` lifted
    /// `.failed` straight to the shell's failure overlay, so `.present`'s
    /// `.degraded` output here never actually rendered. Now
    /// `DailyHubView.loadingCards` reads `TodayMapper.degradedSkeletonCards()`
    /// (the same fixture this asserts) for real, so this pins BOTH the
    /// mapping AND the "Not started" caption that fixture must carry.
    /// #1021 CR3: also pins the reason — a phase-1 failure must map to
    /// `.loadFailed` (the one `DailyHubView` captions), never
    /// `.completionStatusUnknown` (which stays silent).
    @Test func failedMapsToDegradedWithSkeletonCards() {
        let result = TodayMapper.present(state: .failed("boom"), inProgress: nil, isPhase2Degraded: false)
        guard case .degraded(let cards, let reason) = result else { Issue.record("expected .degraded, got \(result)"); return }
        #expect(reason == .loadFailed)
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { $0.isSkeleton })
        #expect(cards.allSatisfy { !$0.isCompleted })
        #expect(cards.allSatisfy { $0.statusText == "Not started" })
        #expect(cards == TodayMapper.degradedSkeletonCards())
    }

    @Test func loadedWithMixedCompletionStaysLoaded() {
        var cards = Self.trio()
        cards[0] = DailyCard(envelope: cards[0].envelope, isCompleted: true, bestTimeSeconds: 72)
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        guard case .loaded(let models) = result else { Issue.record("expected .loaded, got \(result)"); return }
        #expect(models.count == 3)
        #expect(models[0].isCompleted)
        #expect(models[0].statusText.contains("Solved"))
        #expect(!models[1].isCompleted)
    }

    @Test func loadedWithAllCompletedBecomesAllDone() {
        let cards = Self.trio().map { DailyCard(envelope: $0.envelope, isCompleted: true, bestTimeSeconds: 60) }
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        guard case .allDone(let models) = result else { Issue.record("expected .allDone, got \(result)"); return }
        #expect(models.allSatisfy { $0.isCompleted })
    }

    /// #1021 CR3: the phase-2 degrade must map to `.completionStatusUnknown`
    /// (silent — `DailyHubView` renders no caption for it), never
    /// `.loadFailed` (which pins the OPPOSITE — see
    /// `failedMapsToDegradedWithSkeletonCards`).
    @Test func loadedWithPhase2DegradedForcesEveryCardNotStartedWithRealThumbnails() {
        var cards = Self.trio()
        cards[0] = DailyCard(envelope: cards[0].envelope, isCompleted: true, bestTimeSeconds: 60)
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: true)
        guard case .degraded(let models, let reason) = result else { Issue.record("expected .degraded, got \(result)"); return }
        #expect(reason == .completionStatusUnknown)
        #expect(models.allSatisfy { !$0.isCompleted })
        // Real thumbnails (not skeleton) — seed-derived, no CK dependency.
        #expect(models.allSatisfy { !$0.isSkeleton && $0.preview != nil })
        #expect(models.allSatisfy { $0.statusText.contains("Not started") })
    }

    // MARK: - Status text + thumbnail rules (spec B/C)

    @Test func completedWithBestTimeShowsSolvedAndTime() {
        var cards = Self.trio()
        cards[0] = DailyCard(envelope: cards[0].envelope, isCompleted: true, bestTimeSeconds: 192)
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "Solved · 3:12")
    }

    @Test func completedWithNoBestTimeShowsBareSolved() {
        var cards = Self.trio()
        cards[0] = DailyCard(envelope: cards[0].envelope, isCompleted: true, bestTimeSeconds: nil)
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "Solved")
    }

    @Test func notStartedShowsGivenCount() {
        let cards = Self.trio()
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        let expectedGivens = cards[0].envelope.puzzle.clues.givenMask.filter { $0 }.count
        #expect(result.cards[0].statusText == "Not started · \(expectedGivens) givens")
    }

    @Test func inProgressMatchingPuzzleIdShowsElapsedTime() {
        let cards = Self.trio()
        let summary = SavedGameSummary(
            recordName: "r1",
            puzzleId: cards[0].envelope.identity.puzzleId,
            mode: .daily,
            difficulty: cards[0].difficulty,
            lastModifiedAt: Date(),
            elapsedSeconds: 65,
            status: "inProgress",
            generatorVersion: 1,
            boardState: nil
        )
        let result = TodayMapper.present(state: .loaded(cards), inProgress: summary, isPhase2Degraded: false)
        #expect(result.cards[0].statusText == "In progress · 1:05")
        // No decodable boardState → falls back to clues-only, not nil.
        #expect(result.cards[0].preview != nil)
    }

    @Test func inProgressNotMatchingAnyCardIsIgnored() {
        let cards = Self.trio()
        let summary = SavedGameSummary(
            recordName: "r1",
            puzzleId: "some-other-puzzle",
            mode: .daily,
            difficulty: .easy,
            lastModifiedAt: Date(),
            elapsedSeconds: 65,
            status: "inProgress",
            generatorVersion: 1
        )
        let result = TodayMapper.present(state: .loaded(cards), inProgress: summary, isPhase2Degraded: false)
        #expect(!result.cards[0].statusText.contains("In progress"))
    }

    @Test func completedCardCarriesTheCompletedAccessibilityIdentifier() {
        var cards = Self.trio()
        cards[0] = DailyCard(envelope: cards[0].envelope, isCompleted: true)
        let result = TodayMapper.present(state: .loaded(cards), inProgress: nil, isPhase2Degraded: false)
        #expect(result.cards[0].accessibilityIdentifier == "sudoku.dailyHub.card.completed")
        #expect(result.cards[1].accessibilityIdentifier == nil)
    }

    // MARK: - Header

    @Test func headerModelSkeletonWhenWeekStripUnknown() {
        let model = TodayMapper.headerModel(weekStrip: .unknown, allCompletedDays: [], today: DayKey(Self.fixedDate, calendar: .current))
        #expect(model.isSkeleton)
        #expect(model.last7 == Array(repeating: false, count: 7))
    }

    @Test func headerModelUsesWeekStripStreakVerbatim() {
        let days = (0...6).reversed().map { offset in
            DailyStripDay(
                offsetFromToday: offset,
                date: Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400),
                isCompleted: offset == 0
            )
        }
        let snapshot = DailyStripSnapshot(days: days, streak: 1)
        let model = TodayMapper.headerModel(weekStrip: snapshot, allCompletedDays: [], today: DayKey(Self.fixedDate, calendar: .current))
        #expect(!model.isSkeleton)
        #expect(model.current == 1)
        #expect(model.last7 == days.map(\.isCompleted))
    }

    @Test func headerModelLongestComesFromAllCompletedDaysNotJustTheWindow() {
        let today = DayKey(Self.fixedDate, calendar: .current)
        let days = (0...6).reversed().map { offset in
            DailyStripDay(offsetFromToday: offset, date: Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400), isCompleted: offset == 0)
        }
        let snapshot = DailyStripSnapshot(days: days, streak: 1)
        // An 10-day run entirely OUTSIDE the 7-day window (offsets 20...29).
        let longRun = Set((20...29).map { offset in
            DayKey.key(UTCDay.string(from: Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400)))!
        })
        let model = TodayMapper.headerModel(weekStrip: snapshot, allCompletedDays: longRun, today: today)
        #expect(model.longest == 10)
    }

    @Test func headerModelTappablePipsAreReviewablePastDaysOnly() {
        let today = DayKey(Self.fixedDate, calendar: .current)
        let days: [DailyStripDay] = [
            DailyStripDay(offsetFromToday: 1, date: Self.fixedDate.addingTimeInterval(-86_400), isCompleted: true, completedPuzzleIds: ["2026-05-06-easy"]),
            DailyStripDay(offsetFromToday: 0, date: Self.fixedDate, isCompleted: true, completedPuzzleIds: ["2026-05-07-easy"])
        ]
        let snapshot = DailyStripSnapshot(days: days, streak: 2)
        let model = TodayMapper.headerModel(weekStrip: snapshot, allCompletedDays: [], today: today)
        // index 0 = yesterday (reviewable, past) → tappable; index 1 = today → never tappable.
        #expect(model.tappablePipIndices == Set([0]))
    }

    // MARK: - Loading skeleton (Leader ruling 1)

    @Test func skeletonCardsAre9x9AndMarkedSkeleton() {
        let skeletons = TodayMapper.skeletonCards()
        #expect(skeletons.count == 3)
        #expect(skeletons.allSatisfy { $0.isSkeleton })
        #expect(skeletons.allSatisfy { $0.preview?.columns == 9 && $0.preview?.rows == 9 })
    }
}
