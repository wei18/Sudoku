import Testing
@testable import Telemetry

@Suite("Telemetry smoke")
struct TelemetrySmokeTests {
    @Test func packageCompiles() {
        _moduleAnchor()
    }
}
