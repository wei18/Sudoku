import SudokuEngine
import Testing
@testable import Telemetry
import SudokuKitTesting

@Suite("OSLogSink — privacy + level mapping")
struct OSLogSinkTests {

    @Test func gameplayEventsAreDebugLevel() async {
        let logger = FakeLogger()
        let sink = OSLogSink(logger: logger)

        await sink.receive(.digitPlaced(row: 4, col: 5, digit: 6, previous: nil))
        await sink.receive(.noteToggled(row: 0, col: 0, digit: 1, added: true))
        await sink.receive(.moveUndone)
        await sink.receive(.moveRedone)

        await logger.settle()
        let entries = await logger.entries
        #expect(entries.count == 4)
        #expect(entries.allSatisfy { $0.level == .debug })
        #expect(entries.allSatisfy { $0.privacy == .privateValue })
    }

    @Test func gameplayPayloadIsPrivateByDefault() async {
        let logger = FakeLogger()
        let sink = OSLogSink(logger: logger)
        await sink.receive(.digitPlaced(row: 4, col: 5, digit: 6, previous: 2))

        await logger.settle()
        let entries = await logger.entries
        #expect(entries.count == 1)
        #expect(entries[0].privacy == .privateValue)
        // Sanity: the message still carries the raw values (FakeLogger sees
        // them; the .private flag only affects how os.Logger renders them
        // in Console.app / sysdiagnose).
        #expect(entries[0].message.contains("r=4"))
        #expect(entries[0].message.contains("d=6"))
    }

    @Test func sessionStartedEmitsPublicWithPuzzleId() async {
        let logger = FakeLogger()
        let sink = OSLogSink(logger: logger)

        await sink.receive(.sessionStarted(puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy))

        await logger.settle()
        let entries = await logger.entries
        #expect(entries.count == 1)
        #expect(entries[0].level == .info)
        #expect(entries[0].privacy == .publicValue)
        #expect(entries[0].message.contains("2026-05-19-easy"))
    }

    @Test func puzzleCompletedIsNoticeAndPublic() async {
        let logger = FakeLogger()
        let sink = OSLogSink(logger: logger)

        await sink.receive(.puzzleCompleted(
            puzzleId: "2026-05-19-hard",
            mode: .daily,
            difficulty: .hard,
            elapsedSeconds: 444
        ))

        await logger.settle()
        let entries = await logger.entries
        #expect(entries.count == 1)
        #expect(entries[0].level == .notice)
        #expect(entries[0].privacy == .publicValue)
        #expect(entries[0].message.contains("2026-05-19-hard"))
        #expect(entries[0].message.contains("elapsed=444"))
    }

    @Test func errorOccurredIsErrorLevelAndPrivateMessage() async {
        let logger = FakeLogger()
        let sink = OSLogSink(logger: logger)

        await sink.receive(.errorOccurred(source: "Persistence", code: "lww.conflict", message: "free text"))

        await logger.settle()
        let entries = await logger.entries
        #expect(entries.count == 1)
        #expect(entries[0].level == .error)
        // Whole message marked private — see OSLogSink.swift rationale on
        // single-field privacy granularity.
        #expect(entries[0].privacy == .privateValue)
        #expect(entries[0].message.contains("source=Persistence"))
        #expect(entries[0].message.contains("code=lww.conflict"))
    }

    @Test func liveInitDoesNotCrash() {
        // Smoke — exercising the convenience init path that wires
        // OSLoggerAdapter. We can't introspect os.Logger from tests, so
        // the assertion is "constructible + receive doesn't trap".
        let sink = OSLogSink(subsystem: "com.wei18.sudoku", category: "TelemetryTests")
        Task { await sink.receive(.moveUndone) }
    }
}
