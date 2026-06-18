// CompletionView — Sudoku's post-solve surface. Thin wrapper over the shared
// `GameShellUI.CompletionScreen` body (#418).
//
// Sudoku owns its PRESENTATION: this view is rendered inside the pushed
// `.completion` AppRoute (RouteFactory). It injects the solve-only success
// hero, the Mistakes count, and (Daily-only) the reminder primer affordance +
// sheet (#287).
//
// SDD-003 Epic 4: the popup is Success/Failed · Time · Mistakes · Close only —
// `state: .hidden` renders no leaderboard zone, and `actions` injects ONLY a
// Close button (Retry / New Game / Leaderboard removed at this injection
// site). The VM's leaderboard fetch/mapping machinery is left intact but
// unrendered; GC entry-point relocation is an open product question (#468).

public import SwiftUI
import GameShellUI
// refactor/settingskit-target: `ReminderPrimerSheet` moved out of GameShellUI
// into SettingsUI. #556: `ReminderPrimerCoordinator` also moved here and appears
// in `CompletionView.init`'s public param, so this import is now public.
public import SettingsUI

public struct CompletionView: View {
    @Bindable private var viewModel: CompletionViewModel
    @Environment(\.theme) private var theme

    // #287 Phase 2: optional daily-ready reminder primer. Non-nil ONLY on a
    // Daily completion (LiveRouteFactory gates on the puzzleId), so a Practice
    // solve — and every existing snapshot fixture that omits this param —
    // renders byte-identically (no affordance, no sheet).
    @State private var reminderPrimer: ReminderPrimerCoordinator?

    // SDD-003 Epic 4: dismiss this screen. On the pushed `.completion` route
    // this removes the last stack entry. Supplied by RouteFactory / parent.
    // `nil` in previews / snapshot tests that don't need the action wired.
    private let onClose: (() -> Void)?

    public init(
        viewModel: CompletionViewModel,
        reminderPrimer: ReminderPrimerCoordinator? = nil,
        onClose: (() -> Void)? = nil
    ) {
        self.viewModel = viewModel
        self._reminderPrimer = State(initialValue: reminderPrimer)
        self.onClose = onClose
    }

    public var body: some View {
        CompletionScreen(
            outcome: CompletionOutcome(
                kind: .success,
                systemImage: "checkmark.circle.fill",
                title: "Solved!",
                accessibilityLabel: Text("Solved in \(elapsedLabel)")
            ),
            elapsedLabel: elapsedLabel,
            mistakeCount: viewModel.mistakeCount,
            // SDD-003 Epic 4: the popup carries no leaderboard zone (spec:
            // Success/Failed · Time · Mistakes · Close only). The VM's
            // leaderboard fetch/mapping machinery is intentionally left in
            // place but unrendered; GC entry-point relocation is an open
            // product question on #468.
            state: .hidden,
            onRetryLeaderboard: {},
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

    // The affordance row from flow S02 ("Remind me when tomorrow's puzzle is
    // ready"). Tapping it presents the soft primer (S03). Shown only for a
    // Daily solve and only while reminders are not yet authorized — once
    // granted there is nothing left to ask.
    @ViewBuilder
    private var reminderAffordance: some View {
        if let reminderPrimer, reminderPrimer.status == .notDetermined {
            Button {
                Task { await reminderPrimer.presentPrimer() }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "bell.badge")
                        .foregroundStyle(theme.accent.primary.resolved)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Remind me when tomorrow's puzzle is ready")
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

    // SDD-003 Epic 4: only Close is injected into actions; Retry / New Game /
    // Leaderboard CTAs removed at this injection site (not from the shared
    // component). `nil` in snapshot tests → button simply absent. "Close" is
    // a literal-as-key catalog entry (×7 locales), repo convention.
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

    private var elapsedLabel: String {
        let total = viewModel.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

}
