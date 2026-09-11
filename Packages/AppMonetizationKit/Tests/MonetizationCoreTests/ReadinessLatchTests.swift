import Foundation
import Testing
@testable import MonetizationCore

// Every wait here is bounded: a latch that never opens must FAIL the test
// (the timer cancels the waiter), never hang the suite.

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
}
