// MinesweeperDailyHubViewModel — owns the daily trio fetch + completion overlay.
//
// Mirrors `SudokuUI.DailyHubViewModel`: bootstraps by fetching today's trio
// from a `MinesweeperDailyProviding` and the already-completed daily ids from
// Persistence, merging them into three `MinesweeperDailyCard` rows. The
// completion-fetch is graceful-degrade (a failure renders every card
// un-completed, never blocks the hub) — same principle as Sudoku's Daily.
//
// MS generation is synchronous + non-throwing (pure `MinesweeperDaily`), so
// there is no `.exhausted` / generator-failure path; the only async work is
// the optional completed-ids fetch.

public import Foundation
public import SwiftUI
import GameShellUI
public import MinesweeperEngine
public import MinesweeperPersistence
public import Persistence
public import Telemetry

public struct MinesweeperDailyCard: Hashable, Sendable, Identifiable {
    public let entry: MinesweeperDailyEntry
    public let isCompleted: Bool
    /// Epic 8 (SDD-003): `true` when the player hit a mine on this daily — a
    /// third state distinct from completed (won) and not-yet-played. A failed
    /// daily can be replayed freely but the replay is unscored and does not
    /// change this record.
    public let isFailed: Bool

    public var id: String { entry.puzzleId }
    public var difficulty: Difficulty { entry.difficulty }
    public var seed: UInt64 { entry.seed }

    public init(entry: MinesweeperDailyEntry, isCompleted: Bool, isFailed: Bool = false) {
        self.entry = entry
        self.isCompleted = isCompleted
        self.isFailed = isFailed
    }
}

public enum MinesweeperDailyHubState: Sendable, Equatable {
    case idle
    case loading
    case loaded([MinesweeperDailyCard])
}

@MainActor
@Observable
public final class MinesweeperDailyHubViewModel {
    public private(set) var state: MinesweeperDailyHubState = .idle

    private var path: Binding<[AppRoute]>

    private let provider: any MinesweeperDailyProviding
    private let persistence: (any PersistenceProtocol)?
    /// Epic 8 (SDD-003): MS-native store for failed-daily ids fetch. Optional
    /// so preview / test callsites that don't thread a store keep compiling —
    /// when nil, no cards are ever marked failed (graceful-degrade, same
    /// principle as the completed-ids path).
    private let savedGameStore: MinesweeperSavedGameStore?
    private let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// Idempotency latch for `.task` — once `bootstrap()` resolves we don't
    /// re-enter the fetch path on subsequent SwiftUI lifecycle ticks.
    private var hasBootstrapped = false

    public init(
        path: Binding<[AppRoute]>,
        provider: any MinesweeperDailyProviding = LiveMinesweeperDailyProvider(),
        persistence: (any PersistenceProtocol)? = nil,
        savedGameStore: MinesweeperSavedGameStore? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.path = path
        self.provider = provider
        self.persistence = persistence
        self.savedGameStore = savedGameStore
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
    }

    /// Seed state for previews / snapshot tests that bypass the async fetch.
    /// Latches `hasBootstrapped` so the view's `.task { bootstrap() }` becomes a
    /// no-op and the seeded state survives `NSHostingView` capture — mirrors
    /// `MinesweeperCompletionViewModel.setStateForTesting`. Production never
    /// calls this; the live `bootstrap()` path is untouched.
    public func setStateForTesting(_ state: MinesweeperDailyHubState) {
        self.state = state
        self.hasBootstrapped = true
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        let today = dateProvider()
        // Two-phase orchestration delegated to the shared skeleton (#558).
        // `dailyTrio` is synchronous and non-throwing — phase-1 wraps it in an
        // async closure that can never throw, so onPhase1Error is unreachable.
        // Phase-2 fills completion + failure overlays asynchronously — best-effort,
        // never blocks the initial render (M10 / §How.6.1 p1).
        await performDailyBootstrap(
            setLoading: { state = .loading },
            fetchPhase1: { self.provider.dailyTrio(date: today) },
            onPhase1: { trio in
                // Phase 1: render immediately with overlays unknown (#530).
                state = .loaded(Self.mergeCards(trio: trio, completed: [], failed: []))
            },
            onPhase1Error: { _ in /* unreachable: dailyTrio is non-throwing */ },
            fetchPhase2: { trio in
                // Phase 2: fill completion + failure overlays — non-blocking, best-effort.
                await self.fillCompletionAndFailureOverlay(trio: trio, date: today)
            }
        )
    }

    /// Phase-2 overlay fill: fetches completed and failed daily ids, then
    /// re-merges them with the already-rendered cards. Called after `state` is
    /// already `.loaded`, so a hang or failure here cannot block the initial
    /// render. Errors are funneled through `errorReporter` (OSLog-observable)
    /// and degrade silently to "no cards marked" — same M10 contract as #526.
    private func fillCompletionAndFailureOverlay(trio: [MinesweeperDailyEntry], date: Date) async {
        guard case .loaded = state else { return }

        var completed: Set<String> = []
        if let persistence {
            do {
                completed = try await persistence.fetchCompletedDailyIds(for: date)
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperDailyHubViewModel.fetchCompletedDailyIds"
                )
            }
        }

        var failed: Set<String> = []
        if let savedGameStore {
            do {
                failed = try await savedGameStore.fetchFailedDailyIds(for: date)
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperDailyHubViewModel.fetchFailedDailyIds"
                )
            }
        }

        guard case .loaded = state else { return }
        if !completed.isEmpty || !failed.isEmpty {
            state = .loaded(Self.mergeCards(trio: trio, completed: completed, failed: failed))
        }
    }

    /// Route for a tapped daily card:
    /// - Completed (won): re-surfaces the result via `.completion` (#386).
    /// - Failed (hit a mine): pushes the `.board` for a free replay —
    ///   the replay is unscored/unsubmitted and does NOT overwrite the
    ///   Failed record (Epic 8 / SDD-003; the board VM guards this via
    ///   `isReplay`). The `.board` route carries `isReplay: true` so the
    ///   board knows not to persist or submit GC on this attempt.
    /// - Not-yet-played: pushes the `.board` normally (daily-mode, scored).
    public func cardTapped(_ card: MinesweeperDailyCard) {
        if card.isCompleted {
            path.wrappedValue.append(.completion(difficulty: card.difficulty, mode: .daily))
        } else if card.isFailed {
            path.wrappedValue.append(
                .replayDailyBoard(difficulty: card.difficulty, seed: card.seed)
            )
        } else {
            path.wrappedValue.append(.board(difficulty: card.difficulty, seed: card.seed, mode: .daily))
        }
    }

    /// Merge the daily trio with the sets of completed and failed daily ids into
    /// cards. A card is completed iff its `puzzleId` is in `completed`; failed
    /// iff in `failed` (and not also completed — a completed win takes priority).
    /// Pure + `nonisolated` so state-marking is unit-testable without standing
    /// up a persistence conformer.
    nonisolated static func mergeCards(
        trio: [MinesweeperDailyEntry],
        completed: Set<String>,
        failed: Set<String> = []
    ) -> [MinesweeperDailyCard] {
        trio.map { entry in
            let isCompleted = completed.contains(entry.puzzleId)
            let isFailed = !isCompleted && failed.contains(entry.puzzleId)
            return MinesweeperDailyCard(
                entry: entry,
                isCompleted: isCompleted,
                isFailed: isFailed
            )
        }
    }
}
