// DailyHubViewModel — owns trio fetch + completion overlay.
//
// Per docs/designs/03-daily-hub.md + docs/v1/design.md §How.5.4. Bootstraps by
// fetching today's trio from PuzzleProvider and the already-completed
// daily puzzleIds from Persistence; merges them into 3 `DailyCard` rows.

public import Foundation
public import SwiftUI
import GameShellUI
public import SudokuPersistence
public import Persistence
public import SudokuEngine
public import Telemetry

public struct DailyCard: Sendable, Equatable, Hashable, Identifiable {
    public let envelope: PuzzleEnvelope
    public let isCompleted: Bool

    public var id: String { envelope.identity.puzzleId }
    public var difficulty: Difficulty { envelope.identity.difficulty }
}

public enum DailyHubState: Sendable, Equatable {
    case idle
    case loading
    case loaded([DailyCard])
    case exhausted
    case failed(String)
}

@MainActor
@Observable
public final class DailyHubViewModel {
    public private(set) var state: DailyHubState = .idle

    /// Navigation path store (issue #240): routes through an injected
    /// `Binding<[AppRoute]>` when `RouteFactory` hoists `RootViewModel.path`
    /// via `init(path:)`, otherwise a local stub (previews / unit tests).
    /// Mirrors `HomeViewModel`'s pattern (issue #197).
    private var routePath: RoutePath<AppRoute>

    /// Single public view of the navigation path. Callers do not need to know
    /// which mode (injected binding / local stub) is active.
    public var path: [AppRoute] {
        get { routePath.effectivePath }
        set { routePath.effectivePath = newValue }
    }

    private let provider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    private let dateProvider: @Sendable () -> Date
    /// Idempotency latch for `.task` — once `bootstrap()` has resolved we
    /// don't re-enter the fetch path on subsequent SwiftUI lifecycle ticks.
    private var hasBootstrapped = false

    /// Transient in-flight latch for the completed-card → Completion fan-out
    /// (#385). `cardTapped` is a synchronous `@MainActor` closure, so a
    /// double-tap (or a tap landing during the in-flight `loadOrCreate`) can
    /// otherwise push `.completion` twice. Set synchronously before spawning
    /// the open Task and cleared in `openCompleted`'s `defer` — both run on
    /// the MainActor, so no second tap can slip a route in during the load.
    /// Unlike P0-1's one-shot `hasNavigatedToCompletion`, this RESETS so a
    /// re-tap after returning to the hub works again.
    private var isOpeningCompleted = false

    public init(
        provider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        path: Binding<[AppRoute]>? = nil
    ) {
        self.provider = provider
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.dateProvider = dateProvider
        self.routePath = RoutePath(path)
    }

    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true
        state = .loading
        let today = dateProvider()
        do {
            let trio = try await provider.fetchDailyTrio(date: today)
            // Phase 1: render immediately with completion unknown (#526).
            // M10 (issue #67): the hub must never block on a CloudKit call —
            // when iCloud is signed out, `database.records(matching:inZoneWith:)`
            // hangs indefinitely rather than throwing, so the previous
            // `async let completedCall` pattern blocked here forever.
            // Fix: render the three cards right after the trio arrives (no
            // CK dependency), then fill completion overlay asynchronously.
            // If the fill hangs or errors, the hub stays loaded with every
            // card showing as un-completed (graceful-degrade, §How.6.1 p1).
            let cards = trio.map { DailyCard(envelope: $0, isCompleted: false) }
            state = .loaded(cards)
            // Phase 2: completion overlay — non-blocking, best-effort.
            await fillCompletionOverlay(trio: trio, date: today)
        } catch let error as PuzzleStoreError {
            switch error {
            case .generatorFailed:
                state = .exhausted
            default:
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "DailyHubViewModel.bootstrap"
                )
                state = .failed(String(describing: error))
            }
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.bootstrap"
            )
            state = .failed(String(describing: error))
        }
    }

    /// Phase-2 completion overlay: fetches completed daily ids and re-merges
    /// them with the already-rendered cards. Called after `state` is already
    /// `.loaded` so a hang or failure here cannot block the initial render.
    /// Errors are funneled through `errorReporter` (OSLog-observable) and
    /// degrade silently to "no cards completed" — same M10 contract as before.
    private func fillCompletionOverlay(trio: [PuzzleEnvelope], date: Date) async {
        let completed: Set<String>
        do {
            completed = try await persistence.fetchCompletedDailyIds(for: date)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.fetchCompletedDailyIds"
            )
            return // degrade: cards remain un-completed
        }
        guard !completed.isEmpty else { return }
        let cards = trio.map { envelope in
            DailyCard(envelope: envelope, isCompleted: completed.contains(envelope.identity.puzzleId))
        }
        state = .loaded(cards)
    }

    /// Synchronous tap entry point (the DailyHubView shell closure is sync).
    /// An un-completed card pushes straight to the board. A completed card
    /// (#379) must re-surface the player's result, so it fans out to the
    /// async `openCompleted(_:)` helper which fetches the frozen solve time
    /// and routes to `.completion`. The helper is `await`-able directly so
    /// tests don't depend on fire-and-forget `Task` timing.
    public func cardTapped(_ card: DailyCard) {
        guard card.isCompleted else {
            path.append(.board(puzzleId: card.envelope.identity.puzzleId))
            return
        }
        // #385: drop re-taps while a previous open is still in flight so the
        // async fan-out can't push `.completion` twice. The `.board` branch
        // above is synchronous and not latched (unchanged prior behavior).
        guard !isOpeningCompleted else { return }
        isOpeningCompleted = true
        Task { await openCompleted(card) }
    }

    /// Loads the completed daily's saved snapshot to recover its frozen
    /// `elapsedSeconds`, then routes to the Completion screen. On a load
    /// failure we report through the funnel and fall back to `.board` — never
    /// worse than the pre-#379 behavior, and never silently stuck.
    func openCompleted(_ card: DailyCard) async {
        // Reset on both success and the error/fallback path so a later tap
        // (#385) re-enters cleanly. `@MainActor` guarantees this runs without
        // an interleaved `cardTapped` between the route append and the clear.
        defer { isOpeningCompleted = false }
        let puzzleId = card.envelope.identity.puzzleId
        do {
            let snapshot = try await persistence.loadOrCreate(
                puzzleId: puzzleId,
                mode: .daily,
                difficulty: card.difficulty
            )
            path.append(.completion(
                puzzleId: puzzleId,
                elapsedSeconds: snapshot.elapsedSeconds,
                mistakeCount: snapshot.mistakeCount
            ))
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "DailyHubViewModel.openCompleted"
            )
            path.append(.board(puzzleId: puzzleId))
        }
    }
}
