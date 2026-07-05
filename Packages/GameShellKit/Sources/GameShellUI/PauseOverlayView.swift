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
        title: LocalizedStringKey = "leave.game.title",
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
            // Original pause mask — a full blur that hides the board (anti-cheat)
            // so the puzzle can't be studied while the clock is stopped. Fills the
            // whole screen; tap outside the card = resume.
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
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
                // Resume is the primary/safe action — solid fill so it clearly
                // outweighs the subtle destructive Leave (avoids accidental leave).
                .buttonStyle(.borderedProminent)
                // Brand accent, not the system-blue default — each app themes it
                // (Sudoku sage-green / Minesweeper steel-blue).
                .tint(theme.accent.primary.resolved)
                .accessibilityIdentifier("game.pause.resume")
                // Leave — destructive, only when the caller wires onLeave.
                if let onLeave {
                    Button(role: .destructive, action: onLeave) {
                        Text(leaveLabel)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(theme.status.error.resolved)
                }
            }
            .padding(24)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
            // Contain the card — a destructive confirmation shouldn't span the
            // full screen width.
            .frame(maxWidth: 340)
            .padding(.horizontal, 24)
        }
        // #680: without this, the board underneath stays LIVE in the a11y
        // tree — VoiceOver users swiping the paused screen land on dozens of
        // stale board-cell buttons interleaved with Resume/Leave. `.isModal`
        // tells the accessibility system this subtree is the only reachable
        // content while presented; sim-verified via `idb ui describe-all`
        // (both apps) that it alone drops every sibling board/digit-pad
        // element from the reported tree — no manual `.accessibilityHidden`
        // plumbing needed at the board mount sites.
        .accessibilityAddTraits(.isModal)
    }
}
