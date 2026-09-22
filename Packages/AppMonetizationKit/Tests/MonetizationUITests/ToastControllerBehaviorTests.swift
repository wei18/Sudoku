// ToastControllerBehaviorTests — MS monetization wire Phase 1.
//
// Pure behavior tests for `ToastController` that don't need the SudokuUI
// snapshot harness. Full snapshot baselines (`ToastView-success-light`,
// `ToastView-failure-light`) stay in `SudokuUITests/ToastTests.swift`
// because they reuse the `SnapshotConfig` / `hostingView` helpers wired
// there. This file mirrors the non-snapshot half so MonetizationUI has
// its own zero-dep test suite.
//
// Auto-dismiss tests inject a `ManualSleeper` through `ToastController`'s
// sleep seam (#1087) instead of racing a wall-clock duration — timing is
// driven entirely by continuation release, so results never depend on how
// long anything sleeps.

import Testing

@testable import MonetizationUI

/// Test double for `ToastController`'s sleep seam: parks each call to
/// `sleep()` on a continuation instead of actually sleeping, and only
/// resumes it when the test explicitly calls `releaseNext()`.
@MainActor
private final class ManualSleeper {
    private var parked: [CheckedContinuation<Void, Never>] = []
    /// Running total of calls that have ever parked — deliberately not
    /// decremented by `releaseNext()`, so `waitUntilParked(_:)` always means
    /// "at least N calls have started", independent of release order.
    private var parkedCount = 0
    private var waiter: (threshold: Int, continuation: CheckedContinuation<Bool, Never>, timeoutTask: Task<Void, Never>)?

    /// Parks until `releaseNext()` resumes it. Deliberately does not respond
    /// to task cancellation — a `show()` that supersedes a toast cancels the
    /// owning dismiss `Task`, but this sleeper still only resumes on an
    /// explicit `releaseNext()`. That's the point: it lets
    /// `show_replacesPreviousToast_staleSleeperDoesNotClearNewToast` prove
    /// the `Task.isCancelled` guard in `ToastController.show()` — not any
    /// cooperation from the sleep seam — is what stops a stale, later
    /// released sleeper from clearing a newer toast.
    func sleep() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            parked.append(continuation)
            parkedCount += 1
            // `waiter` has exactly two possible resumers — this park path and
            // the timeout path in `timeoutWaiter(threshold:)`. Both run
            // synchronously on `@MainActor` with no suspension between
            // reading `waiter` and clearing it to `nil`, so whichever path
            // gets here first "takes" the stored continuation atomically;
            // the other path's `waiter` read afterwards sees `nil` and does
            // nothing. That's what guarantees each continuation is resumed
            // exactly once — `CheckedContinuation` traps on a second resume.
            if let waiter, parkedCount >= waiter.threshold {
                self.waiter = nil
                waiter.timeoutTask.cancel()
                waiter.continuation.resume(returning: true)
            }
        }
    }

    /// Suspends until at least `count` calls to `sleep()` have parked, or
    /// returns `false` after a 5 s bound elapses. The bound has no
    /// wall-clock meaning for a healthy test — it returns the instant enough
    /// calls park. It exists only so a *broken* test (e.g. `show()`
    /// bypassing the injected `sleep` seam entirely) fails fast instead of
    /// hanging forever.
    func waitUntilParked(_ count: Int) async -> Bool {
        if parkedCount >= count { return true }
        var timeoutTask: Task<Void, Never>?
        let parkedInTime = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            let task = Task { [weak self] in
                // failure-path bound only: a passing run returns when the
                // sleeper parks and cancels this
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.timeoutWaiter(threshold: count)
            }
            timeoutTask = task
            waiter = (count, continuation, task)
        }
        timeoutTask?.cancel()
        return parkedInTime
    }

    /// Resumes the earliest-parked `sleep()` call still waiting.
    func releaseNext() {
        guard !parked.isEmpty else {
            Issue.record("ManualSleeper.releaseNext(): nothing parked")
            return
        }
        parked.removeFirst().resume()
    }

    /// The timeout counterpart of `sleep()`'s early-return path above — see
    /// the comment there for why reading `waiter` and clearing it to `nil`
    /// here is safe against a racing `sleep()` call resuming the same
    /// continuation twice.
    private func timeoutWaiter(threshold: Int) {
        guard let waiter, waiter.threshold == threshold else { return }
        self.waiter = nil
        Issue.record("ManualSleeper: fewer than \(threshold) sleep() calls parked within 5 s — did ToastController.show() bypass the injected sleep?")
        waiter.continuation.resume(returning: false)
    }
}

@MainActor
@Suite("ToastController — behavior")
struct ToastControllerBehaviorTests {

    @Test func show_setsCurrent() {
        let controller = ToastController()
        #expect(controller.current == nil)
        let toast = Toast(style: .success, message: "Ads removed")
        controller.show(toast)
        #expect(controller.current == toast)
    }

    @Test func dismiss_clearsCurrent() {
        let controller = ToastController()
        controller.show(Toast(style: .failure, message: "Boom", duration: .seconds(60)))
        #expect(controller.current != nil)
        controller.dismiss()
        #expect(controller.current == nil)
    }

    @Test func show_replacesPreviousToast() {
        let controller = ToastController()
        controller.show(Toast(style: .success, message: "first", duration: .seconds(60)))
        controller.show(Toast(style: .failure, message: "second", duration: .seconds(60)))
        #expect(controller.current?.message == "second")
        #expect(controller.current?.style == .failure)
    }

    @Test func autoDismiss_firesAfterDuration() async throws {
        let sleeper = ManualSleeper()
        let controller = ToastController(sleep: { _ in await sleeper.sleep() })
        controller.show(Toast(style: .success, message: "pop"))
        try #require(await sleeper.waitUntilParked(1))
        #expect(controller.current != nil)
        sleeper.releaseNext()
        // Await the dismiss task itself rather than a proxy like
        // `Task.yield()` — that removes any dependence on scheduling order
        // between this test task and the dismiss task (#1087).
        await controller.dismissTask?.value
        #expect(controller.current == nil)
    }

    /// A superseded toast's dismiss `Task` is cancelled by the next
    /// `show()`, but its sleeper call is still parked. Releasing that stale
    /// sleeper after the new toast is showing must not clear the new toast.
    @Test func show_replacesPreviousToast_staleSleeperDoesNotClearNewToast() async throws {
        let sleeper = ManualSleeper()
        let controller = ToastController(sleep: { _ in await sleeper.sleep() })
        controller.show(Toast(style: .success, message: "first"))
        try #require(await sleeper.waitUntilParked(1))
        let stale = controller.dismissTask
        controller.show(Toast(style: .failure, message: "second"))
        try #require(await sleeper.waitUntilParked(2))
        sleeper.releaseNext()
        await stale?.value
        #expect(controller.current?.message == "second")
        sleeper.releaseNext()
        await controller.dismissTask?.value
        #expect(controller.current == nil)
    }
}
