// MinesweeperNearWinModifier — DEBUG-only view modifier that detects the
// `-uitest-near-win` launch argument and presents a near-win board as a
// fullScreenCover over the normal root (#510 uitest hook).
//
// Mirrors `SudokuNearWinModifier` exactly. Applied at
// `MinesweeperAppComposition.rootView` level. When the launch argument is
// absent the modifier is a transparent no-op.
//
// On iOS: a `fullScreenCover` presents `MinesweeperBoardView` with the
// pre-built near-win VM. `MinesweeperBoardView` shows its completion overlay
// inline on win (no NavigationStack push needed). On macOS: `fullScreenCover`
// is unavailable — the modifier is an unconditional pass-through.
//
// Availability: `#if DEBUG` only — stripped from Release builds entirely.

#if DEBUG

public import SwiftUI
import GameAppKit

public struct MinesweeperNearWinModifier: ViewModifier {

    public init() {}

    public func body(content: Content) -> some View {
        #if os(iOS)
        content.modifier(MinesweeperNearWinIOSModifier())
        #else
        content
        #endif
    }
}

// MARK: - iOS implementation

#if os(iOS)

import MinesweeperEngine
import MinesweeperGameState

@MainActor
private struct MinesweeperNearWinIOSModifier: ViewModifier {

    @State private var nearWinSession: MinesweeperNearWinSession?

    func body(content: Content) -> some View {
        let isNearWinLaunch = ProcessInfo.processInfo.arguments
            .contains(UITestLaunchArg.nearWin)
        return content
            .onAppear {
                guard isNearWinLaunch else { return }
                Task { @MainActor in
                    nearWinSession = await MinesweeperNearWinSession.build()
                }
            }
            // item: (not isPresented:) — the cover is driven by the session
            // itself, so the content closure always receives the built session.
            // Splitting presentation (Bool) from data (optional) raced: the
            // cover presented before the session propagated → blank cover (#523).
            .fullScreenCover(item: $nearWinSession) { nearWin in
                MinesweeperNearWinCoverView(nearWin: nearWin)
            }
    }
}

// MARK: - Cover content

/// Presents `MinesweeperBoardView` with the pre-built near-win VM.
/// `MinesweeperBoardView` shows a completion overlay inline on win —
/// no NavigationStack push is needed.
@MainActor
private struct MinesweeperNearWinCoverView: View {
    let nearWin: MinesweeperNearWinSession

    var body: some View {
        MinesweeperBoardView(viewModel: nearWin.viewModel)
            .environment(\.theme, MinesweeperTheme())
            .environment(\.minesweeperCell, MinesweeperTheme().cell)
            // #510 Phase 3 (#633): winning-cell beacon. Unlike Sudoku (where a
            // wrong digit is harmless and can be brute-forced), tapping the
            // wrong hidden cell here hits a mine = loss — the E2E test must tap
            // the EXACT remaining safe cell, whose (row, col) is computed at
            // runtime. Surface it through this hidden element's identifier; the
            // test parses it, then taps that cell by its unique a11y label
            // ("Row r+1, Column c+1, Hidden"). Compiled out of Release builds by
            // the enclosing `#if DEBUG`.
            .overlay(alignment: .topLeading) {
                Color.clear
                    .frame(width: 1, height: 1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("uitest winning cell beacon")
                    .accessibilityIdentifier(
                        "game.uitest.winningCell.r\(nearWin.lastSafeRow).c\(nearWin.lastSafeCol)"
                    )
            }
    }
}

#endif // os(iOS)

#endif // DEBUG
