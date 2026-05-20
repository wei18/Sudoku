// GameCenterDashboard — present Apple's native Game Center leaderboards UI.
//
// Per issue #49 / docs/designs/07-leaderboard.md (2026-05-20 rewrite). The custom
// SwiftUI `LeaderboardView` has been retired; full leaderboard browsing now
// delegates to Apple's native dashboard (scope toggle, time-range filter,
// player profile drill-through, AX3 stacking, sign-in affordance — all
// handled by Apple).
//
// API choice: hybrid (see impl-notes §設計決定 Decision 1).
//   - `leaderboardId == nil` → `GKAccessPoint.shared.trigger(state: .leaderboards)`.
//     The public `GameCenterViewControllerState.leaderboards` case has no
//     associated values, so this is the only path for the "open the full
//     listing" entry point.
//   - `leaderboardId != nil` → present `GKGameCenterViewController(
//     leaderboardID:playerScope:timeScope:)` modally on the active window.
//     This is the only GameKit API that accepts a focused leaderboard ID.
//
// Both paths bottom out in Apple's UIKit/AppKit view controller, so we drop
// the SwiftUI representable bridge entirely and reach the active
// UIWindowScene / NSApplication.keyWindow directly.

import Foundation

#if canImport(GameKit)
import GameKit
#endif

#if canImport(UIKit)
import UIKit
#endif

#if canImport(AppKit)
import AppKit
#endif

public enum GameCenterDashboard {
    /// Present Apple's native Game Center leaderboards UI.
    /// - Parameter leaderboardId: Specific board to focus, or `nil` for the
    ///   full leaderboards listing (Home tab / Mac sidebar default).
    @MainActor
    public static func present(leaderboardId: String? = nil) {
        #if canImport(GameKit)
        if let id = leaderboardId {
            presentFocusedDashboard(leaderboardId: id)
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) { /* dismissed */ }
        }
        #else
        // Non-Apple platforms (Linux CI for pure-logic targets): no-op.
        _ = leaderboardId
        #endif
    }

    #if canImport(GameKit)
    @MainActor
    private static func presentFocusedDashboard(leaderboardId: String) {
        let controller = GKGameCenterViewController(
            leaderboardID: leaderboardId,
            playerScope: .global,
            timeScope: .allTime
        )
        // Apple requires the delegate to dismiss; route through a singleton.
        controller.gameCenterDelegate = GameCenterDashboardDismissProxy.shared

        #if canImport(UIKit)
        guard let presenter = activeUIPresenter() else { return }
        presenter.present(controller, animated: true)
        #elseif canImport(AppKit)
        guard let presenter = NSApplication.shared.keyWindow?.contentViewController
            ?? NSApplication.shared.mainWindow?.contentViewController
        else { return }
        presenter.presentAsSheet(controller)
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

#if canImport(GameKit)
@MainActor
private final class GameCenterDashboardDismissProxy: NSObject, @preconcurrency GKGameCenterControllerDelegate {
    static let shared = GameCenterDashboardDismissProxy()

    func gameCenterViewControllerDidFinish(_ gameCenterViewController: GKGameCenterViewController) {
        #if canImport(UIKit)
        gameCenterViewController.dismiss(animated: true)
        #elseif canImport(AppKit)
        gameCenterViewController.dismiss(nil)
        #endif
    }
}
#endif
