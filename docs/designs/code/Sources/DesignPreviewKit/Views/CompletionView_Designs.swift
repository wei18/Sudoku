// DESIGN PREVIEW ONLY — docs/designs/code/Views/CompletionView_Designs.swift
//
// Extracted from docs/designs/06-completion.md §c. Refinements:
// - Leaderboard row rendering reuses Components/LeaderboardRow.swift.
// - Color literals replaced with DesignTokens.

import SwiftUI

public struct CompletionView_Designs: View {

    public enum State: Equatable {
        case authenticated(top: [LeaderboardEntry], around: [LeaderboardEntry])
        case unauthenticated
        case fetchFailed
        case loading
        case practiceMode
    }

    public static let demoTop: [LeaderboardEntry] = [
        .init(rank: 1, name: "alice", time: "3:48", isMe: false),
        .init(rank: 2, name: "bob", time: "3:55", isMe: false),
        .init(rank: 3, name: "carol", time: "4:02", isMe: false),
    ]
    public static let demoAround: [LeaderboardEntry] = [
        .init(rank: 16, name: "frank", time: "4:09", isMe: false),
        .init(rank: 17, name: "you", time: "4:11", isMe: true),
        .init(rank: 18, name: "dave", time: "4:18", isMe: false),
    ]

    public var state: State

    public init(state: State = .authenticated(top: CompletionView_Designs.demoTop, around: CompletionView_Designs.demoAround)) {
        self.state = state
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: DesignTokens.Spacing.xl) {
                hero
                content
                buttons
            }
            .padding(DesignTokens.Spacing.xl)
        }
        .background(DesignTokens.surfaceBackground)
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(DesignTokens.statusSuccess)
            Text("Solved!")
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Easy · 4:11")
                .font(.title3)
                .foregroundStyle(DesignTokens.textSecondary)
            Text("new best −0:23")
                .font(.callout.monospacedDigit())
                .foregroundStyle(DesignTokens.statusSuccess)
        }
        .frame(maxWidth: .infinity)
        .padding(DesignTokens.Spacing.xl)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .authenticated(let top, let around):
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                section("Top") { ForEach(top) { LeaderboardRow(entry: $0) } }
                section("Around you") { ForEach(around) { LeaderboardRow(entry: $0) } }
            }
        case .unauthenticated:
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "person.crop.circle.badge.questionmark")
                    .font(.system(size: 36))
                    .foregroundStyle(DesignTokens.textSecondary)
                Text("Sign in to Game Center to compare with others.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.textPrimary)
                Button("Sign in") { }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .tint(DesignTokens.accentPrimary)
                    .frame(minHeight: 48)
            }
        case .fetchFailed:
            VStack(spacing: DesignTokens.Spacing.md) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(DesignTokens.statusWarning)
                Text("Couldn't load leaderboard.")
                    .foregroundStyle(DesignTokens.textPrimary)
                Button { } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.accentPrimary)
            }
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 120)
        case .practiceMode:
            EmptyView()
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            Text(title)
                .font(.headline)
                .foregroundStyle(DesignTokens.textPrimary)
            VStack(spacing: DesignTokens.Spacing.xs) { rows() }
        }
    }

    @ViewBuilder private var buttons: some View {
        if case .practiceMode = state {
            Button("Play again") { }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.accentPrimary)
        } else {
            HStack(spacing: DesignTokens.Spacing.md) {
                Button("View full leaderboard") { }
                    .buttonStyle(.bordered)
                    .tint(DesignTokens.accentPrimary)
                Button("Play again") { }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.accentPrimary)
            }
        }
    }
}

#Preview("Completion — authenticated, light, en") {
    CompletionView_Designs()
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
