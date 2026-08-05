// DailyRankStateViews — the non-populated Daily Rank states (#983): sign-in /
// friends-grant / error explainer, and the populated-but-empty state. Split
// out of DailyRankView.swift to keep it under the 400-line file_length gate.

internal import SwiftUI
internal import GameCenterClient

// MARK: - Explainer (states 1/2 + error funnel)

/// Icon + title + message + single CTA — used for "not signed in", "friends
/// access not granted", and the network-error funnel. Never a blank screen.
struct DailyRankExplainerView: View {
    let systemImage: String
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let actionTitleKey: LocalizedStringKey
    let accessibilityId: String
    let action: () async -> Void

    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Spacer()
            Image(systemName: systemImage)
                .font(.system(size: 40))
                .foregroundStyle(theme.text.tertiary.resolved)
            Text(titleKey)
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
                .multilineTextAlignment(.center)
            Text(messageKey)
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
                .multilineTextAlignment(.center)
            Button {
                Task { await action() }
            } label: {
                // #797: ink lives on the label content, not chained after
                // `.buttonStyle` — `.borderedProminent` ignores an ambient
                // `.foregroundStyle` set on the Button itself.
                Text(actionTitleKey)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(theme.surface.primary.resolved)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent.primary.resolved)
            .accessibilityIdentifier(accessibilityId)
            Spacer()
        }
        .padding(theme.spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

// MARK: - Populated-but-empty (state 3)

/// Zero-friends / zero-scores-yet. The persistent "Open Game Center" button
/// on `DailyRankView` already covers §How's "keep the full dashboard
/// reachable" CTA, so this block is copy-only.
struct DailyRankEmptyView: View {
    let scope: DailyRankScope
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(spacing: theme.spacing.medium) {
            Spacer()
            Image(systemName: "trophy")
                .font(.system(size: 40))
                .foregroundStyle(theme.text.tertiary.resolved)
            Text("No Rankings Yet")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
                .multilineTextAlignment(.center)
            Text(scope == .friends
                 ? "None of your friends have set a time today. Add friends in Game Center to compare."
                 : "Be the first to set a time today.")
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(theme.spacing.large)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("dailyRank.empty")
    }
}

// MARK: - Populated (state 4)

/// Top slice + (when the local player fell outside it) a separate "Your
/// Rank" section, local player row highlighted in both.
struct DailyRankResultView: View {
    let result: DailyRankResult
    let scope: DailyRankScope

    var body: some View {
        if result.topEntries.isEmpty {
            DailyRankEmptyView(scope: scope)
        } else {
            List {
                Section("Top Ranked") {
                    ForEach(result.topEntries, id: \.rank) { entry in
                        DailyRankRow(
                            entry: entry,
                            isLocalPlayer: entry.player.teamPlayerId == result.localPlayerId
                        )
                    }
                }
                if !result.localPlayerInTop, let own = result.localPlayerEntry {
                    Section("Your Rank") {
                        DailyRankRow(entry: own, isLocalPlayer: true)
                    }
                }
            }
            .listStyle(.plain)
            .accessibilityIdentifier("dailyRank.list")
        }
    }
}

private struct DailyRankRow: View {
    let entry: LeaderboardEntry
    let isLocalPlayer: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: 12) {
            Text("\(entry.rank)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(theme.text.secondary.resolved)
                .frame(width: 28, alignment: .trailing)
            Text(entry.player.displayName)
                .font(.body)
                .foregroundStyle(theme.text.primary.resolved)
                .lineLimit(1)
            if isLocalPlayer {
                Text("You")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(theme.accent.primary.resolved)
            }
            Spacer()
            Text(ResumeTitle.elapsed(entry.score))
                .font(.body.monospacedDigit())
                .foregroundStyle(theme.text.secondary.resolved)
        }
        .padding(.vertical, 4)
        .listRowBackground(isLocalPlayer ? theme.accent.muted.resolved.opacity(0.25) : Color.clear)
        .accessibilityIdentifier(isLocalPlayer ? "dailyRank.row.localPlayer" : "dailyRank.row")
    }
}
