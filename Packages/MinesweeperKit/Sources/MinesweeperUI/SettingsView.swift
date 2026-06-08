// SettingsView — Minesweeper Settings.
//
// Wraps `GameShellUI.SettingsShellView` to inherit the shared grouped-Form
// chrome (PR X4).
//
// MS monetization wire Phase 3 (2026-06-03): mounts the shared
// `RemoveAdsRow` / `AdsRemovedRow` / `RestorePurchasesRow` from
// `MonetizationUI` (PR #249) under a `Section("Purchases")`. The host
// passes a `MonetizationStateController` constructed against the MS ASC
// productId. Tint is `.accentColor` — MS has no theme tokens yet.
//
// #277: drops the "Coming soon" stub. About(Version) + Storage(Clear cache)
// now reuse the shared `GameShellUI.SettingsAboutVersionRow` /
// `SettingsStorageSection` — the same building blocks Sudoku adopts. The host
// (LiveRouteFactory) supplies the version string (Bundle.main) and an async
// clear-cache closure wired to MS persistence via `PersistenceProtocol`.
// Clear-cache is parity-only until MS save-flow lands (latestInProgress()
// returns nil today), but it IS wired to the real protocol method, not a
// fake button. Tint is `.accentColor` — MS has no theme.

public import SwiftUI
public import MonetizationUI
// #331: `public` (was `internal`) — `SettingsNoticesConfig` now appears in
// SettingsView's public init signature, so the import must be public.
public import GameShellUI

public struct SettingsView: View {
    private let version: String
    private let clearCache: @MainActor () async -> Void
    private let monetizationController: MonetizationStateController?
    // #331: shared Notices section inputs, app-injected by the host. Defaulted
    // nil so previews / tests keep the byte-identical screen.
    private let notices: SettingsNoticesConfig?

    public init(
        version: String = "1.0.0",
        clearCache: @escaping @MainActor () async -> Void = {},
        monetizationController: MonetizationStateController? = nil,
        notices: SettingsNoticesConfig? = nil
    ) {
        self.version = version
        self.clearCache = clearCache
        self.monetizationController = monetizationController
        self.notices = notices
    }

    public var body: some View {
        SettingsShellView(title: "Settings") {
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

            Section("About") {
                SettingsAboutVersionRow(version: version, tintColor: .accentColor)
            }

            // #331: shared Notices / 宣告 section. Same building block Sudoku
            // adopts; URLs + copyright app-injected via the config. Tint is
            // `.accentColor` — MS has no theme tokens yet.
            if let notices {
                SettingsNoticesSection(tintColor: .accentColor, config: notices)
            }

            SettingsStorageSection(clearCache: clearCache)
        }
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
