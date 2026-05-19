// CompletionView — hero stat + (optional) leaderboard slice.
//
// Per docs/designs/06-completion.md. State variants:
//   .loading              → ProgressView
//   .loaded(slice)        → hero + leaderboard rows + "View full" CTA
//   .unauthenticated      → hero + sign-in CTA
//   .failed               → hero + retry CTA

public import SwiftUI
import GameCenterClient

public struct CompletionView: View {
    @Bindable private var viewModel: CompletionViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: CompletionViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                content
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        .task { await viewModel.bootstrap() }
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

    private var failedBlock: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load leaderboard.")
                .foregroundStyle(theme.text.primary.resolved)
            Button {
                Task { await viewModel.bootstrap() }
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
