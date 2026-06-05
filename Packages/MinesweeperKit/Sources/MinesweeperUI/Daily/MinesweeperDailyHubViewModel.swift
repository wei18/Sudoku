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
public import MinesweeperEngine
public import Persistence
public import Telemetry

public struct MinesweeperDailyCard: Hashable, Sendable, Identifiable {
    public let entry: MinesweeperDailyEntry
    public let isCompleted: Bool

    public var id: String { entry.puzzleId }
    public var difficulty: Difficulty { entry.difficulty }
    public var seed: UInt64 { entry.seed }

    public init(entry: MinesweeperDailyEntry, isCompleted: Bool) {
        self.entry = entry
        self.isCompleted = isCompleted
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
    private let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// Idempotency latch for `.task` — once `bootstrap()` resolves we don't
    /// re-enter the fetch path on subsequent SwiftUI lifecycle ticks.
    private var hasBootstrapped = false

    public init(
        path: Binding<[AppRoute]>,
        provider: any MinesweeperDailyProviding = LiveMinesweeperDailyProvider(),
        persistence: (any PersistenceProtocol)? = nil,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.path = path
        self.provider = provider
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        state = .loading
        let today = dateProvider()
        let trio = provider.dailyTrio(date: today)

        // Completion-list failure must degrade gracefully to "no daily
        // completed yet" (every card un-completed) — the Daily hub must never
        // block (mirror Sudoku's M10 principle). MS persistence's
        // `fetchCompletedDailyIds` returns [] today (no MS daily save-flow yet),
        // so this is parity wiring against the real protocol method.
        var completed: Set<String> = []
        if let persistence {
            do {
                completed = try await persistence.fetchCompletedDailyIds(for: today)
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "MinesweeperDailyHubViewModel.fetchCompletedDailyIds"
                )
                completed = []
            }
        }

        state = .loaded(Self.mergeCards(trio: trio, completed: completed))
    }

    public func cardTapped(_ card: MinesweeperDailyCard) {
        path.wrappedValue.append(.board(difficulty: card.difficulty, seed: card.seed, mode: .daily))
    }

    /// Merge the daily trio with the set of completed daily ids into cards,
    /// marking a card completed iff its `puzzleId` is in `completed`. Pure +
    /// `nonisolated` so completion-marking is unit-testable without standing up
    /// a `PersistenceProtocol` conformer.
    nonisolated static func mergeCards(
        trio: [MinesweeperDailyEntry],
        completed: Set<String>
    ) -> [MinesweeperDailyCard] {
        trio.map { entry in
            MinesweeperDailyCard(entry: entry, isCompleted: completed.contains(entry.puzzleId))
        }
    }
}
