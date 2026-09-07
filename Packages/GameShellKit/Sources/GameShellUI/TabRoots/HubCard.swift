// HubCard — standard-material card container for TODAY/PRACTICE/PROGRESS
// content-layer cards (#1021 Phase A, design.md §4.2: content-layer cards are
// NOT eligible for the Slider/Toggle transient-interaction glass exception,
// so they use `theme.surface.primary` — a standard material, never
// `glassEffect`).
//
// Corner radius matches `AchievementsRow.swift:60`'s existing standard-
// material card (`.rect(cornerRadius: 14)`) so every content-layer card in
// the app shares one radius.

public import SwiftUI

public struct HubCard<Content: View>: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.medium) private var padding

    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
    }
}
