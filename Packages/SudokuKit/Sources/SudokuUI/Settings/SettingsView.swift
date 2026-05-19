// SettingsView — native Form with Account / Statistics / Storage / About.
//
// Per docs/designs/08-settings.md. No branding; HIG default Form chrome.

public import SwiftUI

public struct SettingsView: View {
    @Bindable private var viewModel: SettingsViewModel
    @State private var showClearCacheConfirmation = false
    @Environment(\.theme) private var theme

    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        Form {
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
