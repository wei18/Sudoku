// ResumeCandidateBoardPreviewTests — #1017.
//
// `ResumeCandidate`'s new `boardPreview: BoardPreview?` field must never
// block resume: a `nil` preview (the degrade path when a per-app mapper
// couldn't build one from a malformed/missing payload) still resolves
// through `GameRootViewModel.bootstrap()` exactly like a candidate carrying
// one. Split out of `GameRootViewModelTests.swift` to keep that file under
// SwiftLint's 400-line ceiling.

import Testing
import GameShellUI
import GameCenterClient
import Persistence
import SudokuGameState
import SudokuEngine
import Foundation
@testable import GameAppKit

private enum PreviewRoute: Hashable, Sendable {
    case board(puzzleId: String)
}

private actor MinimalPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }

    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }

    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}

    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }

    func fetchPersonalRecord(
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }

    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

private struct MinimalGameCenter: GameCenterClient {
    func authenticate() async throws -> GameCenterAuthState { .unauthenticated }
    func authStateUpdates() async -> AsyncStream<GameCenterAuthState> { AsyncStream { $0.finish() } }

    func submitScore(
        puzzleId: String,
        elapsedSeconds: Int,
        leaderboardKind: LeaderboardKind
    ) async throws {}

    func submitScore(leaderboardId: String, elapsedSeconds: Int) async throws {}
    func reportAchievement(_ achievement: AchievementProgress) async throws {}
}

@MainActor
@Suite("ResumeCandidate — boardPreview (#1017)")
struct ResumeCandidateBoardPreviewTests {

    /// `boardPreview` defaults to `nil` and must not block resume —
    /// `bootstrap()` still resolves the candidate and the pill still has a
    /// title/subtitle/route to render.
    @Test func bootstrapResolvesCandidateWithNilBoardPreview() async {
        let candidate = ResumeCandidate(
            title: "Resume Easy",
            subtitle: "3:21",
            route: PreviewRoute.board(puzzleId: "2026-05-19-easy")
        )
        #expect(candidate.boardPreview == nil)

        let viewModel = GameRootViewModel<PreviewRoute>(
            gameCenter: MinimalGameCenter(),
            persistence: MinimalPersistence(),
            fetchResume: { candidate }
        )

        await viewModel.bootstrap()

        #expect(viewModel.resumeCandidate == candidate)
        #expect(viewModel.resumeCandidate?.boardPreview == nil)
    }

    /// A candidate that DOES carry a preview still round-trips through
    /// `ResumeCandidate`'s `Equatable` conformance and `bootstrap()`.
    @Test func bootstrapResolvesCandidateWithBoardPreview() async throws {
        let preview = try #require(BoardPreview(columns: 2, rows: 1, cells: [.given, .empty]))
        let candidate = ResumeCandidate(
            title: "Resume Easy",
            subtitle: "3:21",
            route: PreviewRoute.board(puzzleId: "2026-05-19-easy"),
            boardPreview: preview
        )

        let viewModel = GameRootViewModel<PreviewRoute>(
            gameCenter: MinimalGameCenter(),
            persistence: MinimalPersistence(),
            fetchResume: { candidate }
        )

        await viewModel.bootstrap()

        #expect(viewModel.resumeCandidate?.boardPreview == preview)
    }
}
