// DESIGN PREVIEW ONLY — docs/designs/code/Views/RootView_Designs.swift
//
// Extracted from docs/designs/01-root.md §c. Refinements:
// - ResumePill extracted to Components/ResumePill.swift
// - Tokens via DesignTokens
// - Original `@Observable` stub VM simplified to a plain @State binding
//   (preview snapshot only — no observation needed).

import SwiftUI

public struct RootView_Designs: View {
    public struct ResumeCandidate: Equatable {
        public let difficultyLabel: String
        public let elapsed: String
        public init(difficultyLabel: String, elapsed: String) {
            self.difficultyLabel = difficultyLabel
            self.elapsed = elapsed
        }
    }

    public enum SidebarMode: String, Hashable, CaseIterable, Identifiable {
        case daily, practice, leaderboard, settings
        public var id: String { rawValue }
        public var titleKey: LocalizedStringKey {
            switch self {
            case .daily: "Daily"
            case .practice: "Practice"
            case .leaderboard: "Leaderboard"
            case .settings: "Settings"
            }
        }
        public var symbol: String {
            switch self {
            case .daily: "calendar"
            case .practice: "dice"
            case .leaderboard: "trophy.fill"
            case .settings: "gear"
            }
        }
    }

    public var resume: ResumeCandidate?
    @State private var selected: SidebarMode? = .daily
    @Environment(\.horizontalSizeClass) private var hSize

    public init(resume: ResumeCandidate? = .init(difficultyLabel: "Easy", elapsed: "3:21")) {
        self.resume = resume
    }

    public var body: some View {
        if hSize == .regular {
            NavigationSplitView {
                List(SidebarMode.allCases, selection: $selected) { mode in
                    Label(mode.titleKey, systemImage: mode.symbol).tag(mode)
                }
                .navigationTitle("Sudoku")
            } detail: {
                VStack {
                    pill
                    DetailStub(mode: selected)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .background(DesignTokens.surfaceBackground)
            }
        } else {
            NavigationStack {
                VStack {
                    pill
                    DetailStub(mode: .none)
                }
                .padding(.horizontal, DesignTokens.Spacing.lg)
                .background(DesignTokens.surfaceBackground)
            }
        }
    }

    @ViewBuilder private var pill: some View {
        if let r = resume {
            ResumePill(difficultyLabel: r.difficultyLabel, elapsed: r.elapsed)
                .padding(.top, DesignTokens.Spacing.sm)
        }
    }

    private struct DetailStub: View {
        let mode: SidebarMode?
        var body: some View {
            Text(label)
                .foregroundStyle(DesignTokens.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        var label: LocalizedStringKey {
            switch mode {
            case .daily: "DailyHubView →"
            case .practice: "PracticeHubView →"
            case .leaderboard: "LeaderboardView →"
            case .settings: "SettingsView →"
            case .none: "HomeView →"
            }
        }
    }
}

#Preview("Root — iPhone, light, en") {
    RootView_Designs()
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
