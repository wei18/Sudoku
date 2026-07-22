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
    ///
    /// #878/#941: `setStateForTesting` bypasses `bootstrap()` entirely, which
    /// leaves `isPhase2Pending` at its default `true` — every baseline below
    /// explicitly pins `isPhase2Pending: false` for hygiene, though #941
    /// removed the last visual/behavioral difference `isPhase2Pending` ever
    /// made (cards render full-opacity + tappable regardless now).
    private func dailyHubView(isPhase2Pending: Bool = false) -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        viewModel.setPhase2PendingForTesting(isPhase2Pending)
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
    /// last two dots filled, "2 day streak" caption. Completed days carry a
    /// production-shaped puzzleId (#826 CR round 2: the tappable gate is
    /// `isReviewable`, derived from the ids in init — an id-less completed
    /// day would render inert and silently drop yesterday's dot-button from
    /// the structure baseline).
    private static func partialStreakStrip() -> MinesweeperDailyStripSnapshot {
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

    private func dailyHubViewWithStreak() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        // #878: pin the settled (non-pending) treatment — see `dailyHubView`'s
        // doc above for why this is needed alongside `setStateForTesting`.
        viewModel.setPhase2PendingForTesting(false)
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

    /// #882 (audit #875 coverage caveat): the EMPTY state — a fresh account
    /// where the week-window fetch SUCCEEDED but every day has zero
    /// completions. Distinct from the base fixtures above (`weekStrip` left
    /// at its default `.unknown` — fetch never ran / failed, card omitted
    /// entirely): here `days` is fully populated (7 slots) and every dot
    /// renders not-completed (today dashed, the other 6 missed with the
    /// #882 F-3 xmark), with no streak header (0-day streak captions
    /// identically to unknown — see `MinesweeperDailyStripSnapshot.streak`'s
    /// doc). MS has no incidental equivalent of Sudoku's real-bootstrap path
    /// producing this for free (every MS snapshot fixture seeds state via
    /// `setStateForTesting`), so this is scripted explicitly via
    /// `setWeekStripForTesting`.
    private static func emptyStrip() -> MinesweeperDailyStripSnapshot {
        let days = (0...6).reversed().map { offset in
            MinesweeperDailyStripDay(
                offsetFromToday: offset,
                date: fixedDate.addingTimeInterval(-Double(offset) * 86_400),
                isCompleted: false,
                completedPuzzleIds: []
            )
        }
        return MinesweeperDailyStripSnapshot(days: days, streak: nil)
    }

    private func dailyHubViewWithEmptyStrip() -> some View {
        let viewModel = MinesweeperDailyHubViewModel(path: .constant([]))
        viewModel.setStateForTesting(.loaded(Self.loadedTrio))
        // #878: pin the settled (non-pending) treatment — see `dailyHubView`'s
        // doc above for why this is needed alongside `setStateForTesting`.
        viewModel.setPhase2PendingForTesting(false)
        viewModel.setWeekStripForTesting(Self.emptyStrip())
        return NavigationStack {
            MinesweeperDailyHubView(viewModel: viewModel)
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshotDaily_iPhone_light_stripEmpty() {
        let host = hostingView(
            dailyHubViewWithEmptyStrip(),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        assertUISnapshot(
            of: host,
            as: .image,
            named: "Daily-iPhone-light-stripEmpty",
            record: SnapshotMode.recordMode
        )
        assertViewStructure(of: host, named: "Daily-iPhone-light-stripEmpty", record: SnapshotMode.recordMode)
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
