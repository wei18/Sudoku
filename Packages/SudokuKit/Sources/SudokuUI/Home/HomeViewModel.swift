// HomeViewModel — owns the 4-mode card list + drives navigation.
//
// Per docs/v1/design.md §How.5.4. Routing is delegated through a binding so the
// same VM works inside RootView (bound to its `path`) and standalone in
// previews / unit tests (bound to a local stub array).

public import Foundation
public import SwiftUI

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
    /// Private fallback storage used only when no external binding is
    /// supplied (previews / unit tests). When `RootView` hoists its own
    /// `[AppRoute]` and passes a `Binding` via `init(path:)`, this stays
    /// empty and `path` reads/writes through `externalPath` instead.
    private var localPath: [AppRoute] = []

    @ObservationIgnored
    private let externalPath: Binding<[AppRoute]>?

    /// Single public view of the navigation path. Routes to the external
    /// binding when one was injected; otherwise falls back to the local
    /// stub array. Callers do not need to know which mode is active.
    public var path: [AppRoute] {
        get { externalPath?.wrappedValue ?? localPath }
        set {
            if let externalPath {
                externalPath.wrappedValue = newValue
            } else {
                localPath = newValue
            }
        }
    }

    public init(path: Binding<[AppRoute]>? = nil) {
        self.externalPath = path
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
