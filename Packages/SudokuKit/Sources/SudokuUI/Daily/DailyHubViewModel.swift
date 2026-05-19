// DailyHubViewModel — owns trio fetch + completion overlay.
//
// Per docs/designs/03-daily-hub.md + design.md §How.5.4. Bootstraps by
// fetching today's trio from PuzzleProvider and the already-completed
// daily puzzleIds from Persistence; merges them into 3 `DailyCard` rows.

public import Foundation
public import PuzzleStore
public import Persistence

public struct DailyCard: Sendable, Equatable, Hashable, Identifiable {
    public let envelope: PuzzleEnvelope
    public let isCompleted: Bool

    public var id: String { envelope.identity.puzzleId }
    public var difficulty: String { envelope.identity.difficulty }
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
    public var path: [AppRoute] = []

    private let provider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let dateProvider: @Sendable () -> Date

    public init(
        provider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        dateProvider: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.persistence = persistence
        self.dateProvider = dateProvider
    }

    public func bootstrap() async {
        state = .loading
        let today = dateProvider()
        do {
            async let trioCall = provider.fetchDailyTrio(date: today)
            async let completedCall = persistence.fetchCompletedDailyIds(for: today)
            let trio = try await trioCall
            let completed = (try? await completedCall) ?? []
            let cards = trio.map { envelope in
                DailyCard(envelope: envelope, isCompleted: completed.contains(envelope.identity.puzzleId))
            }
            state = .loaded(cards)
        } catch let error as PuzzleStoreError {
            switch error {
            case .generatorFailed:
                state = .exhausted
            default:
                state = .failed(String(describing: error))
            }
        } catch {
            state = .failed(String(describing: error))
        }
    }

    public func cardTapped(_ card: DailyCard) {
        path.append(.board(puzzleId: card.envelope.identity.puzzleId))
    }
}
