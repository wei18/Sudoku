// CellFeedbackStateTests — #1018: the idle -> animating -> idle lifecycle.
// Tests settle by awaiting the expiry Task's value, never by Task.yield().

import Observation
import Testing
@testable import GameShellUI

/// A hand-released sleeper: `wait()` suspends until `release()`.
private actor Gate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        if released { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
@Suite("CellFeedbackState — concurrent events, expiry (#1018)")
struct CellFeedbackStateTests {

    @Test("idle -> begin -> not idle -> end -> idle")
    func lifecycle() {
        let state = CellFeedbackState<Int>()
        #expect(state.isIdle)
        let token = state.begin(1)
        #expect(!state.isIdle)
        state.end(token)
        #expect(state.isIdle)
    }

    @Test("two overlapping events are both active, in begin order")
    func overlappingEventsKeepBeginOrder() {
        let state = CellFeedbackState<Int>()
        let first = state.begin(1)
        let second = state.begin(2)
        #expect(state.activeEvents.map(\.event) == [1, 2])
        #expect(state.activeEvents.map(\.token) == [first, second])
    }

    @Test("ending the first leaves the second active")
    func endingFirstKeepsSecond() {
        let state = CellFeedbackState<Int>()
        let first = state.begin(1)
        _ = state.begin(2)
        state.end(first)
        #expect(state.activeEvents.map(\.event) == [2])
        #expect(!state.isIdle)
    }

    @Test("ending a token twice, or an unknown token, is a no-op")
    func endingTwiceIsNoOp() {
        let state = CellFeedbackState<Int>()
        let first = state.begin(1)
        _ = state.begin(2)
        state.end(first)
        state.end(first)
        #expect(state.activeEvents.map(\.event) == [2])
    }

    @Test("scheduled event stays active until the sleeper is released, idle after task.value")
    func scheduledExpiry() async {
        let state = CellFeedbackState<Int>()
        let gate = Gate()
        let scheduled = state.begin(7, lifetime: .milliseconds(200)) { _ in await gate.wait() }
        #expect(state.activeEvents.map(\.event) == [7])
        #expect(state.activeEvents.map(\.token) == [scheduled.token])
        await gate.release()
        await scheduled.task.value
        #expect(state.isIdle)
    }

    @Test("pending expiries: empty after an expiry completes")
    func pendingEmptyAfterExpiry() async {
        let state = CellFeedbackState<Int>()
        let gate = Gate()
        _ = state.begin(1, lifetime: .milliseconds(200)) { _ in await gate.wait() }
        #expect(state.pendingExpiries.count == 1)
        await gate.release()
        await state.waitForPendingExpiries()
        #expect(state.pendingExpiries.isEmpty)
        #expect(state.isIdle)
    }

    @Test("pending expiries: holds exactly the unreleased ones while two overlap")
    func pendingHoldsUnreleasedWhileOverlapping() async {
        let state = CellFeedbackState<Int>()
        let firstGate = Gate()
        let secondGate = Gate()
        let first = state.begin(1, lifetime: .milliseconds(200)) { _ in await firstGate.wait() }
        _ = state.begin(2, lifetime: .milliseconds(200)) { _ in await secondGate.wait() }
        #expect(state.pendingExpiries.count == 2)

        await firstGate.release()
        await first.task.value
        #expect(state.pendingExpiries.count == 1)

        await secondGate.release()
        await state.waitForPendingExpiries()
        #expect(state.pendingExpiries.isEmpty)
    }

    @Test("pending expiries: empty right after an early end")
    func pendingEmptyAfterEarlyEnd() async {
        let state = CellFeedbackState<Int>()
        let gate = Gate()
        let scheduled = state.begin(1, lifetime: .milliseconds(200)) { _ in await gate.wait() }
        #expect(state.pendingExpiries.count == 1)
        state.end(scheduled.token)
        #expect(state.pendingExpiries.isEmpty)
        #expect(state.isIdle)
        await gate.release()
        await scheduled.task.value
    }

    @Test("an early end cancels a cancellation-aware sleeper instead of leaving it running")
    func earlyEndCancelsTheSleeper() async {
        let state = CellFeedbackState<Int>()
        // A real, cancellation-aware sleep; 5 s is the hard bound if the cancel is missing.
        let scheduled = state.begin(1, lifetime: .seconds(5)) { duration in
            try? await Task.sleep(for: duration)
        }
        state.end(scheduled.token)
        let elapsed = await ContinuousClock().measure { await scheduled.task.value }
        #expect(elapsed < .seconds(2), "the sleeper kept running after an early end (took \(elapsed))")
        #expect(state.pendingExpiries.isEmpty)
    }

    /// Flips when an observed property of the state changes.
    private final class ChangeFlag: @unchecked Sendable {
        var fired = false
    }

    @Test("ending an unknown or already-ended token mutates nothing")
    func endingUnknownTokenNotifiesNoObserver() {
        let state = CellFeedbackState<Int>()
        let token = state.begin(1)
        state.end(token)
        let flag = ChangeFlag()
        withObservationTracking {
            _ = state.activeEvents
            _ = state.pendingExpiries
        } onChange: {
            flag.fired = true
        }
        state.end(token)
        #expect(!flag.fired, "ending an already-ended token still mutated observed state")
    }

    @Test("the pending expiry task does not keep the state alive")
    func pendingTaskDoesNotRetainState() async {
        let gate = Gate()
        weak var weakState: CellFeedbackState<Int>?
        var task: Task<Void, Never>?
        do {
            let state = CellFeedbackState<Int>()
            weakState = state
            task = state.begin(1, lifetime: .milliseconds(200)) { _ in await gate.wait() }.task
        }
        #expect(weakState == nil, "a sleeping expiry task kept the state alive")
        await gate.release()
        await task?.value
    }

    @Test("a second event begun while the first sleeper is held is active immediately")
    func secondEventNotBlockedByFirst() async {
        let state = CellFeedbackState<Int>()
        let firstGate = Gate()
        let secondGate = Gate()
        let first = state.begin(1, lifetime: .milliseconds(200)) { _ in await firstGate.wait() }
        let second = state.begin(2, lifetime: .milliseconds(200)) { _ in await secondGate.wait() }
        #expect(state.activeEvents.map(\.event) == [1, 2])

        await firstGate.release()
        await first.task.value
        #expect(state.activeEvents.map(\.event) == [2])

        await secondGate.release()
        await second.task.value
        #expect(state.isIdle)
    }
}
