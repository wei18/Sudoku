// TerminalPersistJoin — join point between a board's terminal-state persist
// and the hub's teardown-triggered refresh (#823).
//
// Bug this closes: the Completion overlay's Close/Play Again call `dismiss()`
// synchronously, which (via `GameRoot`'s fullScreenCover binding / path-shrink
// branch) bumps `GameRootViewModel.sessionTeardownCount` — the signal the
// Daily hubs `.onChange` to refresh (#761). That bump used to be unconditional
// and immediate, so a fast tap could fire the hub refresh BEFORE a slow
// CloudKit save (`persistCurrentState()` / `markCompletedIfNeeded()`, awaited
// inline inside the board VM's terminal-transition method) had actually
// landed — the just-finished daily could show unmarked until the next
// refresh trigger.
//
// Fix shape (Leader-adjudicated direction, issue #823 option 1): keep
// `dismiss()` itself instant — never delay the actual UI collapse — and move
// the join to the refresh TRIGGER instead. The board view, right before
// calling `dismiss()` / popping `path`, registers its in-flight
// terminal-persist `Task` here (a plain synchronous property write — adds no
// latency). `GameRootViewModel.gameSessionDidTearDown(persistJoin:)` then
// defers the `sessionTeardownCount` bump into an unstructured `Task` that
// awaits `awaitPending()` — bounded by `timeout` — before incrementing. A
// hung save degrades to today's transient-staleness behavior (the counter
// still bumps once the timeout elapses; a later teardown gives a second
// chance, as documented in the issue's "mitigating factors") instead of
// blocking the hub refresh forever.
//
// Owned by `GameRoot` as `@State` (one instance per Root, mirrors
// `GameChromeState`'s lifetime) and injected downward via
// `\.terminalPersistJoin` so board views (`SudokuUI.BoardView`,
// `MinesweeperUI.MinesweeperBoardView`) can reach it without a direct
// reference. `GameRoot` also holds the same instance directly, so it can pass
// it straight into `dismissGame(persistJoin:)` / `gameSessionDidTearDown(persistJoin:)`
// without a round-trip through `@Environment` on the (non-View) view model.

public import SwiftUI

// MARK: - TerminalPersistJoin

/// Shared carrier: the board registers its in-flight terminal-persist `Task`;
/// the teardown path awaits it (bounded) before signalling session end.
@MainActor
public final class TerminalPersistJoin {
    private var pendingTask: Task<Void, Never>?
    private let timeout: Duration

    /// - Parameter timeout: upper bound on how long `awaitPending()` will wait
    ///   for a registered task before giving up. Defaults to 3 seconds —
    ///   comfortably above a healthy CloudKit save round-trip, short enough
    ///   that a hung save doesn't make Home feel stuck. Overridable so tests
    ///   can shrink it and stay fast.
    public init(timeout: Duration = .seconds(3)) {
        self.timeout = timeout
    }

    /// Register the in-flight terminal-persist task (or `nil` if none is
    /// outstanding). Call this synchronously, right before `dismiss()` /
    /// popping `path` — it is a plain property write, so it adds no latency
    /// to the dismiss action itself. Overwrites any previous registration:
    /// only the most recent terminal transition's save matters.
    public func register(_ task: Task<Void, Never>?) {
        pendingTask = task
    }

    /// Await the registered task, bounded by `timeout`. Clears the handle
    /// first so a second concurrent/subsequent teardown never double-awaits
    /// (or blocks on) a stale registration. No-ops instantly when nothing is
    /// registered (the common case — most dismissals aren't mid-save) or
    /// when the registered task already finished (awaiting a completed `Task`
    /// returns immediately). The underlying task is never cancelled on
    /// timeout — a slow save still gets to complete and land on its own; we
    /// simply stop waiting for it here.
    ///
    /// Deliberately NOT a `withTaskGroup` race: a `TaskGroup` implicitly
    /// awaits every child before returning from scope, even ones you've
    /// called `cancelAll()` on — and `await task.value` does not itself
    /// observe cancellation (it always waits for `task`'s actual outcome).
    /// That combination silently defeats the bound (a hung task keeps the
    /// whole group parked for its full runtime instead of the timeout).
    /// Two independent unstructured `Task`s + a single continuation resumed
    /// exactly once by whichever finishes first avoids that trap: this
    /// function returns as soon as the winner resumes, and the loser is left
    /// to finish (or keep hanging) on its own, unobserved.
    public func awaitPending() async {
        guard let task = pendingTask else { return }
        pendingTask = nil
        let timeout = timeout
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let once = ResumeOnce(continuation)
            Task {
                await task.value
                await once.resume()
            }
            Task {
                try? await Task.sleep(for: timeout)
                await once.resume()
            }
        }
    }
}

// MARK: - ResumeOnce

/// Actor-guarded "resume exactly once" wrapper — two racing unstructured
/// `Task`s both hold a reference and may call `resume()` at effectively the
/// same time; only the first must actually resume the continuation.
private actor ResumeOnce {
    private var didResume = false
    private let continuation: CheckedContinuation<Void, Never>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = continuation
    }

    func resume() {
        guard !didResume else { return }
        didResume = true
        continuation.resume()
    }
}

// MARK: - EnvironmentKey

private struct TerminalPersistJoinKey: EnvironmentKey {
    static let defaultValue: TerminalPersistJoin? = nil
}

public extension EnvironmentValues {
    /// The active `TerminalPersistJoin` injected by `GameRoot`. Board views
    /// read this to register their in-flight terminal-persist task before
    /// dismissing (#823).
    var terminalPersistJoin: TerminalPersistJoin? {
        get { self[TerminalPersistJoinKey.self] }
        set { self[TerminalPersistJoinKey.self] = newValue }
    }
}
