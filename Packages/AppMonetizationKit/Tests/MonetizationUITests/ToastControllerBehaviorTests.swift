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
    private var waiter: (threshold: Int, continuation: CheckedContinuation<Void, Never>)?

    /// Parks until `releaseNext()` resumes it. Deliberately does not respond
    /// to task cancellation — a `show()` that supersedes a toast cancels the
    /// owning dismiss `Task`, but this sleeper still only resumes on an
    /// explicit `releaseNext()`. That's the point: it lets
    /// `show_replacesPreviousToast_staleSleeperDoesNotClearNewToast` prove
    /// the `Task.isCancelled` guard in `ToastController.show()` — not any
    /// cooperation from the sleep seam — is what stops a stale, later
    /// released sleeper from clearing a newer toast.
    func sleep() async {
        await withCheckedContinuation { continuation in
            parked.append(continuation)
            parkedCount += 1
            if let waiter, parkedCount >= waiter.threshold {
                self.waiter = nil
                waiter.continuation.resume()
            }
        }
    }

    /// Suspends until at least `count` calls to `sleep()` have parked.
    func waitUntilParked(_ count: Int) async {
        if parkedCount >= count { return }
        await withCheckedContinuation { continuation in
            waiter = (count, continuation)
        }
    }

    /// Resumes the earliest-parked `sleep()` call still waiting.
    func releaseNext() {
        guard !parked.isEmpty else { return }
        parked.removeFirst().resume()
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

    @Test func autoDismiss_firesAfterDuration() async {
        let sleeper = ManualSleeper()
        let controller = ToastController(sleep: { @MainActor _ in await sleeper.sleep() })
        controller.show(Toast(style: .success, message: "pop"))
        await sleeper.waitUntilParked(1)
        #expect(controller.current != nil)
        sleeper.releaseNext()
        await settle()
        #expect(controller.current == nil)
    }

    /// A superseded toast's dismiss `Task` is cancelled by the next
    /// `show()`, but its sleeper call is still parked. Releasing that stale
    /// sleeper after the new toast is showing must not clear the new toast.
    @Test func show_replacesPreviousToast_staleSleeperDoesNotClearNewToast() async {
        let sleeper = ManualSleeper()
        let controller = ToastController(sleep: { @MainActor _ in await sleeper.sleep() })
        controller.show(Toast(style: .success, message: "first"))
        await sleeper.waitUntilParked(1)
        controller.show(Toast(style: .failure, message: "second"))
        await sleeper.waitUntilParked(2)
        sleeper.releaseNext()
        await settle()
        #expect(controller.current?.message == "second")
        sleeper.releaseNext()
        await settle()
        #expect(controller.current == nil)
    }

    /// The MainActor runs jobs as a FIFO serial queue: yielding here lets
    /// the dismiss job enqueued by a just-released `sleep()` continuation
    /// run to completion before assertions — no polling, no deadline.
    private func settle() async {
        await Task.yield()
    }
}
