// SettingsView — native Form with Account / Statistics / Storage / About.
//
// Per docs/designs/08-settings.md. No branding; HIG default Form chrome.
//
// v2.3.6: a new "Remove Ads" Section hosts two rows (Remove Ads CTA hidden
// once purchased; Restore Purchases always visible). Both rows flip to a
// `ProgressView` while the underlying async call is in flight.
//
// v2.4.6: purchase/restore success/failure and clear-cache confirmation
// surface via `ToastController` (bottom-center capsule, mounted on
// `RootView`) instead of orphan `Label` rows in the Form. `latestMessage`
// on the controller stays as the VoiceOver source of truth; the visual
// surface is the toast overlay.

public import SwiftUI

public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    private let monetizationController: MonetizationStateController?
    @State private var showClearCacheConfirmation = false

    public init(
        viewModel: SettingsViewModel,
        monetizationController: MonetizationStateController? = nil
    ) {
        self.viewModel = viewModel
        self.monetizationController = monetizationController
    }

    public var body: some View {
        Form {
            if let controller = monetizationController {
                Section("Purchases") {
                    if !controller.hasPurchasedRemoveAds {
                        RemoveAdsRow(controller: controller)
                    }
                    RestorePurchasesRow(controller: controller)
                }
            }

            Section("About") {
                LabeledContent("Version", value: viewModel.appVersion)
                LabeledContent("Generator", value: generatorLabel)
            }

            Section("Storage") {
                Button("Clear cache", role: .destructive) {
                    showClearCacheConfirmation = true
                }
            }
        }
        .navigationTitle("Settings")
        .task { await viewModel.bootstrap() }
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
        .confirmationDialog(
            "Reset session cache",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear cache", role: .destructive) {
                Task { await viewModel.clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generated puzzles will be re-derived next play. Saved games are not affected.")
        }
    }

    private var generatorLabel: String {
        // `GeneratorVersion.v1.rawValue` == `"v1"` — already prefixed.
        viewModel.generatorVersion.rawValue
    }
}

// MARK: - Rows

struct RemoveAdsRow: View {
    @Bindable var controller: MonetizationStateController
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            Task { await controller.purchaseRemoveAds() }
        } label: {
            HStack {
                Image(systemName: "nosign")
                    .foregroundStyle(theme.accent.primary.resolved)
                Text("Remove Ads")
                Spacer()
                Group {
                    if controller.purchaseInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(controller.removeAdsDisplayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .disabled(controller.purchaseInFlight)
        .accessibilityLabel("Remove Ads \(controller.removeAdsDisplayPrice)")
    }
}

struct RestorePurchasesRow: View {
    @Bindable var controller: MonetizationStateController
    @Environment(\.theme) private var theme

    var body: some View {
        Button {
            Task { await controller.restorePurchases() }
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.accent.primary.resolved)
                Text("Restore Purchases")
                Spacer()
                Group {
                    if controller.restoreInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .disabled(controller.restoreInFlight)
    }
}
