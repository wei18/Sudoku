// LiveRouteFactory+Helpers.swift — static helpers extracted from
// LiveRouteFactory (SDD-003 Epic 8 pushed the main file over the 400-line
// ceiling; extraction per the repo convention instead of a file-wide
// swiftlint disable).

internal import SwiftUI
// #814: `bannerSlot()` moved here from LiveRouteFactory.swift (400-line
// ceiling).
internal import MonetizationUI
internal import MinesweeperUI
internal import GameShellUI
internal import SettingsUI
internal import Foundation

extension LiveRouteFactory {

    // MARK: - Banner helper

    /// Epic 5: banner slot for non-Board screens (Today/Practice tab roots +
    /// Settings). The session model in the environment decides whether the
    /// slot shows (#1058).
    ///
    /// #1020: `static` (not an instance method) so `Live+TabRoots.swift`'s
    /// Today/Practice tab-root builder — which has no `LiveRouteFactory`
    /// instance to call through, only the wired `GameDeps` bag — can reuse
    /// the exact same banner instead of re-deriving it.
    @MainActor
    // #851: was relying on `BannerSlotView`'s bare default (`.clear`) — the
    // #468 Epic 5 theming note above already flagged this as unfinished
    // ("if MS adopts per-theme accents, pass theme tokens here like Sudoku's
    // RouteFactory.themedBanner()"). Now does exactly that, mirroring
    // `MinesweeperBoardView.themedBanner`'s `theme.surface.background.resolved`
    // so the Today/Practice/Settings banner slot matches the themed Board
    // banner instead of depending on an un-themed transparent default.
    static func bannerSlot() -> some View {
        BannerSlotView(
            isSuppressed: false,
            backgroundColor: MinesweeperTheme().surface.background.resolved,
            // Padding lives inside `BannerSlotView` so a hidden slot collapses
            // to zero height.
            horizontalPadding: 16,
            verticalPadding: 12
        )
    }
    /// acknowledgements row deep-links to the app's iOS Settings page where
    /// LicensePlist's `Settings.bundle` surfaces (omitted on macOS, no
    /// deep-link); copyright derived locally; privacy/support URLs unwired
    /// pending a canonical public URL (see #331 meeting note).
    @MainActor
    internal static func makeSettingsNotices() -> SettingsNoticesConfig {
        let year = Calendar.current.component(.year, from: Date())
        var onAcknowledgements: (@MainActor () -> Void)?
        #if canImport(UIKit)
        onAcknowledgements = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
        return SettingsNoticesConfig(
            onAcknowledgements: onAcknowledgements,
            copyright: "© \(year) Wei"
        )
    }
}
