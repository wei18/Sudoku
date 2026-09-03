// ProgressHostView — owns Sudoku's `ProgressViewModel` and re-renders the
// shared `GameAppKit.ProgressScreen` as it fills in (#1021 Phase D).
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

public struct ProgressHostView: View {
    @State private var viewModel: ProgressViewModel
    private let rootViewModel: GameRootViewModel<AppRoute>

    public init(viewModel: ProgressViewModel, rootViewModel: GameRootViewModel<AppRoute>) {
        _viewModel = State(initialValue: viewModel)
        self.rootViewModel = rootViewModel
    }

    public var body: some View {
        ProgressScreen(model: viewModel.model, rootViewModel: rootViewModel)
            // Leaf-view one-shot bootstrap — `.task` is the idiomatic choice
            // here (#607: leaf `.task` links clean; only the app-root
            // bootstrap is restricted to `.onAppear { Task }`).
            .task { await viewModel.bootstrap() }
    }
}
