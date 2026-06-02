// SettingsView — Minesweeper Settings placeholder.
//
// Wraps `GameShellUI.SettingsShellView` to inherit the shared grouped-Form
// chrome (PR X4). No real rows this round — just a "Coming soon" hint so
// the destination is non-empty. IAP / About / Storage rows land once
// Minesweeper's product surface is designed.

public import SwiftUI
internal import GameShellUI

public struct SettingsView: View {
    public init() {}

    public var body: some View {
        SettingsShellView(title: "Settings") {
            Section {
                Text("Coming soon")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
