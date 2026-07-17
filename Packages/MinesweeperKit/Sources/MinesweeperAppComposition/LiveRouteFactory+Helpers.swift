// LiveRouteFactory+Helpers.swift — static helpers extracted from
// LiveRouteFactory (SDD-003 Epic 8 pushed the main file over the 400-line
// ceiling; extraction per the repo convention instead of a file-wide
// swiftlint disable).

internal import SwiftUI
internal import MonetizationUI
// #814: `bannerSlot()` moved here from LiveRouteFactory.swift (400-line
// ceiling); it binds the `adProvider` / `adGate` existentials (MonetizationCore).
internal import MonetizationCore
internal import MinesweeperUI
internal import GameShellUI
internal import SettingsUI
internal import Foundation

extension LiveRouteFactory {

    // MARK: - Banner helper

    /// Epic 5: banner slot for non-Home, non-Board screens. The cast from
    /// `AdProvider` → `BannerViewProviding` follows the §9.1 pattern (keeps
    /// MinesweeperAppComposition off GoogleMobileAds). When adProvider / adGate
    /// are nil (preview / test), the slot itself is not created — the caller
    /// passes EmptyView via the `banner: {}` default instead.
    @MainActor
    // #851: was relying on `BannerSlotView`'s bare default (`.clear`) — the
    // #468 Epic 5 theming note above already flagged this as unfinished
    // ("if MS adopts per-theme accents, pass theme tokens here like Sudoku's
    // RouteFactory.themedBanner()"). Now does exactly that, mirroring
    // `MinesweeperBoardView.themedBanner`'s `theme.surface.background.resolved`
    // so the Daily/Practice/Settings banner slot matches the themed Home/Board
    // banner instead of depending on an un-themed transparent default.
    func bannerSlot() -> some View {
        if let adProvider, let adGate {
            AnyView(
                BannerSlotView(
                    adProvider: adProvider,
                    adGate: adGate,
                    bannerHost: adProvider as? any BannerViewProviding,
                    backgroundColor: MinesweeperTheme().surface.background.resolved
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            )
        } else {
            AnyView(EmptyView())
        }
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
