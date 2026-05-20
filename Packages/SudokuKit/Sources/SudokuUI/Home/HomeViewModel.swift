// HomeViewModel — owns the 4-mode card list + drives navigation.
//
// Per design.md §How.5.4. Routing is delegated through a binding so the
// same VM works inside RootView (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).

public import Foundation
public import SwiftUI
import GameCenterClient

public enum HomeMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case daily
    case practice
    case leaderboard
    case settings

    public var id: String { rawValue }

    /// Canonical 1:1 mapping from a Home mode to the navigation destination.
    /// Shared by `HomeViewModel.select(_:)` and the Mac sidebar in `RootView`
    /// so both entry points push the same route.
    public var appRoute: AppRoute {
        switch self {
        case .daily:
            return .daily
        case .practice:
            return .practice
        case .leaderboard:
            return .leaderboard(leaderboardId: LeaderboardIDs.id(for: .dailyEasy))
        case .settings:
            return .settings
        }
    }
}

@MainActor
@Observable
public final class HomeViewModel {
    /// Local fallback path — used when no external binding is supplied
    /// (previews, unit tests, AppComposition's standalone factory). When the
    /// owning view (e.g. `RootView`) hoists its own `[AppRoute]`, it passes
    /// a `Binding` via `init(path:)` and `select(_:)` mutates THAT binding,
    /// so the same array drives `NavigationStack`.
    public var path: [AppRoute] = []

    @ObservationIgnored
    private let externalPath: Binding<[AppRoute]>?

    public init(path: Binding<[AppRoute]>? = nil) {
        self.externalPath = path
    }

    public func select(_ mode: HomeMode) {
        if let externalPath {
            externalPath.wrappedValue.append(mode.appRoute)
        } else {
            path.append(mode.appRoute)
        }
    }
}
