// DESIGN PREVIEW ONLY — docs/designs/code/Views/LeaderboardView_Designs.swift
//
// Extracted from docs/designs/07-leaderboard.md §c. Refinements:
// - Row rendering extracted to Components/LeaderboardRow.swift (handles AX3 vertical-stack).
// - Tokens via DesignTokens.

import SwiftUI

public struct LeaderboardView_Designs: View {

    public enum Scope: String, CaseIterable, Identifiable {
        case global = "Global", around = "Around me", friends = "Friends"
        public var id: String { rawValue }
        public var key: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }
    public enum Difficulty: String, CaseIterable, Identifiable {
        case easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert"
        public var id: String { rawValue }
        public var key: LocalizedStringKey { LocalizedStringKey(rawValue) }
    }

    public enum State: Equatable {
        case loaded([LeaderboardEntry])
        case unauthenticated
        case error
        case loading
    }

    public static let demoEntries: [LeaderboardEntry] = [
        .init(rank: 1, name: "alice", time: "3:48", isMe: false),
        .init(rank: 2, name: "bob", time: "3:55", isMe: false),
        .init(rank: 3, name: "carol", time: "4:02", isMe: false),
        .init(rank: 4, name: "dave", time: "4:18", isMe: false),
        .init(rank: 5, name: "eve", time: "4:24", isMe: false),
        .init(rank: 17, name: "you", time: "4:11", isMe: true),
    ]

    public var state: State
    @SwiftUI.State private var scope: Scope = .global
    @SwiftUI.State private var difficulty: Difficulty = .easy

    public init(state: State = .loaded(LeaderboardView_Designs.demoEntries)) {
        self.state = state
    }

    public var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases) { Text($0.key).tag($0) }
            }
            .pickerStyle(.segmented)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))
            .tint(DesignTokens.accentPrimary)

            Picker("Difficulty", selection: $difficulty) {
                ForEach(Difficulty.allCases) { Text($0.key).tag($0) }
            }
            .pickerStyle(.segmented)
            .tint(DesignTokens.accentPrimary)

            content
        }
        .padding(DesignTokens.Spacing.lg)
        .navigationTitle("Leaderboard")
        .background(DesignTokens.surfaceBackground)
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loaded(let entries):
            List(entries) { LeaderboardRow(entry: $0) }
                .listStyle(.plain)
        case .unauthenticated:
            unauthState
        case .error:
            errorState
        case .loading:
            ProgressView().controlSize(.large).frame(maxHeight: .infinity)
        }
    }

    private var unauthState: some View {
        VStack(spacing: DesignTokens.Spacing.lg) {
            Image(systemName: "lock")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.textSecondary)
            Text("Sign in to Game Center")
                .font(.title3.weight(.medium))
                .foregroundStyle(DesignTokens.textPrimary)
            Text("Rankings sync once you sign in.")
                .font(.callout)
                .foregroundStyle(DesignTokens.textSecondary)
            Button("Sign in") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(DesignTokens.accentPrimary)
                .frame(minHeight: 48)
        }
        .frame(maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(DesignTokens.statusWarning)
            Text("Couldn't load leaderboard.")
                .foregroundStyle(DesignTokens.textPrimary)
            Button { } label: { Label("Retry", systemImage: "arrow.clockwise") }
                .buttonStyle(.bordered)
                .tint(DesignTokens.accentPrimary)
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview("Leaderboard — loaded, light, en") {
    NavigationStack { LeaderboardView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
