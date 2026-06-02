import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - Sentinel: DailyHubShellView stays generic
//
// PR U12 extracted DailyHubShellView out of SudokuKit's DailyHubView. The
// shell is generic over the per-item card type so each game's Kit can pass
// its own card view (Sudoku: `DailyPuzzleCard`; Minesweeper: TBD). This
// test pins the genericity by instantiating the shell with two distinct
// non-Sudoku `Item` types — a trivial `Identifiable` struct and a wrapper
// — using `Text(...)` for the card / failure slots (nothing imported from
// SudokuUI / MinesweeperUI). Compile-only — if a future refactor accidentally
// re-couples the shell to Sudoku types, this file stops compiling.
//
// Mirrors X1 (NavigationStackHost) + X3 (RootShellView) + X4
// (SettingsShellView) sentinel patterns.

@Suite("GameShellUI — DailyHubShellView stays generic")
struct DailyHubShellViewGenericityTests {
    struct SentinelItem: Hashable, Sendable, Identifiable {
        let id: String
    }

    struct OtherItem: Hashable, Sendable, Identifiable {
        let id: Int
        let label: String
    }

    @Test @MainActor func instantiatesWithLoadedSentinelItems() {
        let shell = DailyHubShellView(
            title: "Sentinel",
            backgroundColor: .clear,
            state: HubLoadState<SentinelItem>.loaded([
                SentinelItem(id: "a"),
                SentinelItem(id: "b")
            ]),
            card: { item in Text(item.id) },
            failure: { reason in Text(reason) },
            onItemTap: { _ in }
        )
        _ = shell
    }

    @Test @MainActor func instantiatesWithSecondItemTypeAndEmptyState() {
        // Confirms the shell isn't accidentally fixed to one Item type by
        // instantiating with a second, structurally different Identifiable.
        let shell = DailyHubShellView(
            title: "Sentinel",
            backgroundColor: .clear,
            state: HubLoadState<OtherItem>.empty,
            card: { item in Text(item.label) },
            failure: { reason in Text(reason) },
            onItemTap: { _ in }
        )
        _ = shell
    }

    @Test @MainActor func instantiatesWithFailedState() {
        let shell = DailyHubShellView(
            title: "Sentinel",
            backgroundColor: .clear,
            state: HubLoadState<SentinelItem>.failed("boom"),
            card: { item in Text(item.id) },
            failure: { reason in Text("failure: \(reason)") },
            onItemTap: { _ in }
        )
        _ = shell
    }
}
