// HomeViewModel — owns the 4-mode card list + drives navigation.
//
// Per docs/v1/design.md §How.5.4. Routing is delegated through a binding so the
// same VM works inside RootView (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).

public import Foundation
public import SwiftUI
import GameShellUI

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
    /// Navigation path store (issue #240): routes through an injected
    /// `Binding<[AppRoute]>` when `RootView` hoists its own array via
    /// `init(path:)`, otherwise a local stub (previews / unit tests).
    private var routePath: RoutePath<AppRoute>

    /// Single public view of the navigation path. Callers do not need to know
    /// which mode (injected binding / local stub) is active.
    public var path: [AppRoute] {
        get { routePath.effectivePath }
        set { routePath.effectivePath = newValue }
    }

    public init(path: Binding<[AppRoute]>? = nil) {
        self.routePath = RoutePath(path)
    }

    public func select(_ mode: HomeMode) {
        // `.leaderboard` is a side-effect (presents Apple's native Game Center
        // dashboard) rather than a stack push — issue #49 (2026-05-20).
        switch mode {
        case .daily:
            path.append(.daily)
        case .practice:
            path.append(.practice)
        case .settings:
            path.append(.settings)
        case .leaderboard:
            GameCenterDashboard.present()
        }
    }
}
