// DailyHubView — bootstrap, exhausted inline block, and 4-state snapshots.

import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import SudokuUI

import Persistence
import SudokuPersistence
import SudokuKitTesting

@MainActor
@Suite("DailyHubView — bootstrap + snapshots")
struct DailyHubViewTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

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

    // #686: the `.exhausted` alert's CTAs must actually navigate (previously
    // "Try another difficulty" was a dead `{}` closure with no picker on this
    // screen to route to).
    @Test func exhaustedTryPracticeInsteadRoutesToPracticeHub() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )
        await viewModel.bootstrap()
        #expect(viewModel.state == .exhausted)

        viewModel.tryPracticeInstead()

        #expect(viewModel.path == [.practice])
    }

    @Test func exhaustedDismissPopsBackToHome() async {
        let viewModel = await makeViewModel(
            providerResult: .failure(.generatorFailed(underlying: "exhausted"))
        )
        await viewModel.bootstrap()
        viewModel.path = [.home, .daily]
        #expect(viewModel.state == .exhausted)

        viewModel.dismissExhausted()

        #expect(viewModel.path == [.home])
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

    // MARK: - Snapshots

    #if canImport(AppKit)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotUnfinishedIPhoneLight() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-unfinished")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-unfinished", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotEasyCompletedIPhoneLight() async {
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
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-easyDone")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-easyDone", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotAllCompletedIPhoneLight() async {
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

    // #768: `.exhausted` now renders as an inline icon+message+action block
    // (was a system `.alert` over `Color.clear`) — pins the new content so a
    // regression back to a blank backdrop shows up as a snapshot diff.
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

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotUnfinishedIPadLight() async {
        let viewModel = await makeViewModel()
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

    // MARK: - #774 week-strip states

    /// Partial streak: today + yesterday completed via per-date scripting →
    /// last two dots filled, "2 day streak" caption. (The `makeViewModel`
    /// helper's `completedDailyIds:` fixtures above explicitly script ALL 7
    /// window dates to the same non-empty set — #921 — reproducing a FULL
    /// 7-day streak, so this is the only baseline pinning a MIXED strip.)
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStripPartialStreakIPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let easyId = envelopes[0].identity.puzzleId
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(envelopes))
        let persistence = FakePersistence()
        await persistence.setCompletedDailyIds([easyId], for: Self.fixedDate)
        await persistence.setCompletedDailyIds(["yesterday-easy"], for: Self.fixedDate.addingTimeInterval(-86_400))
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        #expect(viewModel.weekStrip.streak == 2)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-streak2")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-streak2", record: SnapshotMode.recordMode)
    }

    /// #882 (audit #875 coverage caveat): the EMPTY state — a fresh account
    /// with no completion history anywhere in the window. Distinct from
    /// `snapshotStripDegradedIPhoneLight` below: degraded means the fetch
    /// itself FAILED (`weekStrip == .unknown`, card omitted); empty means the
    /// fetch SUCCEEDED and every day genuinely has zero completions
    /// (`weekStrip.days.count == 7`, card renders with 7 not-completed dots —
    /// today dashed, the other 6 missed — and no streak header, since a
    /// genuine 0-day streak is captioned identically to unknown, per
    /// `DailyStripSnapshot.streak`'s doc). `makeViewModel()`'s default empty
    /// `completedDailyIds` already produces this via the real bootstrap path
    /// (unlike the MS suite's seeded fixtures) — this test makes that
    /// coverage explicit and asserted instead of leaving it an unlabeled
    /// side effect of `snapshotUnfinishedIPhoneLight`.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStripEmptyIPhoneLight() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()
        #expect(viewModel.weekStrip.days.count == 7)
        #expect(viewModel.weekStrip.days.allSatisfy { !$0.isCompleted })
        #expect(viewModel.weekStrip.streak == nil)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-stripEmpty")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-stripEmpty", record: SnapshotMode.recordMode)
    }

    /// Degraded strip: the completed-ids fetch fails (offline / signed-out) →
    /// all-subdued skeleton dots, NO streak caption (never a false "0"), trio
    /// still rendered un-completed.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStripDegradedIPhoneLight() async {
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
        #expect(viewModel.weekStrip == .unknown)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-stripDegraded")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-stripDegraded", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type: the strip's dots are structural (fixed 16pt, never
    /// wrap); the caption + trio text scale. Env-injected Dynamic Type
    /// snapshots are a layout pin only, not proof of runtime behavior
    /// (see memory: dynamic-type-sim-verify-and-cap) — sim verification is
    /// the authority for AX bugs.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotStripStreakAX3IPhoneLight() async {
        let envelopes = FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(envelopes))
        let persistence = FakePersistence()
        await persistence.setCompletedDailyIds([envelopes[0].identity.puzzleId], for: Self.fixedDate)
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        let host = hostingView(
            DailyHubView(viewModel: viewModel).dynamicTypeSize(.accessibility3),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-streak-AX3")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-streak-AX3", record: SnapshotMode.recordMode)
    }

    // MARK: - #878 phase-2-pending card treatment

    /// #878 (#874 F-4, re-opening #842's no-affordance tradeoff): pins the
    /// dimmed, non-button card treatment while `isPhase2Pending` is `true` —
    /// scripted via `setPhase2PendingForTesting` after a real (fast, fake-
    /// backed) `bootstrap()` lands, no gated-fetch fixture needed. Mirrors
    /// MinesweeperKit's `Daily-iPhone-light-phase2Pending` counterpart.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotPhase2PendingIPhoneLight() async {
        let viewModel = await makeViewModel()
        await viewModel.bootstrap()
        #expect(viewModel.isPhase2Pending == false)
        viewModel.setPhase2PendingForTesting(true)
        let host = hostingView(
            DailyHubView(viewModel: viewModel),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "DailyHub-iPhone-light-phase2Pending")
        }
        assertViewStructure(of: host, named: "DailyHub-iPhone-light-phase2Pending", record: SnapshotMode.recordMode)
    }
    #endif
}
