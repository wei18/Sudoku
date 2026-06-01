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

public import GameShellUI
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
        SettingsShellView(title: "Settings") {
            if let controller = monetizationController {
                Section("Purchases") {
                    if controller.hasPurchasedRemoveAds {
                        AdsRemovedRow()
                    } else {
                        RemoveAdsRow(controller: controller)
                    }
                    RestorePurchasesRow(controller: controller)
                }
            }

            Section("About") {
                // Issue #197: unify with Purchases section's HStack primitive
                // so `.formStyle(.grouped)` on macOS renders all rows as
                // full-width pills. `LabeledContent` lands on a 2-column
                // preferences layout that bypasses the pill background.
                AboutRow(systemImage: "info.circle", title: "Version", value: viewModel.appVersion)
                AboutRow(systemImage: "gearshape", title: "Generator", value: generatorLabel)
            }

            Section("Storage") {
                Button(role: .destructive) {
                    showClearCacheConfirmation = true
                } label: {
                    // HStack + Spacer stretches the label content so the
                    // grouped Form gives this row the same full-width pill
                    // treatment as the Purchases section's button rows
                    // (issue #197).
                    HStack {
                        Label("Clear cache", systemImage: "trash")
                        Spacer()
                    }
                }
            }
        }
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
                Image(systemName: "sparkles")
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

struct AdsRemovedRow: View {
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Label("Ads Removed", systemImage: "checkmark.seal.fill")
                .foregroundStyle(theme.accent.primary.resolved)
            Spacer()
            Text("Active")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ads removed. Active.")
    }
}

/// Static About row matching the icon-left / label / spacer / value-right
/// shape of `RemoveAdsRow` so `.formStyle(.grouped)` renders both sections
/// with the same full-width pill background on macOS (issue #197).
struct AboutRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let value: String
    @Environment(\.theme) private var theme

    var body: some View {
        HStack {
            Image(systemName: systemImage)
                .foregroundStyle(theme.accent.primary.resolved)
            Text(title)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
