import SwiftUI
import Testing
@testable import GameShellUI

// MARK: - Sentinel: PracticeHubShellView stays generic
//
// PR U12 extracted PracticeHubShellView out of SudokuKit's PracticeHubView.
// The shell is generic over two `View` slots — `Filter` (the game's
// difficulty Picker) and `CTA` (the game's draw/start affordance) — so
// neither slot bakes a Sudoku-specific shape into the public surface. This
// test instantiates the shell with two unrelated slot views (plain Text
// stand-ins for the Picker + CTA) to pin that genericity. Compile-only:
// if a future refactor accidentally re-couples either slot to a Sudoku
// type, this file stops compiling.
//
// Mirrors SettingsShellViewGenericityTests (PR X4).

@Suite("GameShellUI — PracticeHubShellView stays generic")
struct PracticeHubShellViewGenericityTests {
    @Test @MainActor func instantiatesWithNonSudokuSlots() {
        let shell = PracticeHubShellView(
            title: "Sentinel",
            backgroundColor: .clear,
            filterHeader: "Sentinel filter",
            headerForeground: .primary,
            filter: {
                Text("filter slot")
            },
            cta: {
                Text("cta slot")
            }
        )
        _ = shell
    }

    @Test @MainActor func instantiatesWithStructurallyDistinctSlots() {
        // Picker stand-in (HStack) + Button stand-in to prove neither slot
        // is constrained to a single SwiftUI primitive shape.
        let shell = PracticeHubShellView(
            title: "Sentinel",
            backgroundColor: .clear,
            filterHeader: "Pick",
            headerForeground: .secondary,
            filter: {
                HStack {
                    Text("A")
                    Text("B")
                }
            },
            cta: {
                Button("Go") {}
            }
        )
        _ = shell
    }
}
