// PauseOverlayView — shared pause menu shown while a game session is paused.
//
// Extracted from SudokuUI's PauseOverlayView so both Sudoku and Minesweeper
// share one board-pause cover (per minesweeper-mirrors-sudoku +
// reusable-targets-over-duplication). The pause/resume LOGIC stays per-game in
// each app's GameViewModel (each owns its session actor + timer); only this
// presentational cover is shared.
//
// A full-cover `.ultraThinMaterial` blur over the board hides the minefield /
// grid so the player can't study it while the clock is stopped. A centered
// menu card offers Resume (primary) and optionally Leave (destructive).
// Tapping the blurred backdrop also resumes — matches the prior tap-anywhere
// contract the E2E tests rely on (accessibilityIdentifier "game.pause.resume").
//
// String keys are injected as `LocalizedStringKey` so each app resolves them
// from its OWN `Localizable.xcstrings` (Bundle.main), mirroring how
// `CompletionScreen` threads app-divergent strings.

public import SwiftUI

public struct PauseOverlayView: View {
    private let title: LocalizedStringKey
    private let message: LocalizedStringKey
    private let leaveLabel: LocalizedStringKey
    private let onLeave: (() -> Void)?
    private let onResume: () -> Void
    @Environment(\.theme) private var theme

    public init(
        title: LocalizedStringKey = "game.paused",
        message: LocalizedStringKey = "leave.game.message",
        leaveLabel: LocalizedStringKey = "leave.game.leave",
        onLeave: (() -> Void)? = nil,
        onResume: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.leaveLabel = leaveLabel
        self.onLeave = onLeave
        self.onResume = onResume
    }

    public var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .onTapGesture { onResume() }
            VStack(spacing: 20) {
                Text(title)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(theme.text.primary.resolved)
                Text(message)
                    .font(.body)
                    .foregroundStyle(theme.text.secondary.resolved)
                    .multilineTextAlignment(.center)
                // Resume — primary CTA.
                // #510 Phase 3 (#633): stable, non-localized anchor so the E2E
                // flow can dismiss the pause cover in any locale.
                Button(action: onResume) {
                    Text("Resume")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("game.pause.resume")
                // Leave — destructive, only when the caller wires onLeave.
                if let onLeave {
                    Button(role: .destructive, action: onLeave) {
                        Text(leaveLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            .padding(32)
        }
    }
}
