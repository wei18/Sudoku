internal import Foundation
import Synchronization

// MARK: - ReadinessLatch (#1058)
//
// A one-way, awaitable latch backing `AdProvider.awaitReady()`. It starts
// closed (or open, for providers with nothing to start), opens exactly once
// via `open()`, and never re-closes.
//
// Cancellation: a waiter whose task is cancelled while the latch is still
// closed stops waiting and throws `CancellationError`. Without this, a banner
// slot that disappeared during cold launch would stay suspended and resume
// after boot into an ad request nobody renders or disposes. Once the latch is
// open, `wait()` returns without throwing even for a cancelled task — it only
// reports cancellation that actually interrupted a wait.
//
// Concurrency: `Mutex`-backed (same shape as `AdGate`'s synchronous seed) so
// `open()` and the cancellation handler run synchronously from any context,
// with no actor hop that could reorder against a registration.

public final class ReadinessLatch: Sendable {
    private struct State {
        var isOpen: Bool
        var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
    }

    private let state: Mutex<State>

    public init(isOpen: Bool = false) {
        self.state = Mutex(State(isOpen: isOpen))
    }

    public var isOpen: Bool {
        state.withLock { $0.isOpen }
    }

    /// Opens the latch and resumes every current waiter. Idempotent.
    public func open() {
        let pending = state.withLock { state -> [CheckedContinuation<Void, any Error>] in
            guard !state.isOpen else { return [] }
            state.isOpen = true
            let waiters = Array(state.waiters.values)
            state.waiters = [:]
            return waiters
        }
        for continuation in pending {
            continuation.resume()
        }
    }

    /// Returns once the latch is open (immediately if it already is).
    ///
    /// - Throws: `CancellationError` only if the calling task is cancelled
    ///   while the latch is still closed.
    public func wait() async throws {
        if isOpen { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let immediate = state.withLock { state -> Result<Void, any Error>? in
                    if state.isOpen { return .success(()) }
                    if Task.isCancelled { return .failure(CancellationError()) }
                    state.waiters[id] = continuation
                    return nil
                }
                if let immediate {
                    continuation.resume(with: immediate)
                }
            }
        } onCancel: {
            let waiter = state.withLock { $0.waiters.removeValue(forKey: id) }
            waiter?.resume(throwing: CancellationError())
        }
    }
}
