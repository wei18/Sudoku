// MinesweeperCompletedRedirectSurface — the `.review`-variant surface for an
// already-completed daily (#1023). Mirrors Sudoku's
// `BoardLoaderView+CompletedRedirect.CompletedRedirectSurface` exactly: used
// by BOTH `MinesweeperDailyOpenGuardView`'s `.resolved(.completed)` state
// (path 4) and `MinesweeperAppComposition.LiveRouteFactory`'s pushed
// `.completion` review route (path 2), the SAME shape.
//
// A confirmed-`.completed` daily record is, by definition, a WIN — MS has no
// "completed but lost" daily state — so `outcomeKind` is always `.success`.

public import SwiftUI
import GameShellUI
public import SettingsUI

public struct MinesweeperCompletedRedirectSurface: View {
    let completionViewModel: MinesweeperCompletionViewModel
    let reminderPrimer: ReminderPrimerCoordinator?
    let fetchDailyProgress: (@MainActor () async -> MinesweeperDailyCompletionProgress)?
    let onDailyNext: ((MinesweeperDailyEntry) -> Void)?
    let onClose: () -> Void
    /// MS re-view has no stored elapsed (#284/#386) — the hero omits the time
    /// row entirely when `false`. Defaults `true` (has-time callers unchanged).
    let showsElapsedTime: Bool

    /// `.allDone` default — never claims a "Next" that doesn't exist while
    /// `fetchDailyProgress` is still resolving.
    @State private var progress: MinesweeperDailyCompletionProgress = .allDone

    public init(
        completionViewModel: MinesweeperCompletionViewModel,
        reminderPrimer: ReminderPrimerCoordinator?,
        fetchDailyProgress: (@MainActor () async -> MinesweeperDailyCompletionProgress)?,
        onDailyNext: ((MinesweeperDailyEntry) -> Void)?,
        onClose: @escaping () -> Void,
        showsElapsedTime: Bool = true
    ) {
        self.completionViewModel = completionViewModel
        self.reminderPrimer = reminderPrimer
        self.fetchDailyProgress = fetchDailyProgress
        self.onDailyNext = onDailyNext
        self.onClose = onClose
        self.showsElapsedTime = showsElapsedTime
    }

    public var body: some View {
        CompletionOverlayScaffold(
            variant: .review,
            outcomeKind: .success,
            context: context,
            onClose: onClose,
            card: {
                MinesweeperCompletionView(
                    viewModel: completionViewModel,
                    reminderPrimer: reminderPrimer,
                    onClose: nil,
                    showsElapsedTime: showsElapsedTime
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
        case .moreToday(let entry):
            guard let onDailyNext else { return .dailyAllDone }
            return .dailyMoreToday(
                nextDifficultyLabel: LocalizedStringKey(entry.difficulty.rawValue.capitalized),
                onNext: {
                    onClose()
                    onDailyNext(entry)
                }
            )
        case .allDone:
            return .dailyAllDone
        }
    }
}
