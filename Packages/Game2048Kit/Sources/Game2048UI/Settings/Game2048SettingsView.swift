// Game2048SettingsView — Tiles2048 Settings.
//
// Mirrors MinesweeperKit/SettingsView. Wraps `GameShellUI.SettingsScreen`
// (shared grouped-Form chrome). Mounts the shared `RemoveAdsRow` /
// `AdsRemovedRow` / `RestorePurchasesRow` under a `Section("Purchases")`.
// Game Center entry row mirrors the #492-merged pattern.
//
// Banner is injected by LiveRouteFactory (Epic 5 pattern; SettingsKit /
// GameShellUI must NOT import MonetizationUI).

public import SwiftUI
public import MonetizationUI
public import SettingsUI
// #560: shared `GameCenterDashboard.present()` (was the per-app copy).
internal import GameCenterClient

public struct Game2048SettingsView<Banner: View>: View {
    private let version: String
    private let clearCache: @MainActor () async -> Void
    private let monetizationController: MonetizationStateController?
    private let notices: SettingsNoticesConfig?
    private let banner: Banner

    public init(
        version: String = "1.0.0",
        clearCache: @escaping @MainActor () async -> Void = {},
        monetizationController: MonetizationStateController? = nil,
        notices: SettingsNoticesConfig? = nil,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.version = version
        self.clearCache = clearCache
        self.monetizationController = monetizationController
        self.notices = notices
        self.banner = banner()
    }

    public var body: some View {
        SettingsScreen(
            version: version,
            tint: .accentColor,
            clearCache: clearCache,
            // 2048 v1.0 has no reminder wiring yet (M4 scope).
            reminderSettings: nil,
            // 2048 v1.0 has no audio wiring (M5 scope if added).
            audioSettings: nil,
            notices: notices,
            // Game Center entry: present native GC dashboard (#492 pattern).
            onGameCenter: { GameCenterDashboard.present() },
            purchases: {
                if let controller = monetizationController {
                    Section("Purchases") {
                        if controller.hasPurchasedRemoveAds {
                            AdsRemovedRow(tintColor: .accentColor)
                        } else {
                            RemoveAdsRow(
                                controller: controller,
                                tintColor: .accentColor
                            )
                        }
                        RestorePurchasesRow(
                            controller: controller,
                            tintColor: .accentColor
                        )
                    }
                }
            },
            banner: { self.banner }
        )
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview {
    NavigationStack {
        Game2048SettingsView()
    }
}
