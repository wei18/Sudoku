// FakeLogger — records every log invocation for assertion.
//
// LoggerProtocol.log is synchronous (see LoggerProtocol.swift rationale).
// To stay Sendable + isolated we fan out the synchronous call to an actor
// append via a Task; tests await `entries(after:)` to settle pending
// dispatches before asserting.

public import Telemetry

public actor FakeLogger: LoggerProtocol {
    public struct Entry: Sendable, Equatable, Hashable {
        public let level: LogLevel
        public let message: String
        public let privacy: LogPrivacy

        public init(level: LogLevel, message: String, privacy: LogPrivacy) {
            self.level = level
            self.message = message
            self.privacy = privacy
        }
    }

    public private(set) var entries: [Entry] = []

    public init() {}

    nonisolated public func log(level: LogLevel, message: String, privacy: LogPrivacy) {
        Task { await self.append(Entry(level: level, message: message, privacy: privacy)) }
    }

    private func append(_ entry: Entry) {
        entries.append(entry)
    }

    /// Test helper — yields the actor a few hops so any in-flight `Task {}`
    /// dispatched from `nonisolated log(...)` have a chance to land before
    /// assertions read `entries`.
    public func settle() async {
        for _ in 0..<5 {
            await Task.yield()
        }
    }
}
