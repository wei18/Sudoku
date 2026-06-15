// Game2048GameCenterDashboard — present Apple's native Game Center
// leaderboards UI for Tiles2048.
//
// Near-verbatim mirror of `MinesweeperGameCenterDashboard` (#291).
// Full leaderboard browsing delegates to Apple's native dashboard.
// This is a modal side-effect, NOT an AppRoute.
//
// API choice (mirrors MS / Sudoku):
//   - `leaderboardId == nil` → `GKAccessPoint.shared.trigger(state: .leaderboards)`.
//   - `leaderboardId != nil` (iOS) → present `GKGameCenterViewController(
//     leaderboardID:playerScope:timeScope:)`.
//   - `leaderboardId != nil` (macOS) → collapses to generic listing
//     (same macOS 26 deprecation as MS / Sudoku #180).

import Foundation

#if canImport(GameKit)
import GameKit
#endif

#if canImport(UIKit)
import UIKit
#endif

public enum Game2048GameCenterDashboard {
    @MainActor
    public static func present(leaderboardId: String? = nil) {
        #if canImport(GameKit)
        if let id = leaderboardId {
            presentFocusedDashboard(leaderboardId: id)
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) { /* dismissed */ }
        }
        #else
        _ = leaderboardId
        #endif
    }

    #if canImport(GameKit)
    @MainActor
    private static func presentFocusedDashboard(leaderboardId: String) {
        #if os(macOS)
        _ = leaderboardId
        GKAccessPoint.shared.trigger(state: .leaderboards) { /* dismissed */ }
        #else
        let controller = GKGameCenterViewController(
            leaderboardID: leaderboardId,
            playerScope: .global,
            timeScope: .allTime
        )
        controller.gameCenterDelegate = Game2048GameCenterDashboardDismissProxy.shared
        #if canImport(UIKit)
        guard let presenter = activeUIPresenter() else { return }
        presenter.present(controller, animated: true)
        #endif
        #endif
    }
    #endif

    #if canImport(UIKit)
    @MainActor
    private static func activeUIPresenter() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? scenes.compactMap({ $0 as? UIWindowScene }).first
        guard let root = windowScene?.windows.first(where: \.isKeyWindow)?.rootViewController
            ?? windowScene?.windows.first?.rootViewController
        else { return nil }
        var presenter: UIViewController = root
        while let next = presenter.presentedViewController {
            presenter = next
        }
        return presenter
    }
    #endif
}

#if canImport(GameKit) && !os(macOS)
@MainActor
private final class Game2048GameCenterDashboardDismissProxy: NSObject, @preconcurrency GKGameCenterControllerDelegate {
    static let shared = Game2048GameCenterDashboardDismissProxy()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        #if canImport(UIKit)
        gameCenterViewController.dismiss(animated: true)
        #endif
    }
}
#endif
