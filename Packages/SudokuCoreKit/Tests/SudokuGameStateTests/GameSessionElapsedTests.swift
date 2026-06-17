import Foundation
import SudokuEngine
import Testing
 import SudokuGameState

@Suite("GameSession elapsedSeconds (clock-injected)")
struct GameSessionElapsedTests {

    @Test("start() at t=0 → elapsed == 0")
    func startAtZero() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        let elapsed = await session.elapsedSeconds
        #expect(elapsed == 0)
    }

    @Test("playing accumulates as the clock advances")
    func playingAccumulates() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(30)
        let elapsed = await session.elapsedSeconds
        #expect(elapsed == 30)
    }

    @Test("pause() freezes the clock — subsequent advance is ignored")
    func pauseFreezes() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(30)
        try await session.pause()
        clock.set(60)
        let elapsed = await session.elapsedSeconds
        #expect(elapsed == 30)
    }

    @Test("resume() continues accumulation from the prior total")
    func resumeAccumulates() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(30)
        try await session.pause()
        clock.set(60)
        try await session.resume()
        clock.set(90)
        let elapsed = await session.elapsedSeconds
        #expect(elapsed == 60, "30 before pause + 30 after resume")
    }

    @Test("complete() freezes the clock")
    func completeFreezes() async throws {
        let clock = FakeMonotonicClock()
        let session = GameSession(puzzle: TestPuzzles.simple, clock: clock)
        try await session.start()
        clock.set(45)
        try await session.complete()
        clock.set(120)
        let elapsed = await session.elapsedSeconds
        #expect(elapsed == 45)
    }
}

/// Test-only deterministic clock. Reads/writes are lock-protected so
/// `now` can be `nonisolated` to satisfy `MonotonicClock.now`.
final class FakeMonotonicClock: MonotonicClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value: TimeInterval = 0

    init(start: TimeInterval = 0) {
        self.value = start
    }

    var now: TimeInterval {
        lock.withLock { value }
    }

    func set(_ seconds: TimeInterval) {
        lock.withLock { value = seconds }
    }
}
