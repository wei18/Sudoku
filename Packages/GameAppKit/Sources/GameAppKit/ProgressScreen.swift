// ProgressScreen — the shared PROGRESS tab root (#1021 Phase D, design.md
// §3.3). Composed from Phase A's TabRoots scaffold: a "Personal bests"
// section (`PersonalBestRow` per difficulty, best time as the hero), a
// month-view streak calendar (`StreakCalendarView`, a record display — NOT a
// data-visualization dashboard), and the two native Game Center entry points
// (`GameCenterEntryRow.achievements` / `.leaderboards`).
//
// **Explicit non-goal (design.md §3.3):** no in-app achievement gallery / card
// list — that would be building a bespoke achievement system (metadata,
// progress, illustrations that don't exist yet). The correct move is a good
// entry point into Apple's own dashboard, which is exactly what the two
// `GameCenterEntryRow`s are.
//
// One screen, shared by both apps — replaces each app's now-retired
// per-app Statistics screen at the `.progress` tab root (#1021 Phase E2).
// Each app supplies its own `ProgressModel` (built from `PersonalRecord` +
// day-bucketed completion reads its own `ProgressViewModel` performs) and
// re-renders this screen whenever that model changes (the screen itself
// holds no state / does no I/O — same "dumb view over a value" shape as
// `PersonalBestRow`).

public import SwiftUI
// `public` — `ProgressModel` appears in this file's own public init.
public import GameShellUI

@MainActor
public struct ProgressScreen<Route: Hashable & Sendable>: View {
    private let model: ProgressModel
    private let rootViewModel: GameRootViewModel<Route>

    @Environment(\.theme) private var theme
    @ScaledSpacing(.large) private var sectionGap
    @ScaledSpacing(.small) private var headerGap
    @ScaledSpacing(.small) private var rowGap

    public init(model: ProgressModel, rootViewModel: GameRootViewModel<Route>) {
        self.model = model
        self.rootViewModel = rootViewModel
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                bestsSection
                calendarSection
                gameCenterSection
            }
            .padding(theme.spacing.medium)
            // Same 960pt clamp-and-center treatment as `BoardView.macLayout`'s
            // Mac detail column (the retired Statistics screen used it too).
            .frame(maxWidth: 960, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(theme.surface.background.resolved)
        .navigationTitle(Text("Progress", bundle: .main))
    }

    // MARK: - Personal bests

    private var bestsSection: some View {
        VStack(alignment: .leading, spacing: headerGap) {
            Text("Personal bests", bundle: .main)
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: rowGap) {
                ForEach(model.bests) { best in
                    // #1021 CR2 M2: `isLoading` swaps the row's WHOLE
                    // combined VoiceOver label to a non-fact "loading"
                    // announcement — `.redacted` below only hides the
                    // placeholder zeros visually, it does not change what
                    // VoiceOver reads.
                    PersonalBestRow(model: best, isLoading: model.isLoading)
                }
            }
        }
        .redacted(reason: model.isLoading ? .placeholder : [])
    }

    // MARK: - Streak calendar

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: headerGap) {
            HubCard {
                // #1021 CR2 M2: `model.history` is passed straight through
                // (no more `?? emptyHistory` substitution here) — the fake
                // all-zero fallback used to make the header read "Current 0
                // · Best 0" as if that were a real, fetched streak while
                // loading OR on a fetch failure. `StreakCalendarView` now
                // owns that layout-only fallback internally and keeps the
                // header/footnote TEXT honest via `isLoading`.
                StreakCalendarView(
                    history: model.history,
                    month: model.month,
                    monthTitle: model.monthTitle,
                    isLoading: model.isLoading
                )
            }
        }
        .redacted(reason: model.isLoading ? .placeholder : [])
    }

    // MARK: - Game Center entry points

    private var gameCenterSection: some View {
        VStack(spacing: rowGap) {
            GameCenterEntryRow.achievements(rootViewModel: rootViewModel)
            GameCenterEntryRow.leaderboards(rootViewModel: rootViewModel)
        }
    }
}
