// CellFeedbackState — the idle -> animating -> idle lifecycle of per-cell
// success feedback (#1018), written once for both games' view models.
//
// It holds a COLLECTION of concurrently active events in begin order, never a
// single slot: a second event can never replace, drop or wait for the first.
// Deliberately no notion of "busy" — feedback is cosmetic and must never gate
// input.

public import Observation

/// Sleeps for a duration; injected so tests release expiry by hand.
public typealias CellFeedbackSleeper = @Sendable (Duration) async -> Void

/// Live sleeper. Cancellation just ends the sleep early.
public func liveCellFeedbackSleeper(_ duration: Duration) async {
    try? await Task.sleep(for: duration)
}

@MainActor
@Observable
public final class CellFeedbackState<Event: Sendable> {
    public struct Token: Hashable, Sendable {
        fileprivate let rawValue: Int
    }

    public struct Entry: Sendable {
        public let token: Token
        public let event: Event
    }

    /// Active events in begin order.
    public private(set) var activeEvents: [Entry] = []

    private var nextRawValue = 0
    /// Expiry tasks scheduled by `begin(_:lifetime:sleeper:)` that have not
    /// finished yet, in begin order. The state holds each task (the task holds
    /// the state only weakly, so a sleeping task never keeps it alive) and
    /// drops the entry as soon as the event ends, whether by expiry or early.
    private var pending: [(token: Token, task: Task<Void, Never>)] = []

    public init() {}

    public var isIdle: Bool { activeEvents.isEmpty }

    /// The expiry tasks still pending, in begin order — what a test needs to
    /// settle (`await` each task's value) without yielding.
    public var pendingExpiries: [Task<Void, Never>] { pending.map(\.task) }

    /// Wait until every expiry pending at the time of the call has finished.
    public func waitForPendingExpiries() async {
        for task in pendingExpiries { await task.value }
    }

    @discardableResult
    public func begin(_ event: Event) -> Token {
        let token = Token(rawValue: nextRawValue)
        nextRawValue += 1
        activeEvents.append(Entry(token: token, event: event))
        return token
    }

    /// Ending an unknown or already-ended token is a true no-op: it mutates
    /// nothing, so observers are not notified. Otherwise it also drops the
    /// token's pending expiry task and cancels it (an early end must not leave
    /// a sleeper running).
    public func end(_ token: Token) {
        guard activeEvents.contains(where: { $0.token == token }) else { return }
        activeEvents.removeAll { $0.token == token }
        for entry in pending where entry.token == token { entry.task.cancel() }
        pending.removeAll { $0.token == token }
    }

    /// Begin `event` and end it after `lifetime`. The state keeps the expiry
    /// task in `pendingExpiries` until the event ends; the returned task is
    /// the same one, and completes once the event has ended.
    @discardableResult
    public func begin(
        _ event: Event,
        lifetime: Duration,
        sleeper: @escaping CellFeedbackSleeper = liveCellFeedbackSleeper
    ) -> (token: Token, task: Task<Void, Never>) {
        let token = begin(event)
        let task = Task { [weak self] in
            await sleeper(lifetime)
            self?.end(token)
        }
        pending.append((token, task))
        return (token, task)
    }
}
