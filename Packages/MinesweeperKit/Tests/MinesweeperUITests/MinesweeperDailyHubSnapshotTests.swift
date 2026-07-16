// MinesweeperDailyHubSnapshotTests — Daily-hub themed card baselines (#308).
//
// From #290 CR (peer of #303): the wired Daily hub ships real themed cards
// (difficulty dot, completion checkmark, glass cards, MS palette) with only
// pure-data + VM tests — the rendered layout was unverified. These baselines
// guard the 1-vs-3-column grid, the difficulty tint per row, and the
// completed-vs-uncompleted card states across light + dark.
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
@Suite("MinesweeperDailyHubView — themed snapshots")
struct MinesweeperDailyHubSnapshotTests {

    /// A fixed daily trio — all three card states exercised in the same frame:
    /// Beginner = not-played (em-dash), Intermediate = completed (checkmark),
    /// Expert = failed (xmark, Epic 8 / SDD-003). Hand-built (not date-derived)
    /// so the fixture is fully deterministic.
    private static let loadedTrio: [MinesweeperDailyCard] = [
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(
                puzzleId: "fixture-beginner",
                difficulty: .beginner,
                seed: 1
            ),
            isCompleted: false,
            isFailed: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(
                puzzleId: "fixture-intermediate",
                difficulty: .intermediate,
                seed: 2
            ),
            isCompleted: true,
            isFailed: false
        ),
        MinesweeperDailyCard(
            entry: MinesweeperDailyEntry(
                puzzleId: "fixture-expert",
                difficulty: .expert,
                seed: 3
            ),
            isCompleted: false,
            isFailed: true
        ),
    ]

    /// The Daily hub seeded to its loaded trio, wrapped in a NavigationStack so
    /// the shell's `.navigationTitle` chrome renders.
    private func dailyHubView() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    // MARK: - Compact (iPhone, 1-column)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPhone_light() {
        let host = hostingView(
            dailyHubView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPhone-light-compact",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPhone-light-compact", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPhone_dark() {
        let host = hostingView(
            dailyHubView(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .dark,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPhone-dark-compact",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPhone-dark-compact", record: SnapshotMode.recordMode)
    }

    // MARK: - iPad 13" (regular, 1032×1376 pt)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPad_light() {
        let host = hostingView(
            dailyHubView(),
            size: SnapshotLayouts.iPad,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPad-light-regular",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPad-light-regular", record: SnapshotMode.recordMode)
    }

    // MARK: - Regular (Mac width, 3-column)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_regular_light() {
        let host = hostingView(
            dailyHubView(),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-mac-light-regular",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-mac-light-regular", record: SnapshotMode.recordMode)
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_regular_dark() {
        let host = hostingView(
            dailyHubView(),
            size: SnapshotLayouts.mac,
            colorScheme: .dark,
            sizeClass: .regular
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-mac-dark-regular",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-mac-dark-regular", record: SnapshotMode.recordMode)
    }

    // MARK: - #774 week-strip states
    //
    // The base fixtures above leave `weekStrip == .unknown` (skeleton dots) —
    // that IS the degraded baseline. The two below pin the with-streak state
    // and the AX3 layout. Fixed dates (relative to a deterministic anchor)
    // keep the VoiceOver weekday labels — and hence the structure snapshot —
    // stable.

    nonisolated private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// Mixed strip: today + yesterday completed, earlier days missed →
    /// last two dots filled, "2 day streak" caption.
    private static func partialStreakStrip() -> MinesweeperDailyStripSnapshot {
        let days = (0...6).reversed().map { offset in
            MinesweeperDailyStripDay(
                offsetFromToday: offset,
                date: fixedDate.addingTimeInterval(-Double(offset) * 86_400),
                isCompleted: offset <= 1
            )
        }
        return MinesweeperDailyStripSnapshot(days: days, streak: 2)
    }

    private func dailyHubViewWithStreak() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        viewModel.setWeekStripForTesting(Self.partialStreakStrip())
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPhone_light_streak() {
        let host = hostingView(
            dailyHubViewWithStreak(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPhone-light-streak2",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPhone-light-streak2", record: SnapshotMode.recordMode)
    }

    /// AX3 Dynamic Type layout pin — dots are structural (fixed 16pt, never
    /// wrap); caption + card text scale. Env-injected Dynamic Type snapshots
    /// are a layout pin only (memory: dynamic-type-sim-verify-and-cap); sim
    /// verification is the authority for AX bugs.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPhone_light_streak_ax3() {
        let host = hostingView(
            dailyHubViewWithStreak().dynamicTypeSize(.accessibility3),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPhone-light-streak-AX3",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPhone-light-streak-AX3", record: SnapshotMode.recordMode)
    }
}
#endif
