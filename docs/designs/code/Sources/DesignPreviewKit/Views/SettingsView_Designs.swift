// DESIGN PREVIEW ONLY — docs/designs/code/Views/SettingsView_Designs.swift
//
// Extracted from docs/designs/08-settings.md §c. Native Form / Section; no
// custom token usage required beyond the GC status icon color.

import SwiftUI

public struct SettingsView_Designs: View {

    public enum GCAuth: Equatable {
        case authenticated(displayName: String)
        case unauthenticated
        case restricted
    }

    public let gc: GCAuth
    public let solvedCount: Int
    public let version: String

    public init(
        gc: GCAuth = .authenticated(displayName: "Wei"),
        solvedCount: Int = 214,
        version: String = "1.0.0 (42)"
    ) {
        self.gc = gc
        self.solvedCount = solvedCount
        self.version = version
    }

    public var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Label("Game Center", systemImage: gcIconName)
                        .foregroundStyle(gcIconColor)
                    Spacer()
                    Text(gcStatusText).foregroundStyle(DesignTokens.textSecondary)
                }
            }

            Section("Statistics") {
                LabeledContent("Puzzles solved", value: "\(solvedCount)")
            }

            Section("Appearance") {
                LabeledContent("Language", value: "System (English)")
            }

            Section("Storage") {
                Button("Clear cache", role: .destructive) { }
            }

            Section("About") {
                LabeledContent("Version", value: version)
                LabeledContent("Generator", value: "v1")
                NavigationLink("Privacy policy") { Text("Privacy stub") }
            }
        }
        .navigationTitle("Settings")
    }

    private var gcIconName: String {
        switch gc {
        case .authenticated: "person.crop.circle.badge.checkmark"
        case .unauthenticated, .restricted: "person.crop.circle.badge.questionmark"
        }
    }
    private var gcIconColor: Color {
        switch gc {
        case .authenticated: DesignTokens.statusSuccess
        case .unauthenticated, .restricted: DesignTokens.statusWarning
        }
    }
    private var gcStatusText: LocalizedStringKey {
        switch gc {
        case .authenticated(let n): "Signed in: \(n)"
        case .unauthenticated: "Not signed in"
        case .restricted: "Restricted"
        }
    }
}

#Preview("Settings — iPhone, light, en") {
    NavigationStack { SettingsView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
