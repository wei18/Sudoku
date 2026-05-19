// LeaderboardView — scope picker + entries list + AX3+ vertical row.
//
// Per docs/designs/07-leaderboard.md. At `@Environment(\.dynamicTypeSize)
// >= .accessibility3`, each row switches from a horizontal layout (rank ·
// name · time) to a vertically-stacked layout to avoid horizontal
// truncation. Pure SwiftUI — no custom layout helper needed.

public import SwiftUI
import GameCenterClient

public struct LeaderboardView: View {
    @Bindable private var viewModel: LeaderboardViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: LeaderboardViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 12) {
            scopePicker
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.background.resolved)
        .navigationTitle("Leaderboard")
        .task { await viewModel.bootstrap() }
    }

    private var scopePicker: some View {
        Picker("Scope", selection: scopeBinding) {
            Text("Global").tag(LeaderboardScope.globalAllTime)
            Text("Today").tag(LeaderboardScope.globalToday)
            Text("Friends").tag(LeaderboardScope.friendsAllTime)
        }
        .pickerStyle(.segmented)
    }

    private var scopeBinding: Binding<LeaderboardScope> {
        Binding(
            get: { viewModel.scope },
            set: { next in Task { await viewModel.setScope(next) } }
        )
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView().controlSize(.large).frame(maxHeight: .infinity)
        case .loaded(let slice):
            entriesList(slice)
        case .friendsDenied:
            friendsCTA
        case .unauthenticated:
            unauthenticatedCTA
        case .failed:
            failedBlock
        }
    }

    private func entriesList(_ slice: LeaderboardSlice) -> some View {
        ScrollView {
            VStack(spacing: 4) {
                ForEach(slice.entries, id: \.rank) { entry in
                    LeaderboardRow(entry: entry)
                }
            }
            .padding(.top, 8)
        }
    }

    private var friendsCTA: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.2.slash")
                .font(.system(size: 36))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Enable Friends to see this list.")
                .foregroundStyle(theme.text.primary.resolved)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
    }

    private var unauthenticatedCTA: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock")
                .font(.system(size: 48))
                .foregroundStyle(theme.text.secondary.resolved)
            Text("Sign in to Game Center")
                .font(.title3.weight(.medium))
                .foregroundStyle(theme.text.primary.resolved)
        }
        .frame(maxHeight: .infinity)
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
        .frame(maxHeight: .infinity)
    }
}

struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    @Environment(\.theme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize >= .accessibility3 {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Rank \(entry.rank), \(entry.player.displayName), \(scoreLabel)"
        )
    }

    private var horizontalLayout: some View {
        HStack {
            Text("\(entry.rank).")
                .monospacedDigit()
                .foregroundStyle(theme.text.secondary.resolved)
                .frame(width: 40, alignment: .trailing)
            Text(entry.player.displayName)
                .foregroundStyle(theme.text.primary.resolved)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(scoreLabel)
                .monospacedDigit()
                .foregroundStyle(theme.text.primary.resolved)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.rank).")
                .monospacedDigit()
                .foregroundStyle(theme.text.secondary.resolved)
            Text(entry.player.displayName)
                .foregroundStyle(theme.text.primary.resolved)
                .lineLimit(2)
            Text(scoreLabel)
                .monospacedDigit()
                .foregroundStyle(theme.text.primary.resolved)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var scoreLabel: String {
        let minutes = entry.score / 60
        let seconds = entry.score % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
