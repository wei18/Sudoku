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
// About / Storage rows are deferred to a follow-up; not in scope here.

public import SwiftUI
public import MonetizationUI
internal import GameShellUI

public struct SettingsView: View {
    private let monetizationController: MonetizationStateController?

    public init(monetizationController: MonetizationStateController? = nil) {
        self.monetizationController = monetizationController
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
            } else {
                Section {
                    Text("Coming soon")
                        .foregroundStyle(.secondary)
                }
            }
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
