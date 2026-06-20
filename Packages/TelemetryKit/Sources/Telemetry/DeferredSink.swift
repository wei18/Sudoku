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

import Foundation

public final class DeferredSink: TelemetrySink, @unchecked Sendable {
    private let lock = NSLock()
    private var downstream: [any TelemetrySink] = []

    public init() {}

    /// Bind the real downstream sinks. Called exactly once, synchronously from
    /// the @MainActor composition root after all deps are assembled.
    public func setDownstream(_ sinks: [any TelemetrySink]) {
        lock.withLock { downstream = sinks }
    }

    /// Forward the event to every downstream sink sequentially.
    /// If called before `setDownstream`, the array is empty — safe no-op.
    /// `withLock` snapshots the array before any `await`; no lock is held
    /// across suspension points (Swift 6 requirement).
    public func receive(_ event: TelemetryEvent) async {
        let sinks = lock.withLock { downstream }
        for sink in sinks {
            await sink.receive(event)
        }
    }
}
