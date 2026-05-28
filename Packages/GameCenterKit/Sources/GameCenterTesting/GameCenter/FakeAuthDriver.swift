// FakeAuthDriver — scripted `AuthDriver` for `LiveGameCenterClient` tests.
//
// The Live client is constructed with an injected `AuthDriver`; tests
// inject this fake to drive every state transition (signed-in, signed-out,
// restricted, cancelled, error, unavailable-in-region) without touching
// real GameKit.

import Foundation
public import GameCenterClient

public actor FakeAuthDriver: AuthDriver {

    public var nextOutcome: AuthOutcome
    private var continuations: [UUID: AsyncStream<AuthOutcome>.Continuation] = [:]

    public init(nextOutcome: AuthOutcome = .signedIn(
        PlayerSummary(teamPlayerId: "P0001", displayName: "Tester")
    )) {
        self.nextOutcome = nextOutcome
    }

    public func setNextOutcome(_ outcome: AuthOutcome) {
        self.nextOutcome = outcome
    }

    public func performAuthentication() async -> AuthOutcome {
        nextOutcome
    }

    public func observeStateChanges() async -> AsyncStream<AuthOutcome> {
        let id = UUID()
        let (stream, continuation) = AsyncStream<AuthOutcome>.makeStream()
        continuations[id] = continuation
        continuation.onTermination = { @Sendable [weak self] _ in
            Task { await self?.unregister(id) }
        }
        return stream
    }

    private func unregister(_ id: UUID) {
        continuations.removeValue(forKey: id)
    }

    /// Push an outcome into every active `observeStateChanges()` consumer.
    public func emit(_ outcome: AuthOutcome) {
        for continuation in continuations.values {
            continuation.yield(outcome)
        }
    }
}
