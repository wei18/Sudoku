// Spike1019OverlayStandIn — THROWAWAY. See Spike1019RootView.swift for
// context. Stand-in for PauseOverlayView / the completion surface — a
// full-cover blur + centered card with a dismiss CTA. Mirrors the real
// overlays' `.accessibilityAddTraits(.isModal)` so this spike also proves
// whether that trait alone is sufficient once the board is hosted inside a
// `sidebarAdaptable` TabView rather than a NavigationSplitView.
//
// `idPrefix` distinguishes the two mount strategies' evidence in
// `ui_describe_all` output ("naive.dismiss" vs "hoisted.dismiss").

public import SwiftUI

struct Spike1019OverlayStandIn: View {
    let kind: Spike1019OverlayKind
    let idPrefix: String
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 16) {
                Text(kind == .pause ? "Paused" : "Completed")
                    .font(.title2.weight(.semibold))
                Text(
                    kind == .pause
                        ? "Spike stand-in for PauseOverlayView."
                        : "Spike stand-in for the Completion surface."
                )
                .font(.body)
                .multilineTextAlignment(.center)
                Button(kind == .pause ? "Resume" : "Close", action: onDismiss)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("spike.\(idPrefix).dismiss")
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: 340)
        }
        .accessibilityIdentifier("spike.\(idPrefix).overlay")
        // Mirrors PauseOverlayView's #680 `.isModal` trait.
        .accessibilityAddTraits(.isModal)
    }
}
