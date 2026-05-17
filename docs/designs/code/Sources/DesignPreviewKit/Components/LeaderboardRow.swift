// DESIGN PREVIEW ONLY — docs/designs/code/Components/LeaderboardRow.swift
//
// One row of the Leaderboard list (also reused inside CompletionView).
// Source: docs/designs/07-leaderboard.md §c row(_:) + §e (AX3 vertical-stack).

import SwiftUI

public struct LeaderboardEntry: Identifiable, Equatable, Hashable {
    public let rank: Int
    public let name: String
    public let time: String
    public let isMe: Bool
    public var id: Int { rank }
    public init(rank: Int, name: String, time: String, isMe: Bool) {
        self.rank = rank; self.name = name; self.time = time; self.isMe = isMe
    }
}

public struct LeaderboardRow: View {
    public let entry: LeaderboardEntry
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    public init(entry: LeaderboardEntry) {
        self.entry = entry
    }

    public var body: some View {
        Group {
            if dynamicTypeSize >= .accessibility3 {
                verticalLayout
            } else {
                horizontalLayout
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .background(
            entry.isMe ? DesignTokens.accentMuted.opacity(0.5) : Color.clear,
            in: .rect(cornerRadius: DesignTokens.Radius.row)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(entry.isMe
            ? "Rank \(entry.rank), you, \(entry.name), \(entry.time)"
            : "Rank \(entry.rank), \(entry.name), \(entry.time)")
    }

    private var horizontalLayout: some View {
        HStack {
            Text("\(entry.rank).")
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(width: 40, alignment: .trailing)
            Text(entry.name)
                .fontWeight(entry.isMe ? .semibold : .regular)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(entry.name)
            Spacer()
            Text(entry.time)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textPrimary)
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(entry.rank).")
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textSecondary)
            Text(entry.name)
                .fontWeight(entry.isMe ? .semibold : .regular)
                .foregroundStyle(DesignTokens.textPrimary)
                .lineLimit(2)
            Text(entry.time)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("LeaderboardRow — default + me") {
    VStack {
        LeaderboardRow(entry: .init(rank: 1, name: "alice", time: "3:48", isMe: false))
        LeaderboardRow(entry: .init(rank: 17, name: "you", time: "4:11", isMe: true))
    }
    .padding()
    .background(DesignTokens.surfacePrimary)
}
