// DailyHubView — bootstrap, exhausted inline block, and 4-state snapshots.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import GameShellUI
import Persistence
import SudokuEngine
import SudokuPersistence
import SudokuKitTesting

@MainActor
@Suite("DailyHubView — bootstrap + snapshots")
struct DailyHubViewTests {

    // internal (not `private`): `DailyHubStoreFrameSnapshotTests.swift` reads it too.
    nonisolated(unsafe) static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        completedDailyIds: Set<String> = [],
        providerResult: Result<[PuzzleEnvelope], PuzzleStoreError>? = nil
    ) async -> DailyHubViewModel {
        let provider = FakePuzzleProvider()
        let result = providerResult ?? .success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate))
        await provider.setDailyTrioResult(result)
        let persistence = FakePersistence()
        // #921: `fetchCompletedDailyIdsByDay()` day-buckets from per-date
        // scripting only (no global-default fallback — see
        // `completedDailyIdsByDate`'s doc). The OLD global default answered
        // the SAME `completedDailyIds` value for every one of the 7 window
        // days (each day's independent `fetchCompletedDailyIds(for:)` call
        // fell back to it identically) — reproduce that exact fixture by
        // scripting all 7 window dates to the same value explicitly, so the
        // committed `easyDone`/`allDone` baselines (full 7-day streak +
        // today's specific-difficulty check) render byte-identical.
        if !completedDailyIds.isEmpty {
            for offset in 0...6 {
                let date = Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400)
                await persistence.setCompletedDailyIds(completedDailyIds, for: date)
            }
        }
        return DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
    }

    @Test func bootstrapLoadsTrioAndMergesCompletion() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId

        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards[0].isCompleted == true)
        #expect(cards[1].isCompleted == false)
        #expect(cards[2].isCompleted == false)
    }

    @Test func generatorFailureMapsToExhaustedState() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )

        await viewModel.bootstrap()

        #expect(viewModel.state == .exhausted)
    }

    // #686/#1020: the `.exhausted` block's CTAs must actually do something
    // (previously "Try another difficulty" was a dead `{}` closure with no
    // picker on this screen to route to). #1020: Practice is a tab identity
    // now — "Try Practice" switches tabs instead of pushing a route.
    @Test func exhaustedTryPracticeInsteadSwitchesToPracticeTab() async {
        var selected: [AppTab] = []
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.generatorFailed(underlying: "exhausted")))
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: FakePersistence(),
            dateProvider: { Self.fixedDate },
            selectTab: { selected.append($0) }
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .exhausted)

        viewModel.tryPracticeInstead()

        #expect(selected == [.practice])
    }

    // #1020 (design.md §3.1): Today is a tab root now, not a route pushed
    // from Home — "Cancel" closes the inline block (drops to an empty
    // `.loaded` state) and stays on Today rather than popping a path.
    @Test func exhaustedDismissClosesBlockToEmptyLoadedState() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .exhausted)

        viewModel.dismissExhausted()

        #expect(viewModel.state == .loaded([]))
    }

    @Test func cardTapAppendsBoardRoute() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded")
            return
        }

        viewModel.cardTapped(cards[1])
        #expect(viewModel.path == [.board(puzzleId: cards[1].envelope.identity.puzzleId)])
    }

    // MARK: - Snapshots (#1021 Phase B — one baseline per TodayPresentation
    // state; names deliberately contain the state word per the dispatch
    // spec). The pre-Phase-B suite (unfinished/easyDone/allDone/exhausted +
    // mac/iPad/streak variants) pinned the retired glass `DailyPuzzleCard` +
    // `DailyStripView` header card — replaced wholesale, not incrementally,
    // since every one of those baselines necessarily diffs under the new
    // shared `DailyCardContent`/`StreakHeaderView` composition. Their old
    // `__Snapshots__/DailyHubViewTests` baselines were deleted (see report).

    #if canImport(AppKit)
    /// `loading`: a freshly-constructed, never-bootstrapped view model —
    /// `DailyHubShellView`'s `.idle` branch renders the same `loading:`
    /// skeleton-card grid as `.loading` (Leader ruling: design.md §3.1
    /// "保留格線結構,不是空白方塊" — 3 grid-lined skeleton rows, not a spinner),
    /// with the streak header still rendering (also skeleton) above it per
    /// the shell's "every state" contract. An artificial fetch delay makes
    /// this deterministic — without one, `DailyHubView`'s own
    /// `.task { bootstrap() }` can race the `NSHostingView` capture and
    /// resolve to `.loaded` before the snapshot is taken (verified: MS's
    /// sibling test hit exactly this race, since MS's `bootstrap()` has no
    /// `await` suspension point at all to lose the race against).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadingIPhoneLight() async {
        let provider = FakePuzzleProvider()
        await provider.setArtificialDelay(nanos: 60_000_000_000)
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: FakePersistence(),
            dateProvider: { Self.fixedDate }
        )
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-loading")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-loading", record: SnapshotMode.recordMode)
    }

    /// `loaded`: one difficulty completed, the other two not — the ordinary
    /// mixed-state render.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadedIPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId
        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-loaded")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-loaded", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type pin of the same `loaded` fixture — env-injected
    /// Dynamic Type snapshots are a layout pin only, not proof of runtime
    /// behavior (memory: dynamic-type-sim-verify-and-cap); sim verification
    /// is the authority for AX bugs. Confirms the card title doesn't
    /// hyphenate/truncate at AX3 (Leader adjudication, row-card layout).
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadedAX3IPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId
        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel).dynamicTypeSize(.accessibility3),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-loaded-AX3")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-loaded-AX3", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type pin on an iPad-width REGULAR size class — #1021
    /// Phase G. Distinct from `snapshotLoadedAX3IPhoneLight` above (compact
    /// size class): before the fix, `DailyHubShellView`'s grid kept 3
    /// columns whenever `sizeClass == .regular`, so at AX3 each ~262pt
    /// column wrapped every status word onto its own line and hyphenated.
    /// `DailyHubGridLayout.columnCount(...)` now forces a single column at
    /// any accessibility Dynamic Type size regardless of size class —
    /// confirms the grid collapses to one column here.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotLoadedAX3IPadLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId
        let viewModel = await makeViewModel(completedDailyIds: [easyId])
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular,
            dynamicTypeSize: .accessibility3
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPad-light-loaded-AX3")
        }
        assertViewStructure(of: host, named: "DailyHub-iPad-light-loaded-AX3", record: SnapshotMode.recordMode)
    }

    /// `allDone`: all three difficulties completed — `TodayAllDoneBlock`
    /// renders above the (still tappable) 3 solved cards.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAllDoneIPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let allIds = Set(envelopes.map(\.identity.puzzleId))
        let viewModel = await makeViewModel(completedDailyIds: allIds)
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-allDone")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-allDone", record: SnapshotMode.recordMode)
    }

    /// `degraded`: the phase-2 completion-overlay fetch fails — real
    /// thumbnails still render (seed-derived, no CK dependency) but every
    /// card is forced to "not started", and the streak header renders as a
    /// skeleton rather than disappearing.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotDegradedIPhoneLight() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        await persistence.setFetchCompletedDailyIdsError(.iCloudNotSignedIn)
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        #expect(viewModel.isPhase2Degraded)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-degraded")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-degraded", record: SnapshotMode.recordMode)
    }

    /// `exhausted` (Sudoku only): the generator failed for today — the
    /// inline icon+message+action block, now wrapped in a `HubCard`
    /// (standard material, no glass) per design.md §3.1's `.exhausted` row.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotExhaustedIPhoneLight() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .exhausted)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-exhausted")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-exhausted", record: SnapshotMode.recordMode)
    }

    // MARK: - Store marketing-frame fixtures (#1021 Phase H)
    // Fixture helpers live in `DailyHubStoreFrameSnapshotTests.swift` (split
    // out for `file_length`; see its header); `@Test`s stay HERE so
    // `#filePath`-derived baseline lookup matches `build-ascspec-screenshots.py`'s
    // literal `Slot(...)` path (`__Snapshots__/DailyHubViewTests/`).

    /// iPhone `02-daily` store frame: all 3 difficulties solved today.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAllCompletedIPhoneLight() async {
        let trio = Self.storeDailyTrio(date: Self.fixedDate)
        let allIds = Set(trio.map(\.identity.puzzleId))
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(trio))
        let persistence = FakePersistence()
        await Self.seedStoreStreak(persistence: persistence, todayCompletedIds: allIds)
        let bestTimes: [Difficulty: Int] = [.easy: 192, .medium: 401, .hard: 860]  // 3:12 / 6:41 / 14:20
        for (difficulty, seconds) in bestTimes {
            await persistence.setPersonalRecordResult(
                .success(PersonalRecord(
                    recordName: "daily-\(difficulty.rawValue)-store",
                    mode: .daily,
                    difficulty: difficulty,
                    bestTimeSeconds: seconds,
                    totalTimeSeconds: seconds * 5,
                    completedCount: 5,
                    lastUpdatedAt: Self.fixedDate,
                    completedPuzzleIds: [PuzzleIdentity.daily(date: Self.fixedDate, difficulty: difficulty).puzzleId]
                )),
                mode: .daily,
                difficulty: difficulty
            )
        }
        let viewModel = DailyHubViewModel(provider: provider, persistence: persistence, dateProvider: { Self.fixedDate })
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-allDone")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-allDone", record: SnapshotMode.recordMode)
    }

    /// iPad `02-daily` store frame: Easy solved, Medium in progress, Hard not started.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotUnfinishedIPadLight() async {
        let trio = Self.storeDailyTrio(date: Self.fixedDate)
        let easyId = trio[0].identity.puzzleId
        let mediumId = trio[1].identity.puzzleId
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(trio))
        let persistence = FakePersistence()
        await Self.seedStoreStreak(persistence: persistence, todayCompletedIds: [easyId])
        await persistence.setPersonalRecordResult(
            .success(PersonalRecord(
                recordName: "daily-easy-store",
                mode: .daily,
                difficulty: .easy,
                bestTimeSeconds: 192,  // 3:12
                totalTimeSeconds: 192 * 5,
                completedCount: 5,
                lastUpdatedAt: Self.fixedDate,
                completedPuzzleIds: [easyId]
            )),
            mode: .daily,
            difficulty: .easy
        )
        let mediumBoardState = Self.storePartialBoardState(givenMask: trio[1].puzzle.clues.givenMask)
        await persistence.setResumeCandidate(SavedGameSummary(
            recordName: "in-progress-medium-store",
            puzzleId: mediumId,
            mode: .daily,
            difficulty: .medium,
            lastModifiedAt: Self.fixedDate,
            elapsedSeconds: 245,  // 4:05
            status: "inProgress",
            generatorVersion: 1,
            boardState: mediumBoardState
        ))
        let viewModel = DailyHubViewModel(provider: provider, persistence: persistence, dateProvider: { Self.fixedDate })
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPad-light-unfinished")
        }
        assertViewStructure(of: host, named: "DailyHub-iPad-light-unfinished", record: SnapshotMode.recordMode)
    }
    #endif
}
