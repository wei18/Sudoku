// GameSessionStatus — finite state machine for a single GameSession.
//
// Per design.md §How.5.3, the legal lifecycle is:
//
//     idle → playing (start)
//     playing → paused (pause)
//     paused → playing (resume)
//     playing → completed (complete)
//     playing → abandoned (abandon)
//     paused → abandoned (abandon)
//
// Every other (from, transition) pair is illegal and surfaces as
// `GameSessionError.illegalTransition` at the call site that drives the
// machine (see `GameSession`).
//
// Pure data — no actor isolation, no I/O — so this file lives independent
// of `GameSession` and can be reused / unit-tested in isolation.

public enum GameSessionStatus: String, Sendable, Hashable, Codable, CaseIterable {
    case idle
    case playing
    case paused
    case completed
    case abandoned
}

public enum GameSessionTransition: String, Sendable, Hashable, Codable, CaseIterable {
    case start
    case pause
    case resume
    case complete
    case abandon
}

extension GameSessionStatus {

    /// True if `transition` may be applied while the session is in `from`.
    /// Pure function — encodes the design.md §How.5.3 transition table.
    public static func isLegal(
        from: GameSessionStatus,
        applying transition: GameSessionTransition
    ) -> Bool {
        switch (from, transition) {
        case (.idle, .start),
             (.playing, .pause),
             (.paused, .resume),
             (.playing, .complete),
             (.playing, .abandon),
             (.paused, .abandon):
            return true
        default:
            return false
        }
    }

    /// The destination state when applying `transition` from this state.
    /// Returns nil if the transition is illegal.
    public func applying(_ transition: GameSessionTransition) -> GameSessionStatus? {
        switch (self, transition) {
        case (.idle, .start):       return .playing
        case (.playing, .pause):    return .paused
        case (.paused, .resume):    return .playing
        case (.playing, .complete): return .completed
        case (.playing, .abandon):  return .abandoned
        case (.paused, .abandon):   return .abandoned
        default:                    return nil
        }
    }
}
