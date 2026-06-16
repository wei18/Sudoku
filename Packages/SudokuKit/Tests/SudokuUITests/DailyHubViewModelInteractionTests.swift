// DailyHubViewModelInteractionTests — bootstrap fetch + card-tap navigation,
// asserting service call shape and navigation through an injected binding
// (issue #171).
//
// `DailyHubViewTests.cardTapAppendsBoardRoute` covers the local-stub branch.
// This suite adds (1) the external-`Binding` navigation branch and (2)
// behavioral service-call assertions via the fakes' recorded `operations`, so a
// regression that stopped calling the provider/persistence on bootstrap — or
// stopped pushing through the injected path on tap — would fail here.

import Foundation
import Testing
@testable import SudokuUI

import GameState
import Persistence
import PuzzleStore
import SudokuEngine
import SudokuKitTesting
import Telemetry

@MainActor
@Suite("DailyHubViewModel — interaction (services + injected path)")
struct DailyHubViewModelInteractionTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    private func makeViewModel(
        provider: FakePuzzleProvider,
        persistence: FakePersistence,
        box: RoutePathBox
    ) -> DailyHubViewModel {
        DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
    }

    @Test func bootstrapCallsProviderAndPersistenceExactlyOnce() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: RoutePathBox())

        await viewModel.bootstrap()

        let providerOps = await provider.operations
        let persistenceOps = await persistence.operations
        #expect(providerOps == [.fetchDailyTrio(date: Self.fixedDate)])
        #expect(persistenceOps == [.fetchCompletedDailyIds(date: Self.fixedDate)])
    }

    @Test func bootstrapIsIdempotent() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: RoutePathBox())

        await viewModel.bootstrap()
        await viewModel.bootstrap()

        let providerOps = await provider.operations
        // The `hasBootstrapped` latch must keep the second call from re-fetching.
        #expect(providerOps.count == 1)
    }

    @Test func cardTapPushesBoardRouteThroughInjectedBinding() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let tapped = cards[1]

        viewModel.cardTapped(tapped)

        #expect(box.routes == [.board(puzzleId: tapped.envelope.identity.puzzleId)])
    }

    // MARK: - #379: completed card routes to Completion

    /// Builds a completed-status snapshot whose `elapsedSeconds` is the
    /// frozen solve time we expect to surface on the Completion route.
    private func completedSnapshot(elapsedSeconds: Int) -> GameSessionSnapshot {
        let puzzle = FakePuzzleProvider.defaultPuzzle(difficulty: .easy, seed: 1)
        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: puzzle.solution,
            status: .completed,
            elapsedSeconds: elapsedSeconds,
            undoMoves: [],
            redoMoves: [],
            notes: NotesGrid()
        )
    }

    @Test func tappingCompletedCardRoutesToCompletionWithSavedTime() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        // Mark the tapped card completed (bootstrap fixture leaves all un-completed).
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        await viewModel.openCompleted(completedCard)

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    // MARK: - #385: cardTapped (sync entry) routes + double-tap latch

    /// Drains the MainActor queue until `box.routes` reaches `count` or the
    /// bounded yield budget is exhausted. `cardTapped`'s completed branch
    /// spawns a detached `Task { await openCompleted(_:) }`; the fake's
    /// `loadOrCreate` resolves without real I/O, so a bounded `Task.yield()`
    /// poll lets that Task run to completion deterministically — no real time
    /// elapses and no sleep is needed.
    private func waitForRouteCount(_ box: RoutePathBox, atLeast count: Int) async {
        for _ in 0..<1_000 {
            if box.routes.count >= count { return }
            await Task.yield()
        }
    }

    @Test func tappingCompletedCardViaCardTappedRoutesToCompletionWithSavedTime() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        // Drive the *sync* entry point (#384's previously-untested branch).
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    @Test func rapidDoubleTapOnCompletedCardRoutesToCompletionExactlyOnce() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        // Two synchronous taps back-to-back: the second must hit the in-flight
        // latch before the first Task's `await` resolves. Both run on the
        // MainActor with no suspension between them, so the latch set in the
        // first `cardTapped` short-circuits the second.
        viewModel.cardTapped(completedCard)
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)
        // Give any erroneously-spawned second Task a chance to push.
        await Task.yield()
        await Task.yield()

        #expect(box.routes == [
            .completion(puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0)
        ])
    }

    @Test func latchResetsSoLaterTapRoutesAgain() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateSnapshot(completedSnapshot(elapsedSeconds: 742))
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let base = cards[1]
        let completedCard = DailyCard(envelope: base.envelope, isCompleted: true)

        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 1)

        // After the first open resolves the latch must clear so a re-tap
        // (e.g. returning to the hub and tapping again) works.
        viewModel.cardTapped(completedCard)
        await waitForRouteCount(box, atLeast: 2)

        let expected: AppRoute = .completion(
            puzzleId: base.envelope.identity.puzzleId, elapsedSeconds: 742, mistakeCount: 0
        )
        #expect(box.routes == [expected, expected])
    }

    @Test func tappingUncompletedCardStillRoutesToBoard() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        let box = RoutePathBox()
        let viewModel = makeViewModel(provider: provider, persistence: persistence, box: box)
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let tapped = cards[0]
        #expect(tapped.isCompleted == false)

        viewModel.cardTapped(tapped)

        #expect(box.routes == [.board(puzzleId: tapped.envelope.identity.puzzleId)])
    }

    @Test func completedCardLoadFailureReportsAndFallsBackToBoard() async {
        let provider = FakePuzzleProvider()
        let persistence = FakePersistence()
        await persistence.setLoadOrCreateError(.zoneNotProvisioned)
        let reporter = RecordingErrorReporter()
        let box = RoutePathBox()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            errorReporter: reporter,
            dateProvider: { Self.fixedDate },
            path: box.binding
        )
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected loaded state, got \(viewModel.state)")
            return
        }
        let completedCard = DailyCard(envelope: cards[2].envelope, isCompleted: true)

        await viewModel.openCompleted(completedCard)

        // Never worse than today's behavior: still navigates to the board.
        #expect(box.routes == [.board(puzzleId: cards[2].envelope.identity.puzzleId)])
        let count = await reporter.reportCount
        #expect(count == 1)
    }

    // MARK: - #526: offline / iCloud-signed-out hang regression

    /// Verifies the fix for #526: when `fetchCompletedDailyIds` hangs
    /// (e.g. iCloud signed out — CK never throws, never returns), the
    /// hub must still reach `.loaded([3 cards])` promptly rather than
    /// staying in `.loading` forever.
    ///
    /// Technique: run `bootstrap()` in a fire-and-forget `Task` (matching
    /// the `.onAppear { Task { await viewModel.bootstrap() } }` production
    /// pattern). Because our fix sets `state = .loaded(cards)` before calling
    /// `fillCompletionOverlay`, the state is observable via `Task.yield()`
    /// polling even while the fill is still suspended in the hanging
    /// persistence. After verifying state the test cancels the bootstrap task,
    /// which unblocks the continuation so the test finishes without leaking.
    @Test func bootstrapReachesLoadedEvenWhenCompletedIdsFetchHangsForever() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let hangingPersistence = HangingPersistence()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: hangingPersistence,
            dateProvider: { Self.fixedDate }
        )

        // Fire-and-forget, exactly as `.onAppear { Task { await ... } }` does.
        let bootstrapTask = Task { @MainActor in
            await viewModel.bootstrap()
        }

        // Yield cooperatively until `.loaded` or the budget runs out.
        for _ in 0..<1_000 {
            if case .loaded = viewModel.state { break }
            await Task.yield()
        }

        // Cancel so the hanging continuation resumes and the test can exit.
        bootstrapTask.cancel()
        _ = await bootstrapTask.result  // drain

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded after trio resolved, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        // All cards must be un-completed (graceful-degrade: completion unknown
        // while CK hangs, not a fatal error or a blocking spinner).
        #expect(cards.allSatisfy { !$0.isCompleted })
    }

    /// Same as above but with a persistence that throws `iCloudNotSignedIn`
    /// immediately — verifies the fast-fail error-path degrade also works.
    @Test func bootstrapReachesLoadedWhenCompletedIdsFetchThrowsICloudNotSignedIn() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))
        let persistence = ThrowingCompletionPersistence(error: PersistenceError.iCloudNotSignedIn)
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
        #expect(cards.allSatisfy { !$0.isCompleted })
    }
}

/// Records `report(_:underlying:source:)` calls so the failure-path test can
/// assert the error was funneled rather than silently swallowed.
private actor RecordingErrorReporter: ErrorReporter {
    private(set) var reportCount = 0

    func report(_ error: UserFacingError, underlying: any Error, source: String) {
        reportCount += 1
    }
}

/// Persistence fake whose `fetchCompletedDailyIds` suspends indefinitely —
/// simulates a signed-out iCloud session where CloudKit never throws and
/// never returns (the documented #526 root cause). Uses `Task.sleep` for a
/// very long duration: the enclosing `Task` cancellation in the test unblocks
/// it via structured concurrency (CancellationError propagates), which lets
/// the test drain cleanly. Avoids the Swift 6 `@Sendable`-capture issue that
/// arises when storing a `CheckedContinuation` directly on an actor.
private actor HangingPersistence: PersistenceProtocol {

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        // Suspend for an hour — the test cancels the bootstrap Task long
        // before this expires, so CancellationError unblocks the test.
        try await Task.sleep(for: .seconds(3_600))
        return []
    }

    // MARK: - Minimal PersistenceProtocol forwarding

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy,
            bestTimeSeconds: nil, totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
} // HangingPersistence

/// Persistence fake whose `fetchCompletedDailyIds` throws immediately with a
/// given error — covers the fast-fail degrade path (e.g. `iCloudNotSignedIn`).
private actor ThrowingCompletionPersistence: PersistenceProtocol {

    private let error: any Error

    init(error: any Error) {
        self.error = error
    }

    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> {
        throw error
    }

    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(puzzleId: String, mode: Mode, difficulty: Difficulty) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(_ snapshot: GameSessionSnapshot, puzzleId: String, mode: Mode, difficulty: Difficulty) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "", mode: .daily, difficulty: .easy,
            bestTimeSeconds: nil, totalTimeSeconds: 0, completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0), completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}

} // ThrowingCompletionPersistence
