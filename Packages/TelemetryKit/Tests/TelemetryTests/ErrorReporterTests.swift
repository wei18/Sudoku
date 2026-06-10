// ErrorReporterTests — M10 (issue #67).
//
// Acceptance criterion from the issue: "New tests assert that a thrown
// CloudKit error surfaces a telemetry event." Validated by injecting a
// `RecordingSink` into the `Telemetry` actor that backs `LiveErrorReporter`
// and asserting the `.errorOccurred(...)` event lands.
//
// Also covers:
//   - UserFacingError.classify maps CKError-domain codes correctly
//   - FakeErrorReporter records reports for VM-level tests

import Foundation
import Testing
import TelemetryTesting
@testable import Telemetry

@Suite("ErrorReporter — funnel + classify (M10 / issue #67)")
struct ErrorReporterTests {

    /// A plain NSError modeling a CloudKit `notAuthenticated` (code 9 in
    /// the `CKErrorDomain`). Tests construct this directly instead of
    /// importing CloudKit so the test target stays cross-platform.
    private func cloudKitNotAuthenticated() -> NSError {
        NSError(
            domain: "CKErrorDomain",
            code: 9,
            userInfo: [NSLocalizedDescriptionKey: "iCloud account signed out"]
        )
    }

    @Test
    func classifierMapsCKNotAuthenticatedToICloudSignedOut() {
        let error = cloudKitNotAuthenticated()
        #expect(UserFacingError.classify(error) == .iCloudSignedOut)
    }

    @Test
    func classifierMapsURLErrorToNetworkUnavailable() {
        let error = NSError(domain: NSURLErrorDomain, code: -1009)
        #expect(UserFacingError.classify(error) == .networkUnavailable)
    }

    @Test
    func classifierFallsBackToUnknownForUnrecognisedDomain() {
        let error = NSError(domain: "Some.Custom.Domain", code: 42)
        #expect(UserFacingError.classify(error) == .unknown)
    }

    @Test
    func liveReporterFansThrownCloudKitErrorIntoTelemetryEvent() async {
        // Wire a recording sink into the Telemetry facade so we can observe
        // the fan-out without parsing OSLog.
        let recorder = RecordingSink()
        let telemetry = Telemetry(sinks: [recorder])
        let reporter = LiveErrorReporter(telemetry: telemetry)

        let thrown = cloudKitNotAuthenticated()
        await reporter.report(
            UserFacingError.classify(thrown),
            underlying: thrown,
            source: "Test.cloudKitFlow"
        )

        let events = await recorder.received
        #expect(events.count == 1)
        // The recorded TelemetryEvent must be `.errorOccurred` with our
        // bucket's rawCode + source. We don't pin the full message string
        // (it includes the NSError description, which is platform-flavoured).
        guard case let .errorOccurred(source, code, _) = events[0] else {
            Issue.record("Expected .errorOccurred, got \(events[0])")
            return
        }
        #expect(source == "Test.cloudKitFlow")
        #expect(code == UserFacingError.iCloudSignedOut.rawCode)
    }

    @Test
    func fakeReporterRecordsEveryReport() async {
        let fake = FakeErrorReporter()
        let thrown = NSError(domain: NSURLErrorDomain, code: -1009)

        await fake.report(
            .networkUnavailable,
            underlying: thrown,
            source: "VMTest.bootstrap"
        )

        let received = await fake.received
        #expect(received.count == 1)
        #expect(received[0].error == .networkUnavailable)
        #expect(received[0].source == "VMTest.bootstrap")
    }
}
