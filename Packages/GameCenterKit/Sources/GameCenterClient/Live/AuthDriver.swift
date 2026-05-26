// AuthDriver — internal seam over `GKLocalPlayer.authenticateHandler`.
//
// `LiveGameCenterClient` does not call GameKit directly: it talks to an
// `AuthDriver`. Production wiring injects `GKAuthDriver` (the only file
// in this package that imports `GameKit`); tests inject `FakeAuthDriver`
// from `SudokuKitTesting`.
//
// This split keeps unit tests off the live framework (which cannot be
// exercised in CI without sandbox accounts — plan.md Phase 10) and makes
// every state transition + error mapping trivially scriptable.

internal import Foundation

public protocol AuthDriver: Sendable {
    /// Run the GameKit auth handshake exactly once. The outcome surfaces
    /// the player identity on success or a structured failure case.
    func performAuthentication() async -> AuthOutcome

    /// Continuous stream of subsequent state changes (sign-out, restricted
    /// mode toggle, region change). Caller `for await`s this for as long
    /// as the client lives.
    func observeStateChanges() async -> AsyncStream<AuthOutcome>
}

public enum AuthOutcome: Sendable, Equatable {
    case signedIn(PlayerSummary)
    case signedOut
    case restricted
    case unavailableInRegion
    case cancelled
    case error(String)
}
