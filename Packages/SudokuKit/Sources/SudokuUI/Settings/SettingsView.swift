// SettingsView — native Form with Account / Statistics / Storage / About.
//
// Per docs/designs/08-settings.md. No branding; HIG default Form chrome.
//
// v2.3.6: a new "Remove Ads" Section hosts two rows (Remove Ads CTA hidden
// once purchased; Restore Purchases always visible). Both rows flip to a
// `ProgressView` while the underlying async call is in flight; success /
// failure surfaces inline at the bottom of the Form via a Label row (no
// toast infra exists yet — see impl-notes §未決).

public import SwiftUI

public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    private let monetizationController: MonetizationStateController?
    @State private var showClearCacheConfirmation = false
    @Environment(\.theme) private var theme

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
                Section("Remove Ads") {
                    if !controller.hasPurchasedRemoveAds {
                        RemoveAdsRow(controller: controller)
                    }
                    RestorePurchasesRow(controller: controller)
                }

                if let message = monetizationMessage(for: controller) {
                    Section {
                        Label(message.text, systemImage: message.systemImage)
                            .foregroundStyle(message.tint(theme: theme))
                    }
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

            if let message = viewModel.clearCacheConfirmation {
                Section {
                    Label(message, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(theme.status.success.resolved)
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

    private struct MonetizationLabel {
        let text: String
        let systemImage: String
        let isSuccess: Bool

        func tint(theme: any Theme) -> Color {
            isSuccess ? theme.status.success.resolved : theme.status.error.resolved
        }
    }

    private func monetizationMessage(for controller: MonetizationStateController) -> MonetizationLabel? {
        switch controller.latestMessage {
        case .none: return nil
        case .adsRemoved:
            return MonetizationLabel(text: "Ads removed", systemImage: "checkmark.circle.fill", isSuccess: true)
        case .restored:
            return MonetizationLabel(text: "Restored", systemImage: "arrow.clockwise.circle.fill", isSuccess: true)
        case .failure(let reason):
            return MonetizationLabel(text: reason, systemImage: "exclamationmark.triangle.fill", isSuccess: false)
        }
    }
}

// MARK: - Rows

struct RemoveAdsRow: View {
    @Bindable var controller: MonetizationStateController

    var body: some View {
        Button {
            Task { await controller.purchaseRemoveAds() }
        } label: {
            HStack {
                Text("Remove Ads")
                Spacer()
                if controller.purchaseInFlight {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text(controller.removeAdsDisplayPrice)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .disabled(controller.purchaseInFlight)
        .accessibilityLabel("Remove Ads \(controller.removeAdsDisplayPrice)")
    }
}

struct RestorePurchasesRow: View {
    @Bindable var controller: MonetizationStateController

    var body: some View {
        Button {
            Task { await controller.restorePurchases() }
        } label: {
            HStack {
                Text("Restore Purchases")
                Spacer()
                if controller.restoreInFlight {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .disabled(controller.restoreInFlight)
    }
}
