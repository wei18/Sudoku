// DESIGN PREVIEW ONLY — docs/designs/code/Components/GeneratorExhaustedAlert.swift
//
// `.exhausted` alert spec, rendered as a stub View so it's snapshottable.
// Source: docs/designs/03-daily-hub.md §d (Alert row) + 04-practice-hub.md §d.
// VoiceOver = .assertive (§How.6.3 generator defect).
//
// SUPERSEDED for `surface: .daily` (#768): the shipped Daily hub no longer
// presents `.exhausted` as a system alert — it renders inline via an
// empty-state block in DailyHubView.swift's `empty:` builder (same copy,
// same Practice/Cancel actions, no separate modal). Kept as a historical
// snapshot fixture, not redesigned. `surface: .practice` is untouched by
// #768 (Practice Hub's own draw-failure path is separately unrelated).

import SwiftUI

public struct GeneratorExhaustedAlert: View {
    /// "daily" vs "practice" tail copy varies subtly.
    public enum Surface { case daily, practice }
    public let surface: Surface

    public init(surface: Surface = .daily) {
        self.surface = surface
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.statusWarning)
            Text("Couldn't generate today's puzzle")
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
                .multilineTextAlignment(.center)
            Text("Try a different difficulty, or come back tomorrow.")
                .font(.callout)
                .foregroundStyle(DesignTokens.textSecondary)
                .multilineTextAlignment(.center)
            HStack(spacing: DesignTokens.Spacing.md) {
                if surface == .practice {
                    Button("Switch difficulty") { }
                        .buttonStyle(.bordered)
                }
                Button(surface == .practice ? "Try again" : "Try another difficulty") { }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentPrimary)
            }
        }
        .padding(DesignTokens.Spacing.xl)
        .frame(maxWidth: 320)
        .background(DesignTokens.surfaceElevated, in: .rect(cornerRadius: DesignTokens.Radius.card))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isModal)
    }
}

#Preview("GeneratorExhaustedAlert — daily") {
    GeneratorExhaustedAlert(surface: .daily)
        .padding()
        .background(DesignTokens.surfaceBackground)
}
