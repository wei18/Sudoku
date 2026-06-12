// CompletionView — Sudoku's post-solve surface. Thin wrapper over the shared
// `GameShellUI.CompletionScreen` body (#418).
//
// Sudoku owns its PRESENTATION: this view is rendered inside the pushed
// `.completion` AppRoute (RouteFactory). It maps the leaderboard-fetch VM state
// onto the shared `CompletionScreenState`, injects the solve-only success hero,
// the "View full leaderboard" CTA, and (Daily-only) the reminder primer
// affordance + sheet (#287). The leaderboard/Game Center coupling stays here:
// the shared shell never imports GameCenterClient.
//
// SDD-003 Epic 4: actions now inject ONLY a Close button (Retry / New Game /
// Leaderboard removed from this injection site per spec note). The close action
// pops the navigation stack via `onClose`, supplied by RouteFactory.
//
// State variants (mapped onto the shared body):
//   .loading              → ProgressView
//   .loaded(slice)        → hero + leaderboard rows + "View full" CTA
//   .unauthenticated      → hero + sign-in CTA
//   .noLeaderboard        → hero + neutral "not ranked" note (Practice, #383)
//   .failed               → hero + retry CTA

public import SwiftUI
import GameCenterClient
import GameShellUI
// refactor/settingskit-target: `ReminderPrimerSheet` moved out of GameShellUI
// into SettingsUI. Used only inside the view body, so the import is internal.
internal import SettingsUI

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
            state: screenState,
            onSignIn: { viewModel.viewLeaderboardTapped() },
            onRetryLeaderboard: { Task { await viewModel.retry() } },
            loadedAccessory: { viewLeaderboardButton },
            actions: { closeButton },
            footer: { reminderAffordance }
        )
        .onAppear { Task { await viewModel.bootstrap() } }
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

    // Maps the leaderboard-fetch VM state onto the shared screen state. The
    // `LeaderboardSlice` (a GameCenterClient type) is flattened to plain
    // `CompletionLeaderboardRow` values here so the shared shell stays GC-free.
    private var screenState: CompletionScreenState {
        switch viewModel.state {
        case .loading:
            .loading
        case .loaded(let slice):
            .loaded(slice.entries.map { entry in
                CompletionLeaderboardRow(
                    rank: entry.rank,
                    displayName: entry.player.displayName,
                    score: scoreLabel(entry.score)
                )
            })
        case .unauthenticated:
            .unauthenticated
        case .noLeaderboard:
            .noLeaderboard
        case .failed:
            .failed
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
    // component). `nil` in snapshot tests → button simply absent.
    @ViewBuilder
    private var closeButton: some View {
        if let onClose {
            Button {
                onClose()
            } label: {
                Text("completion.close")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    private var viewLeaderboardButton: some View {
        Button {
            viewModel.viewLeaderboardTapped()
        } label: {
            Label("View full leaderboard", systemImage: "trophy.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    private var elapsedLabel: String {
        let total = viewModel.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func scoreLabel(_ seconds: Int) -> String {
        let minutes = seconds / 60
        let rem = seconds % 60
        return String(format: "%d:%02d", minutes, rem)
    }
}
