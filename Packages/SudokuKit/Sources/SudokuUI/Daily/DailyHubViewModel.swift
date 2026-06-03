// DailyHubViewModel — owns trio fetch + completion overlay.
//
// Per docs/designs/03-daily-hub.md + docs/v1/design.md §How.5.4. Bootstraps by
// fetching today's trio from PuzzleProvider and the already-completed
// daily puzzleIds from Persistence; merges them into 3 `DailyCard` rows.

public import Foundation
public import SwiftUI
import GameShellUI
public import PuzzleStore
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
            async let trioCall = provider.fetchDailyTrio(date: today)
            async let completedCall = persistence.fetchCompletedDailyIds(for: today)
            let trio = try await trioCall
            // M10 (issue #67): completion-list failure must still degrade
            // gracefully to "no daily completed yet" (every card shows as
            // un-completed) — design.md §How.6.1 principle 1, Daily hub
            // must never block. Funnel reports the underlying error so a
            // CloudKit fetch failure is observable in OSLog instead of
            // silently rendering an inaccurate hub state.
            let completed: Set<String>
            do {
                completed = try await completedCall
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "DailyHubViewModel.fetchCompletedDailyIds"
                )
                completed = []
            }
            let cards = trio.map { envelope in
                DailyCard(envelope: envelope, isCompleted: completed.contains(envelope.identity.puzzleId))
            }
            state = .loaded(cards)
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

    public func cardTapped(_ card: DailyCard) {
        path.append(.board(puzzleId: card.envelope.identity.puzzleId))
    }
}
