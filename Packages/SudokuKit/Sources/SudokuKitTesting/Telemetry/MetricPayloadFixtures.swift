// MetricPayloadFixtures — canned JSON payloads for MetricKit tests.
//
// MetricKit only delivers MXMetricPayload / MXDiagnosticPayload in real
// app contexts on iOS devices; unit tests on a macOS host cannot exercise
// the subscriber path. We therefore ship a couple of synthetic JSON
// fixtures shaped like Apple's documented schema and feed them directly
// through `MetricKitSink.ingest(kind:payloadJSON:)`.
//
// These are NOT bit-identical to a real device-emitted payload — they
// are shape-compatible enough to round-trip through the JSON envelope.

public enum MetricPayloadFixtures {

    /// Minimal MXMetricPayload-shaped fixture (daily aggregate).
    public static let dailyMetric: String = """
    {
      "appVersion": "1.0.0",
      "timeStampBegin": "2026-05-18T00:00:00Z",
      "timeStampEnd": "2026-05-19T00:00:00Z",
      "metaData": {
        "appBuildVersion": "1",
        "osVersion": "iOS 26.0",
        "regionFormat": "US",
        "deviceType": "iPhone16,2"
      },
      "applicationLaunchMetrics": {
        "histogrammedTimeToFirstDrawKey": []
      }
    }
    """

    /// Minimal MXDiagnosticPayload-shaped fixture with a crash diagnostic.
    public static let crashDiagnostic: String = """
    {
      "timeStampBegin": "2026-05-19T09:00:00Z",
      "timeStampEnd":   "2026-05-19T09:05:00Z",
      "crashDiagnostics": [
        {
          "exceptionType": 1,
          "signal": 11,
          "terminationReason": "Signal 11",
          "virtualMemoryRegionInfo": "n/a"
        }
      ]
    }
    """

    /// Minimal MXDiagnosticPayload-shaped fixture with a hang diagnostic.
    public static let hangDiagnostic: String = """
    {
      "timeStampBegin": "2026-05-19T09:00:00Z",
      "timeStampEnd":   "2026-05-19T09:05:00Z",
      "hangDiagnostics": [
        { "hangDuration": "5s" }
      ]
    }
    """
}
