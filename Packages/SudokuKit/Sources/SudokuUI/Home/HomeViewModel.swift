// HomeViewModel — owns the 4-mode card list + drives navigation.
//
// Per design.md §How.5.4. Routing is delegated through a binding so the
// same VM works inside RootView (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).

public import Foundation

public enum HomeMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case daily
    case practice
    case leaderboard
    case settings

    public var id: String { rawValue }
}

@MainActor
@Observable
public final class HomeViewModel {
    public var path: [AppRoute] = []

    public init(path: [AppRoute] = []) {
        self.path = path
    }

    public func select(_ mode: HomeMode) {
        switch mode {
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .leaderboard:
            path.append(.leaderboard(leaderboardId: ""))
        case .settings:
            path.append(.settings)
        }
    }
}
