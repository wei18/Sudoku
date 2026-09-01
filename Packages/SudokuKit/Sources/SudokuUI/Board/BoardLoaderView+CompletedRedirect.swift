// BoardLoaderView+CompletedRedirect — the `.review`-variant surface for
// `BoardLoaderView`'s `.completedRedirect` state (#842 / #1023).
//
// Extracted to a sibling file (repo convention: `+Feature.swift` rather than
// growing the host file past SwiftLint's 400-line `file_length` ceiling —
// `BoardLoaderView.swift` was already at that ceiling before #1023).
//
// #1023: resolves the SAME Daily "more today?" CTA row the live overlay uses
// (`BoardView+Completion.completionContext`), via the SAME injected
// `fetchDailyProgress` closure — this is a re-view of an ALREADY-completed
// daily, so it's `.review` (no ritual, no haptic), but the CTA hierarchy
// (§3.5) is identical to the live path's Daily rows.

public import SwiftUI
public import GameShellUI
public import SettingsUI

/// `public` — also constructed by `SudokuAppComposition.LiveRouteFactory`'s
/// pushed `.completion` review route (path 2), the SAME shape this file's
/// namesake `.completedRedirect` state (path 3) needs.
public struct CompletedRedirectSurface: View {
    let completionViewModel: CompletionViewModel
    let reminderPrimer: ReminderPrimerCoordinator?
    let fetchDailyProgress: (@MainActor () async -> DailyCompletionProgress)?
    let onDailyNext: ((String) -> Void)?
    let onClose: () -> Void

    /// `.allDone` default — never claims a "Next" that doesn't exist while
    /// `fetchDailyProgress` is still resolving.
    @State private var progress: DailyCompletionProgress = .allDone

    public init(
        completionViewModel: CompletionViewModel,
        reminderPrimer: ReminderPrimerCoordinator?,
        fetchDailyProgress: (@MainActor () async -> DailyCompletionProgress)?,
        onDailyNext: ((String) -> Void)?,
        onClose: @escaping () -> Void
    ) {
        self.completionViewModel = completionViewModel
        self.reminderPrimer = reminderPrimer
        self.fetchDailyProgress = fetchDailyProgress
        self.onDailyNext = onDailyNext
        self.onClose = onClose
    }

    public var body: some View {
        CompletionOverlayScaffold(
            variant: .review,
            // A confirmed-`.completed` record is, by definition, a solve —
            // Sudoku is solve-only, so this is always `.success`.
            outcomeKind: .success,
            context: context,
            onClose: onClose,
            card: {
                CompletionView(
                    viewModel: completionViewModel,
                    reminderPrimer: reminderPrimer,
                    onClose: nil
                )
            }
        )
        .task {
            guard let fetchDailyProgress else { return }
            progress = await fetchDailyProgress()
        }
    }

    private var context: CompletionContext {
        switch progress {
        case .moreToday(let difficulty, let puzzleId):
            guard let onDailyNext else { return .dailyAllDone }
            return .dailyMoreToday(
                nextDifficultyLabel: LocalizedStringKey(difficulty.rawValue.capitalized),
                onNext: {
                    onClose()
                    onDailyNext(puzzleId)
                }
            )
        case .allDone:
            return .dailyAllDone
        }
    }
}
