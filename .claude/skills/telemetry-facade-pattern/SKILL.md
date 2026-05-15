---
name: telemetry-facade-pattern
description: Single `Telemetry` SwiftPM target with a fan-out facade — callers say "what happened" (`telemetry.observe(event)`), facade dispatches to multiple sinks (OSLog / NoOp tracking / MetricKit / Game Center). Invoke when starting a new project that will log + track, deciding logger / tracker coupling, designing telemetry interfaces, or when asked "should Logger and Tracking be one thing".
---

# Telemetry Facade Pattern

## When to invoke

- Starting a new project and designing the logger / tracker / metrics interface.
- About to introduce OSLog and any tracking / analytics at the same time.
- Wanting to preserve flexibility for "swap the tracking provider later".
- User asks "should Logger and Tracking be separate", "how should the event interface look".

## Default decisions

### A single `Telemetry` target

- Create one `Telemetry` target inside the SwiftPM Package.
- It contains:
  - `TelemetryEvent` value type (enum / struct, `Sendable`)
  - `TelemetrySink` protocol
  - The main facade — default to a `Telemetry` **actor**. Sink stateful subscriptions (e.g. `MetricKitSink` holding `MXMetricManagerSubscriber` reference identity) require an actor for clean lifecycle management. A `Sendable` struct facade is acceptable only when every sink is fully synchronous and stateless. The facade fans out to multiple sinks.
  - Default sinks (see below)

### Call sites describe only "what happened"

```swift
telemetry.observe(.puzzleCompleted(id: puzzleId, durationMs: 12_345))
```

- The call site **doesn't know** who will consume the event.
- Swapping providers / adding sinks only requires replacing a sink; call sites change nothing.

### Default sink set

| Sink | Receives | Purpose |
|---|---|---|
| `OSLogSink` | All events | Human-readable debug messages |
| `TrackingSink` (default `NoOpTrackingSink`) | Business events | v1 has no third-party tracking but the protocol is reserved; future swaps require zero call-site changes |
| `MetricKitSink` | Subscribes via `MXMetricManager.shared.add(self)`; on receiving `MXMetricPayload`, broadcasts to other sinks | Performance / diagnostics persistence |
| `GameCenterSink` (games) | Completion / achievement events | Submit score / unlock achievement |

```swift
public struct NoOpTrackingSink: TelemetrySink {
    public init() {}
    public func receive(_ event: TelemetryEvent) { /* intentionally empty */ }
}
```

### Composition root wiring

- The App target's DI composition root injects sinks into the facade.
- Sinks are **independent**; one sink's failure does not affect the others.

## Rationale

- Decouples call sites from consumers: v1 can use `telemetry.observe(...)` with no external tracking, and a future TelemetryDeck / in-house pipeline only swaps the sink.
- OSLog + Tracking + MetricKit + GameCenter are all "event streams"; one unified interface is easier to maintain than four separate ones.
- Easy to test: inject a fake sink and assert on the event stream.

## Deviation considerations

- **Minimal App, OSLog only**: you can skip the `Telemetry` target and use `Logger` directly. But **if you anticipate adding tracking / metrics later**, building the facade up front pays off.
- **Need inter-sink dependencies** (e.g. `MetricKitSink` payloads must go through `TrackingSink` first): handle routing inside the facade; call sites still unchanged.
- **Cross-platform** (Android / Linux): facade interface stays platform-neutral; sink implementations are per-platform.

## Verification checklist

- The `Telemetry` target is standalone; UI / Engine don't directly depend on anything beyond OSLog.
- `TelemetryEvent` is a value type, `Sendable`.
- A default `NoOpTrackingSink` is provided and wired in the composition root.
- Tests assert on event streams via fake sinks, not by parsing OSLog output.

## Related skills

- `oslog-logger-defaults`: the concrete `OSLogSink` implementation dependency.
- `apple-three-piece-analytics`: each piece corresponds to one sink.
- `swiftpm-modularization`: why `Telemetry` is its own target.
