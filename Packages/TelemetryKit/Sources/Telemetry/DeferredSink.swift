// DeferredSink — late-binding TelemetrySink that breaks the composition-time
// dependency cycle between Telemetry (built first) and sinks that need deps
// (e.g. GameCenterSink needs persistence + gameCenter which need Telemetry).
//
// Pattern mirrors LiveMetricKitRetainer.install: Telemetry is wired once at
// startup with a DeferredSink in its list; after all deps are assembled,
// `setDownstream` binds the real sink(s) in one sync call.
//
// Thread-safety: `setDownstream` is called exactly once from @MainActor
// composition (sync), then `receive` is called from the `Telemetry` actor.
// NSLock guards the array read/write without crossing an await boundary.
// `final class @unchecked Sendable` (not an actor) so `setDownstream` stays
// synchronous from the @MainActor composition root (`makeGameAppCore` is sync).
//
// Non-blocking forwarding (#579): the downstream completion sinks (GameCenterSink)
// do CloudKit reads (AchievementEvaluator) + GameKit network I/O, and `receive`
// is reached from the gameplay completion path (placeDigit → GameSession
// .sessionCompleted → Telemetry.observe). So `receive` does NOT await the
// downstream — it spawns a detached forwarding Task and returns immediately,
// never freezing the board on that work. Ordering across events is preserved by
// chaining each task on the previous one (so two completions still forward in
// order); the fast sinks (OSLog / NoOp) stay synchronous in `Telemetry.observe`
// — only this deferred branch is detached.

import Foundation

public final class DeferredSink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var downstream: [any TelemetrySink] = []
    /// Latest forwarding task. Each new task awaits this one first (ordering),
    /// so awaiting the latest drains the whole chain. Production never reads it
    /// (detached Tasks run to completion on their own); it exists only so tests
    /// can await quiescence deterministically via `awaitForwardingForTesting`.
    private var inFlight: Task<Void, Never>?

    public init() {}

    /// Bind the real downstream sinks. Called exactly once, synchronously from
    /// the @MainActor composition root after all deps are assembled.
    public func setDownstream(_ sinks: [any TelemetrySink]) {
        lock.withLock { downstream = sinks }
    }

    /// Forward the event to every downstream sink WITHOUT blocking the caller.
    /// If called before `setDownstream`, the array is empty — safe no-op.
    /// `withLock` snapshots state before any `await`; no lock crosses a
    /// suspension point (Swift 6 requirement).
    public func receive(_ event: TelemetryEvent) async {
        let (sinks, previous) = lock.withLock { (downstream, inFlight) }
        guard !sinks.isEmpty else { return }
        let task = Task {
            // Preserve cross-event order: forward only after the prior event's
            // forwarding completes. The caller does not await this task.
            await previous?.value
            for sink in sinks {
                await sink.receive(event)
            }
        }
        lock.withLock { inFlight = task }
    }

    /// Test-only quiescence: await the most recent forwarding task (which chains
    /// back through all prior ones). Production code never calls this.
    func awaitForwardingForTesting() async {
        let task = lock.withLock { inFlight }
        await task?.value
    }
}
