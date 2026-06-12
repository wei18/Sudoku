import Foundation
import SudokuEngine
import Testing
@testable import Telemetry

// Compile-time helper — if any TelemetryEvent case ceased to be Sendable
// this generic constraint would refuse to compile.
private func assertSendable<T: Sendable>(_ value: T) {}

@Suite("TelemetryEvent — surface")
struct TelemetryEventTests {

    @Test func allCasesSendable() {
        let metric = MetricReport(
            kind: .daily,
            payloadJSON: "{}",
            receivedAt: Date(timeIntervalSince1970: 0)
        )
        let cases: [TelemetryEvent] = [
            .digitPlaced(row: 0, col: 0, digit: 1, previous: nil),
            .noteToggled(row: 1, col: 2, digit: 3, added: true),
            .moveUndone,
            .moveRedone,
            .sessionStarted(puzzleId: "p", mode: .daily, difficulty: .easy),
            .sessionPaused,
            .sessionResumed,
            .puzzleCompleted(puzzleId: "p", mode: .daily, difficulty: .easy, elapsedSeconds: 60, mistakeCount: 0),
            .sessionAbandoned(puzzleId: "p", mode: .practice, difficulty: .hard, elapsedSeconds: 12),
            .errorOccurred(source: "Persistence", code: "lww.conflict", message: "x"),
            .metricKitReport(metric),
            .reminderPrimerShown(kind: "dailyReady"),
            .reminderPrimerAccepted(kind: "dailyReady"),
            .reminderPrimerDeclined(kind: "dailyReady"),
            .reminderScheduled(kind: "dailyReady"),
            .reminderFired(kind: "dailyReady"),
            .reminderOpenedApp(kind: "dailyReady")
        ]
        for event in cases { assertSendable(event) }
    }

    @Test func equatablePerCase() {
        #expect(TelemetryEvent.moveUndone == .moveUndone)
        #expect(TelemetryEvent.moveUndone != .moveRedone)
        #expect(
            TelemetryEvent.digitPlaced(row: 0, col: 0, digit: 1, previous: nil)
                == .digitPlaced(row: 0, col: 0, digit: 1, previous: nil)
        )
        #expect(
            TelemetryEvent.digitPlaced(row: 0, col: 0, digit: 1, previous: nil)
                != .digitPlaced(row: 0, col: 0, digit: 2, previous: nil)
        )
        #expect(
            TelemetryEvent.puzzleCompleted(puzzleId: "a", mode: .daily, difficulty: .easy, elapsedSeconds: 60, mistakeCount: 0)
                != .puzzleCompleted(puzzleId: "a", mode: .daily, difficulty: .easy, elapsedSeconds: 61, mistakeCount: 0)
        )
    }

    @Test func codableRoundTrip() throws {
        let metric = MetricReport(
            kind: .crash,
            payloadJSON: "{\"k\":1}",
            receivedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let originals: [TelemetryEvent] = [
            .digitPlaced(row: 8, col: 7, digit: 9, previous: 3),
            .noteToggled(row: 0, col: 0, digit: 5, added: false),
            .moveUndone,
            .moveRedone,
            .sessionStarted(puzzleId: "2026-05-19-easy", mode: .daily, difficulty: .easy),
            .sessionPaused,
            .sessionResumed,
            .puzzleCompleted(puzzleId: "p-1", mode: .practice, difficulty: .medium, elapsedSeconds: 333, mistakeCount: 1),
            .sessionAbandoned(puzzleId: "p-2", mode: .daily, difficulty: .hard, elapsedSeconds: 10),
            .errorOccurred(source: "GameCenter", code: "auth.cancelled", message: "user cancelled"),
            .metricKitReport(metric),
            .reminderPrimerShown(kind: "dailyReady"),
            .reminderPrimerAccepted(kind: "dailyReady"),
            .reminderPrimerDeclined(kind: "dailyReady"),
            .reminderScheduled(kind: "dailyReady"),
            .reminderFired(kind: "dailyReady"),
            .reminderOpenedApp(kind: "dailyReady")
        ]
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for original in originals {
            let data = try encoder.encode(original)
            let decoded = try decoder.decode(TelemetryEvent.self, from: data)
            #expect(decoded == original)
        }
    }

    @Test func metricReportRoundTrip() throws {
        let report = MetricReport(kind: .hang, payloadJSON: "{\"hang\":true}", receivedAt: Date(timeIntervalSince1970: 42))
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(MetricReport.self, from: data)
        #expect(decoded == report)
    }
}
