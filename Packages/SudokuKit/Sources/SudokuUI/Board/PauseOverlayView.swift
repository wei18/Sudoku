// PauseOverlayView — "Tap to resume" cover when the session is paused.
//
// Per docs/designs/05-board.md §b.3 — full-cover `.ultraThinMaterial` blur
// over the board with a centered CTA. No auto-resume on scenePhase (§How.5.5).

import SwiftUI

struct PauseOverlayView: View {
    let onResume: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Button(action: onResume) {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(theme.accent.primary.resolved)
                    Text("Tap to resume")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel("Tap to resume")
        }
    }
}
