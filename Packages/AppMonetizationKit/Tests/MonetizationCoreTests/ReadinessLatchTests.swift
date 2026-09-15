import Foundation
import Synchronization
import Testing
@testable import MonetizationCore

// Every wait here is bounded: a latch that never opens must FAIL the test
// (the timer cancels the waiter), never hang the suite.

/// Records a task's outcome so a test can poll it against a deadline. A
/// waiter whose continuation is never resumed cannot be unblocked by
/// cancelling it again, so awaiting its `result` would hang the suite.
private final class OutcomeBox: Sendable {
    private let outcome = Mutex<Result<Void, any Error>?>(nil)

    var value: Result<Void, any Error>? { outcome.withLock { $0 } }

    func set(_ result: Result<Void, any Error>) {
        outcome.withLock { $0 = result }
    }
}

private func waitForOutcome(
    _ box: OutcomeBox,
    timeout: Duration = .seconds(2)
) async -> Result<Void, any Error>? {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while box.value == nil, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
    return box.value
}

@Suite("MonetizationCore — ReadinessLatch", .timeLimit(.minutes(1)))
struct ReadinessLatchTests {

    /// Awaits `task`, cancelling it first if it is still running after
    /// `timeout`. Returns the task's result and whether the timeout fired.
    private func boundedResult(
        of task: Task<Void, any Error>,
        timeout: Duration = .seconds(2)
    ) async -> (result: Result<Void, any Error>, timedOut: Bool) {
        let timer = Task<Bool, Never> {
            do {
                try await Task.sleep(for: timeout)
                task.cancel()
                return true
            } catch {
                return false
            }
        }
        let result = await task.result
        timer.cancel()
        return (result, await timer.value)
    }

    @Test func openLatchReturnsImmediately() async throws {
        let latch = ReadinessLatch(isOpen: true)
        let outcome = await boundedResult(of: Task { try await latch.wait() })
        #expect(!outcome.timedOut)
        #expect(throws: Never.self) { try outcome.result.get() }
    }

    @Test func waiterResumesWhenOpened() async throws {
        let latch = ReadinessLatch()
        let waiter = Task { try await latch.wait() }
        try await Task.sleep(for: .milliseconds(50))
        #expect(!latch.isOpen)

        latch.open()

        let outcome = await boundedResult(of: waiter)
        #expect(!outcome.timedOut, "open() must resume a suspended waiter")
        #expect(throws: Never.self) { try outcome.result.get() }
    }

    @Test func multipleWaitersAllResume() async throws {
        let latch = ReadinessLatch()
        let first = Task { try await latch.wait() }
        let second = Task { try await latch.wait() }
        try await Task.sleep(for: .milliseconds(50))

        latch.open()

        #expect(await !boundedResult(of: first).timedOut)
        #expect(await !boundedResult(of: second).timedOut)
    }

    @Test func openIsIdempotentAndNeverRecloses() async throws {
        let latch = ReadinessLatch()
        latch.open()
        latch.open()
        #expect(latch.isOpen)
        let outcome = await boundedResult(of: Task { try await latch.wait() })
        #expect(!outcome.timedOut)
    }

    @Test func cancelledWaiterThrowsCancellationWhileClosed() async throws {
        let latch = ReadinessLatch()
        let waiter = Task { try await latch.wait() }
        try await Task.sleep(for: .milliseconds(50))

        waiter.cancel()

        let outcome = await boundedResult(of: waiter)
        #expect(!outcome.timedOut)
        #expect(throws: CancellationError.self) { try outcome.result.get() }
        #expect(!latch.isOpen, "cancelling a waiter must not open the latch")
    }

    @Test func alreadyCancelledTaskReturnsIfLatchOpen() async {
        let latch = ReadinessLatch(isOpen: true)
        let waiter = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            try await latch.wait()
        }
        let outcome = await boundedResult(of: waiter)
        #expect(throws: Never.self) { try outcome.result.get() }
    }

    @Test func alreadyCancelledTaskThrowsIfLatchClosed() async {
        let latch = ReadinessLatch()
        let box = OutcomeBox()
        Task {
            withUnsafeCurrentTask { $0?.cancel() }
            do {
                try await latch.wait()
                box.set(.success(()))
            } catch {
                box.set(.failure(error))
            }
        }

        guard let outcome = await waitForOutcome(box) else {
            Issue.record("wait() on a closed latch from an already-cancelled task never returned")
            return
        }
        #expect(throws: CancellationError.self) { try outcome.get() }
        #expect(!latch.isOpen)
    }

    @Test func openRacingCancellationResumesEveryWaiterExactlyOnce() async {
        for iteration in 0..<200 {
            let latch = ReadinessLatch()
            let boxes = (0..<20).map { _ in OutcomeBox() }
            let waiters = boxes.map { box in
                Task {
                    do {
                        try await latch.wait()
                        box.set(.success(()))
                    } catch {
                        box.set(.failure(error))
                    }
                }
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { latch.open() }
                for waiter in waiters.enumerated() where waiter.offset.isMultiple(of: 2) {
                    group.addTask { waiter.element.cancel() }
                }
            }

            let deadline = ContinuousClock.now.advanced(by: .seconds(2))
            while boxes.contains(where: { $0.value == nil }), ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(1))
            }
            let unresolved = boxes.filter { $0.value == nil }.count
            guard unresolved == 0 else {
                Issue.record("iteration \(iteration): \(unresolved) waiter(s) were never resumed")
                return
            }
            let uncancelledFailures = boxes.enumerated().filter { entry in
                guard !entry.offset.isMultiple(of: 2), case .failure = entry.element.value else { return false }
                return true
            }
            guard uncancelledFailures.isEmpty else {
                Issue.record("iteration \(iteration): an uncancelled waiter threw")
                return
            }
        }
    }
}
