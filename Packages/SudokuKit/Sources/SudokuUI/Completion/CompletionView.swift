// CompletionView — hero stat + (optional) leaderboard slice.
//
// Per docs/designs/06-completion.md. State variants:
//   .loading              → ProgressView
//   .loaded(slice)        → hero + leaderboard rows + "View full" CTA
//   .unauthenticated      → hero + sign-in CTA
//   .noLeaderboard        → hero + neutral "not ranked" note (Practice, #383)
//   .failed               → hero + retry CTA

public import SwiftUI
import GameCenterClient
import GameShellUI

public struct CompletionView: View {
    @Bindable private var viewModel: CompletionViewModel
    @Environment(\.theme) private var theme

    // #287 Phase 2: optional daily-ready reminder primer. Non-nil ONLY on a
    // Daily completion (LiveRouteFactory gates on the puzzleId), so a Practice
    // solve — and every existing snapshot fixture that omits this param —
    // renders byte-identically (no affordance, no sheet).
    @State private var reminderPrimer: ReminderPrimerCoordinator?

    public init(
        viewModel: CompletionViewModel,
        reminderPrimer: ReminderPrimerCoordinator? = nil
    ) {
        self.viewModel = viewModel
        self._reminderPrimer = State(initialValue: reminderPrimer)
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                content
                reminderAffordance
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        .task { await viewModel.bootstrap() }
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

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(theme.status.success.resolved)
            Text("Solved!")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
            Text(elapsedLabel)
                .font(.title3)
                .foregroundStyle(theme.text.secondary.resolved)
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Solved in \(elapsedLabel)")
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .loading:
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, minHeight: 120)
        case .loaded(let slice):
            leaderboardSection(slice)
            viewLeaderboardButton
        case .unauthenticated:
            unauthenticatedBlock
        case .noLeaderboard:
            noLeaderboardBlock
        case .failed:
            failedBlock
        }
    }

    private func leaderboardSection(_ slice: LeaderboardSlice) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Leaderboard")
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            VStack(spacing: 4) {
                ForEach(slice.entries, id: \.rank) { entry in
                    HStack {
                        Text("\(entry.rank).")
                            .monospacedDigit()
                            .foregroundStyle(theme.text.secondary.resolved)
                            .frame(width: 32, alignment: .trailing)
                        Text(entry.player.displayName)
                            .foregroundStyle(theme.text.primary.resolved)
                        Spacer()
                        Text(scoreLabel(entry.score))
                            .monospacedDigit()
                            .foregroundStyle(theme.text.primary.resolved)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                }
            }
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

    private var unauthenticatedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.system(size: 36))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Sign in to Game Center to compare with others.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.primary.resolved)
            Button("Sign in") {
                viewModel.viewLeaderboardTapped()
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, 16)
    }

    // Practice solves have no leaderboard (#383). Neutral, terminal copy — no
    // sign-in CTA (nothing to sign in for) and no dead button.
    private var noLeaderboardBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "dial.medium")
                .font(.system(size: 36))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Practice puzzles aren't ranked.")
                .multilineTextAlignment(.center)
                .foregroundStyle(theme.text.primary.resolved)
        }
        .padding(.top, 16)
    }

    private var failedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load leaderboard.")
                .foregroundStyle(theme.text.primary.resolved)
            Button {
                Task { await viewModel.retry() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(.top, 16)
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
