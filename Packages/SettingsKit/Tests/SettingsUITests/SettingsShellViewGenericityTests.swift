import SwiftUI
import Testing
@testable import SettingsUI

// MARK: - Sentinel: SettingsShellView stays generic
//
// PR X4 extracted SettingsShellView out of SudokuKit's SettingsView. The
// shell takes a `@ViewBuilder` closure for its section content so each
// game's Kit can pass its own sections (Sudoku: Purchases / About / Storage;
// Minesweeper: TBD). This test pins the genericity by instantiating the
// shell with non-Sudoku content (a plain `Section("Sentinel")` with `Text`
// rows — nothing imported from SudokuUI). Compile-only — if a future
// refactor accidentally re-couples the shell to Sudoku types, this file
// stops compiling.
//
// Mirrors X1 (NavigationStackHost) + X3 (RootShellView) sentinels.

@Suite("GameShellUI — SettingsShellView stays generic")
struct SettingsShellViewGenericityTests {
    @Test @MainActor func instantiatesWithNonSudokuSections() {
        let shell = SettingsShellView(title: "Sentinel") {
            Section("Sentinel") {
                Text("row A")
                Text("row B")
            }
        }
        _ = shell
    }
}
