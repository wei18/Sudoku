// MinesweeperProgressHostView — owns Minesweeper's
// `MinesweeperProgressViewModel` and re-renders the shared
// `GameAppKit.ProgressScreen` as it fills in (#1021 Phase D, mirrors Sudoku's
// `ProgressHostView`).
//
// `ProgressScreen` is a dumb view over a `ProgressModel` VALUE (shared by both
// apps, so it cannot hold either app's concrete view model type) — this host
// is the thin per-app sliver that owns the `@Observable` view model and reads
// `viewModel.model` from ITS OWN body (satisfying Observation's SwiftUI
// invalidation tracking) before handing the current snapshot down.

public import SwiftUI
// `public` — this file's public init names `GameRootViewModel<AppRoute>` in
// its own public signature (mirrors `SettingsView.swift`'s same need).
public import GameAppKit

public struct MinesweeperProgressHostView: View {
    @State private var viewModel: MinesweeperProgressViewModel
    private let rootViewModel: GameRootViewModel<AppRoute>
    // #1021 CR2 M1: mirrors Sudoku's `ProgressHostView` /
    // `MinesweeperDailyHubView`'s `sessionTeardownCount` — without this,
    // Progress's bests/history stayed frozen at their first bootstrap for
    // the rest of the app session. See `MinesweeperProgressViewModel.refresh()`.
    @Environment(\.gameSessionTeardownCount) private var sessionTeardownCount

    public init(viewModel: MinesweeperProgressViewModel, rootViewModel: GameRootViewModel<AppRoute>) {
        _viewModel = State(initialValue: viewModel)
        self.rootViewModel = rootViewModel
    }

    public var body: some View {
        ProgressScreen(model: viewModel.model, rootViewModel: rootViewModel)
            // Leaf-view one-shot bootstrap — `.task` is the idiomatic choice
            // here (mirrors every other MS hub's leaf bootstrap).
            .task { await viewModel.bootstrap() }
            .onChange(of: sessionTeardownCount) { _, _ in Task { await viewModel.refresh() } }
    }
}
