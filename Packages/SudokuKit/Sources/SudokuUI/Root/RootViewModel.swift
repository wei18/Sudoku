// RootViewModel — coordinates app-launch bootstrap.
//
// Per design.md §How.5.4 (VM ownership / @Observable @MainActor). Owns the
// auth handshake (`GameCenterClient.authenticate`) and the resume-candidate
// fetch (`PersistenceProtocol.latestInProgress`). Both are kicked off in
// `bootstrap()` from the View's `.task`.
//
// Errors from either fetch are swallowed into degraded states — Root should
// never block Home (design.md §How.5.1: "Bootstrap never blocks Home").

public import Foundation
public import GameCenterClient
public import Persistence

@MainActor
@Observable
public final class RootViewModel {

    public private(set) var authState: GameCenterAuthState = .unknown
    public private(set) var resumeCandidate: SavedGameSummary?
    public private(set) var hasBootstrapped: Bool = false
    public var path: [AppRoute] = []

    private let gameCenter: any GameCenterClient
    private let persistence: any PersistenceProtocol

    public init(
        gameCenter: any GameCenterClient,
        persistence: any PersistenceProtocol
    ) {
        self.gameCenter = gameCenter
        self.persistence = persistence
    }

    /// Idempotent: only the first call performs IO; subsequent calls return
    /// immediately so View `.task` re-entries (size-class changes etc.) do
    /// not re-trigger GameKit auth.
    public func bootstrap() async {
        guard !hasBootstrapped else { return }
        hasBootstrapped = true

        do {
            self.authState = try await gameCenter.authenticate()
        } catch {
            self.authState = .unauthenticated
        }

        self.resumeCandidate = (try? await persistence.latestInProgress()) ?? nil
    }

    public func resumeTapped() {
        guard let candidate = resumeCandidate else { return }
        path.append(.board(puzzleId: candidate.puzzleId))
    }
}
