public import SwiftUI

// MARK: - MinesweeperRootView (skeleton)
//
// PR D placeholder — renders a "Hello, Minesweeper" screen so the Minesweeper
// app target has a body to attach to `WindowGroup`. Real navigation
// (Daily / Practice / Settings shell mirroring SudokuKit's pattern) lands in
// follow-up PRs.

public struct MinesweeperRootView: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.4x3.fill")
                .font(.system(size: 64))
                .foregroundStyle(.tint)
            Text("Hello, Minesweeper")
                .font(.title)
        }
        .padding()
    }
}
