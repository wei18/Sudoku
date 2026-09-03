// MinesweeperDailyHubSnapshotTests — Daily-hub themed card baselines (#308,
// redesigned #1021 Phase B).
//
// #1021 Phase B: the glass `MinesweeperDailyCardView` + `MinesweeperDailyStripView`
// header card are retired in favor of the shared `GameShellUI.DailyCardContent`
// + `StreakHeaderView` (design.md §3.1/§4.2) — every baseline below is a
// wholesale replacement, not an incremental re-record, of the pre-Phase-B
// suite (their old `__Snapshots__/MinesweeperDailyHubSnapshotTests` baselines
// were deleted; see the Phase B report). One baseline per `TodayPresentation`
// state MS can reach — `loading`/`loaded`/`allDone`/`degraded` — names
// deliberately contain the state word (MS has no `exhausted`/`failed`, D21).
//
// Seam (#308): `MinesweeperDailyHubViewModel.setStateForTesting(.loaded(...))`
// installs a fixed loaded trio whose `bootstrap()` is latched to a no-op, so
// the seeded cards survive `NSHostingView` capture instead of being overwritten
// by the view's `.task { bootstrap() }` (which otherwise pulls a `Date()`-seeded
// trio — non-deterministic). Mirrors the Completion VM's testing seam (#292).
// Production never sets this; the live fetch path is untouched.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
@testable import MinesweeperUI

import MinesweeperEngine

@MainActor
@Suite("MinesweeperDailyHubView — themed snapshots (#1021 Phase B)")
struct MinesweeperDailyHubSnapshotTests {

    /// A fixed daily trio — mixed states in one frame: Beginner = not-played,
    /// Intermediate = completed (checkmark), Expert = failed (Epic 8 /
    /// SDD-003). Hand-built (not date-derived) so the fixture is fully
    /// deterministic.
    private static let loadedTrio: [MinesweeperDailyCard] = [
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-beginner", difficulty: .beginner, seed: 1),
            isCompleted: false,
            isFailed: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-intermediate", difficulty: .intermediate, seed: 2),
            isCompleted: true,
            bestTimeSeconds: 118
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-expert", difficulty: .expert, seed: 3),
            isCompleted: false,
            isFailed: true
        )
    ]

    private static let completedTrio: [MinesweeperDailyCard] = [
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-beginner", difficulty: .beginner, seed: 1),
            isCompleted: true,
            bestTimeSeconds: 24
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-intermediate", difficulty: .intermediate, seed: 2),
            isCompleted: true,
            bestTimeSeconds: 118
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(puzzleId: "fixture-expert", difficulty: .expert, seed: 3),
            isCompleted: true,
            bestTimeSeconds: 341
        )
    ]

    private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// A settled (non-`.unknown`) 7-day window with a 2-day streak — feeds a
    /// real (non-skeleton) `StreakHeaderView` render. Mirrors the pre-Phase-B
    /// suite's `partialStreakStrip()` fixture.
    private static func streakSnapshot() -> MinesweeperDailyStripSnapshot {
        let days = (0...6).reversed().map { offset in
            MinesweeperDailyStripDay(
                offsetFromToday: offset,
                date: fixedDate.addingTimeInterval(-Double(offset) * 86_400),
                isCompleted: offset <= 1,
                completedPuzzleIds: offset <= 1 ? ["daily-2024-05-06-beginner"] : []
            )
        }
        return MinesweeperDailyStripSnapshot(days: days, streak: 2)
    }

    /// - Parameter degraded: when `true`, leaves `weekStrip` at its default
    ///   `.unknown` and marks phase 2 SETTLED (`isPhase2Pending: false`) —
    ///   `MinesweeperDailyHubViewModel.isPhase2Degraded`'s exact trigger.
    ///   When `false` (default) AND `state` is `.loaded`, seeds a real,
    ///   settled `streakSnapshot()` so the header renders its ordinary
    ///   (non-skeleton, non-degraded) state and the fixture trio's own
    ///   completed/failed flags render as-is. `.idle`/`.loading` never seed
    ///   the streak — phase 2 genuinely hasn't run for either.
    private func dailyHubView(state: MinesweeperDailyHubState?, degraded: Bool = false) -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        if let state {
            viewModel.setStateForTesting(state)
        }
        var isLoaded = false
        if case .loaded = state { isLoaded = true }
        if degraded {
            viewModel.setPhase2PendingForTesting(false)
        } else if isLoaded {
            viewModel.setWeekStripForTesting(Self.streakSnapshot())
            viewModel.setPhase2PendingForTesting(false)
        }
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    /// `loading`: `setStateForTesting(.loading)` PINS the state (and latches
    /// `hasBootstrapped`) so the view's own `.task { bootstrap() }` can't race
    /// past it before the snapshot captures — MS's `bootstrap()` is
    /// synchronous-to-phase-1 (pure `dailyTrio`), so an un-pinned `.idle`
    /// state resolves to `.loaded` before `NSHostingView` ever renders it
    /// (verified: an earlier version of this test used `state: nil` and
    /// silently captured the LOADED not-started render instead). The shell's
    /// `loading:` skeleton-card grid renders under the (also skeleton)
    /// streak header — `dailyHubView`'s `degraded`/streak-seeding branches
    /// are skipped for a non-`.loaded` state, so both stay genuinely unknown.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoading_iPhone_light() {
        let host = hostingView(
            dailyHubView(state: .loading),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPhone-light-loading", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPhone-light-loading", record: SnapshotMode.recordMode)
    }

    /// `loaded`: mixed not-played / completed / failed trio.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoaded_iPhone_light() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.loadedTrio)),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPhone-light-loaded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPhone-light-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoaded_regular_light() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.loadedTrio)),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-mac-light-loaded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-mac-light-loaded", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoaded_regular_dark() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.loadedTrio)),
            size: SnapshotLayouts.mac,
            colorScheme: .dark,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-mac-dark-loaded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-mac-dark-loaded", record: SnapshotMode.recordMode)
    }

    /// `allDone`: every difficulty completed — `TodayAllDoneBlock` renders
    /// above the (still tappable) 3 solved cards.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAllDone_iPhone_light() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.completedTrio)),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPhone-light-allDone", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPhone-light-allDone", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotAllDone_iPad_light() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.completedTrio)),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPad-light-allDone", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPad-light-allDone", record: SnapshotMode.recordMode)
    }

    /// `degraded`: phase-2 (week-window) fetch settled with nothing (default
    /// `weekStrip == .unknown`, `isPhase2Pending == false`) — every card
    /// forced to "not started", streak header renders as a skeleton.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDegraded_iPhone_light() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.loadedTrio), degraded: true),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPhone-light-degraded", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPhone-light-degraded", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type layout pin — a card title must not hyphenate/truncate
    /// at AX3 (Leader adjudication, row-card layout). Env-injected Dynamic
    /// Type snapshots are a layout pin only (memory:
    /// dynamic-type-sim-verify-and-cap); sim verification is the authority
    /// for AX bugs.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotLoaded_iPhone_light_AX3() {
        let host = hostingView(
            dailyHubView(state: .loaded(Self.loadedTrio)).dynamicTypeSize(.accessibility3),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(of: host, as: .image, named: "Daily-iPhone-light-loaded-AX3", record: SnapshotMode.recordMode)
        assertViewStructure(of: host, named: "Daily-iPhone-light-loaded-AX3", record: SnapshotMode.recordMode)
    }
}
#endif
