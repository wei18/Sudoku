// PauseOverlayView — shared "Tap to resume" cover shown while a game session
// is paused (#434).
//
// Extracted from SudokuUI's PauseOverlayView so both Sudoku and Minesweeper
// share one board-pause cover (per minesweeper-mirrors-sudoku +
// reusable-targets-over-duplication). The pause/resume LOGIC stays per-game in
// each app's GameViewModel (each owns its session actor + timer); only this
// presentational cover is shared.
//
// A full-cover `.ultraThinMaterial` blur over the board hides the minefield /
// grid so the player can't study it while the clock is stopped, with a centered
// resume CTA. No auto-resume on scenePhase — resume is an explicit tap.
//
// The resume label is injected as a `LocalizedStringKey` so each app resolves it
// from its OWN `Localizable.xcstrings` (Bundle.main), mirroring how
// `CompletionScreen` threads its app-divergent strings.

public import SwiftUI

public struct PauseOverlayView: View {
    private let resumeLabel: LocalizedStringKey
    private let onResume: () -> Void
    @Environment(\.theme) private var theme

    public init(
        resumeLabel: LocalizedStringKey = "Tap to resume",
        onResume: @escaping () -> Void
    ) {
        self.resumeLabel = resumeLabel
        self.onResume = onResume
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
            Button(action: onResume) {
                VStack(spacing: 12) {
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(theme.accent.primary.resolved)
                    Text(resumeLabel)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                }
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(Text(resumeLabel))
            // #510 Phase 3 (#633): stable, non-localized anchor so the E2E flow
            // can dismiss the pause cover in any locale (resumeLabel is
            // localized). Shared by both apps' boards (mirror principle).
            .accessibilityIdentifier("game.pause.resume")
        }
    }
}
