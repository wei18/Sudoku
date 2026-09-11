import Foundation
import Synchronization

// MARK: - ObservedTask
//
// A task whose completion can be checked WITHOUT awaiting it, so a test can
// assert "still suspended on readiness" and bound every wait. A regression
// that leaves the operation suspended forever must fail the test (the timeout
// cancels it), never hang the suite.

internal struct ObservedTask: Sendable {
    private final class FinishedFlag: Sendable {
        private let value = Mutex(false)
        var isSet: Bool { value.withLock { $0 } }
        func set() { value.withLock { $0 = true } }
    }

    private let task: Task<Void, any Error>
    private let finished: FinishedFlag

    internal init(_ operation: @escaping @Sendable () async throws -> Void) {
        let finished = FinishedFlag()
        self.finished = finished
        self.task = Task {
            defer { finished.set() }
            try await operation()
        }
    }

    internal var isFinished: Bool { finished.isSet }

    internal func cancel() { task.cancel() }

    /// Awaits the operation, cancelling it first if it is still running after
    /// `timeout`. Returns its result and whether the timeout fired.
    internal func boundedResult(
        timeout: Duration = .seconds(2)
    ) async -> (result: Result<Void, any Error>, timedOut: Bool) {
        let task = self.task
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
}

/// Polls `condition` every 10ms until it holds or `timeout` elapses.
internal func eventually(
    timeout: Duration = .seconds(2),
    _ condition: () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
