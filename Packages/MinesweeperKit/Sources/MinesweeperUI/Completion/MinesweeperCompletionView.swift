// MinesweeperCompletionView — Minesweeper's post-game result surface (#292).
// Thin wrapper over the shared `GameShellUI.CompletionScreen` body (#418).
//
// Minesweeper owns its PRESENTATION: this view is mounted as a full-board
// `.overlay` in place of the old inline `terminalOverlay` (see
// MinesweeperBoardView, #388) — MS's board owns its win/lose state inline and
// has no completion route, so the surface mounts over the board rather than via
// a pushed AppRoute (the difference from Sudoku's route-pushed Completion;
// route-pushed MS Completion deferred — #386).
//
// It injects the win/loss hero outcome and supplies the action stack.
//
// SDD-003 Epic 4: actions now inject ONLY a Close button (View Leaderboard /
// Retry / New Game removed at this injection site per spec note). `onClose`
// dismisses the overlay (MinesweeperBoardView sets `completionViewModel = nil`).
// Minesweeper has no mistake concept → `mistakeCount: nil` (row absent).
// #698: the leaderboard zone's dead fetch/present machinery was deleted from
// both the VM and the shared `CompletionScreen`. Themed via `\.theme` tokens.

public import SwiftUI
import GameShellUI
// #814: `ReminderPrimerCoordinator` appears in this view's public init and
// `ReminderPrimerSheet` in its sheet — both live in SettingsUI (mirrors
// Sudoku's CompletionView import note, #556).
public import SettingsUI

public struct MinesweeperCompletionView: View {
    @Bindable private var viewModel: MinesweeperCompletionViewModel
    @Environment(\.theme) private var theme

    // #814 (mirrors Sudoku's #287 Phase 2): optional daily-ready reminder
    // primer. Non-nil ONLY on a DAILY WIN (MinesweeperBoardView /
    // LiveRouteFactory gate on mode + outcome), so a Practice game, a loss —
    // and every existing snapshot fixture that omits this param — renders
    // byte-identically (no affordance, no sheet).
    @State private var reminderPrimer: ReminderPrimerCoordinator?

    /// SDD-003 Epic 4: dismiss the completion overlay. Wired by
    /// MinesweeperBoardView to `completionViewModel = nil`.
    private let onClose: (() -> Void)?
    /// #386: when re-viewing an already-solved daily there is no stored elapsed
    /// (MS has no save-flow, #284), so the hero OMITS the time row entirely (the
    /// player's real ranked time still appears in the leaderboard slice). The
    /// route-pushed re-opened-daily surface passes `false`; the live post-game
    /// overlay leaves it `true` and formats the just-played `elapsedSeconds`.
    private let showsElapsedTime: Bool

    public init(
        viewModel: MinesweeperCompletionViewModel,
        reminderPrimer: ReminderPrimerCoordinator? = nil,
        onClose: (() -> Void)? = nil,
        showsElapsedTime: Bool = true
    ) {
        self.viewModel = viewModel
        self._reminderPrimer = State(initialValue: reminderPrimer)
        self.onClose = onClose
        self.showsElapsedTime = showsElapsedTime
    }

    public var body: some View {
        CompletionScreen(
            outcome: outcome,
            elapsedLabel: elapsedLabel,
            mistakeCount: nil,
            actions: { closeButton },
            footer: { reminderAffordance }
        )
        .sheet(isPresented: reminderSheetBinding) {
            if let reminderPrimer {
                ReminderPrimerSheet(
                    copy: reminderPrimer.primerCopy,
                    isRequesting: reminderPrimer.isRequesting,
                    onAccept: { Task { await reminderPrimer.acceptPrimer() } },
                    onDecline: { reminderPrimer.declinePrimer() }
                )
                .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Reminder affordance (#814, mirrors Sudoku's flow S02)

    // The "Remind me when tomorrow's boards are ready" row. Tapping it presents
    // the soft primer (S03). Shown only for a Daily win (the caller gates via
    // `reminderPrimer` nil-ness) and only while reminders are not yet
    // authorized — once granted there is nothing left to ask. Structurally
    // identical to Sudoku's `CompletionView.reminderAffordance`; only the row
    // title copy is per-game ("boards" vs "puzzle").
    @ViewBuilder
    private var reminderAffordance: some View {
        if let reminderPrimer, reminderPrimer.status == .notDetermined {
            Button {
                Task { await reminderPrimer.presentPrimer() }
            } label: {
                // spacing-exempt: 12pt (icon-to-text gap) mirrors Sudoku's
                // affordance row byte-for-byte — same pre-`SpacingTokens`
                // rationale as its #762 PR2 exemption.
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(theme.accent.primary.resolved)
                    // spacing-exempt: 2pt (title-to-subtitle gap) — same
                    // rationale as above.
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me when tomorrow's boards are ready")
                            .font(.body.weight(.medium))
                            .foregroundStyle(theme.text.primary.resolved)
                            .multilineTextAlignment(.leading)
                        Text("A gentle daily nudge, default 9 AM — adjustable in Settings")
                            .font(.caption)
                            .foregroundStyle(theme.text.secondary.resolved)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundStyle(theme.text.tertiary.resolved)
                }
                // spacing-exempt: 14pt (row padding) mirrors Sudoku's
                // affordance row (#762 PR2 exemption there).
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
            }
            .buttonStyle(.plain)
        }
    }

    // Bridges the optional coordinator's `isPrimerPresented` to the sheet. With
    // no coordinator wired the binding is inert (always false → no sheet).
    private var reminderSheetBinding: Binding<Bool> {
        Binding(
            get: { reminderPrimer?.isPrimerPresented ?? false },
            set: { reminderPrimer?.isPrimerPresented = $0 }
        )
    }

    // MARK: - Outcome (win / loss)

    private var outcome: CompletionOutcome {
        if viewModel.didWin {
            CompletionOutcome(
                kind: .success,
                systemImage: "checkmark.circle.fill",
                title: "You won",
                // No elapsed → terse "You won" a11y label (re-opened daily, #386).
                accessibilityLabel: elapsedLabel.map { Text("You won in \($0)") }
                    ?? Text("You won")
            )
        } else {
            CompletionOutcome(
                kind: .failure,
                systemImage: "burst.fill",
                title: "Boom",
                accessibilityLabel: elapsedLabel.map { Text("Boom. Lasted \($0)") }
                    ?? Text("Boom")
            )
        }
    }

    // MARK: - CTAs (SDD-003 Epic 4: Close only)

    // View Leaderboard, Retry, and New Game removed at this injection site per
    // the spec note: "移除發生在各 app 的注入點". GC entry-point relocation is an
    // open product question (see section 7 of the impl report / OQ-GC-001).
    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            Button {
                onClose()
            } label: {
                Text("Close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    // MARK: - Formatting

    /// Hero subtitle. `nil` when there's no stored elapsed (re-opened solved
    /// daily, #386) so the shared body omits the time row entirely.
    private var elapsedLabel: String? {
        showsElapsedTime ? timeLabel(viewModel.elapsedSeconds) : nil
    }

    private func timeLabel(_ total: Int) -> String {
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
