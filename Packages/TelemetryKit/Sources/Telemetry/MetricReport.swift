// MetricReport — decoupled MetricKit payload envelope.
//
// MetricKit types (`MXMetricPayload`, `MXDiagnosticPayload`) are not Sendable
// and live behind `import MetricKit` which is unavailable on all platforms
// in test contexts. To keep `TelemetryEvent` portable and freely encodable
// we project payloads to their JSON serialization plus a kind discriminator.
//
// The conversion happens at the `MetricKitSink` boundary (see MetricKitSink.swift).

public import Foundation

public struct MetricReport: Sendable, Equatable, Hashable, Codable {
    public enum Kind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
        case daily   // MXMetricPayload (regular daily report)
        case crash   // MXCrashDiagnostic
        case hang    // MXHangDiagnostic
    }

    public let kind: Kind
    public let payloadJSON: String
    public let receivedAt: Date

    public init(kind: Kind, payloadJSON: String, receivedAt: Date) {
        self.kind = kind
        self.payloadJSON = payloadJSON
        self.receivedAt = receivedAt
    }
}
