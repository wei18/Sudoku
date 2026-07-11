// #750: smoke coverage for the extracted ASC-screenshot render machinery —
// the pixel/point ratios (the ASC device scale) are the one invariant a
// silent regression here would be easy to miss.

#if canImport(AppKit)
import Foundation
import Testing
@testable import GameTestSupportKit

@Suite("ASCProfile")
struct ASCProfileTests {
    @Test("iPhone 6.9\" is an exact 3x scale")
    func iPhoneScale() {
        #expect(ASCProfile.iPhone69.pixelSize.width / ASCProfile.iPhone69.pointSize.width == 3)
        #expect(ASCProfile.iPhone69.pixelSize.height / ASCProfile.iPhone69.pointSize.height == 3)
    }

    @Test("iPad 13\" and Mac are an exact 2x scale")
    func iPadAndMacScale() {
        #expect(ASCProfile.iPad13.pixelSize.width / ASCProfile.iPad13.pointSize.width == 2)
        #expect(ASCProfile.iPad13.pixelSize.height / ASCProfile.iPad13.pointSize.height == 2)
        #expect(ASCProfile.mac.pixelSize.width / ASCProfile.mac.pointSize.width == 2)
        #expect(ASCProfile.mac.pixelSize.height / ASCProfile.mac.pointSize.height == 2)
    }

    @Test("emit gate reads ASC_EMIT_SCREENSHOTS, not set in a normal test run")
    func emitGateDefaultsOff() {
        #expect(ASCScreenshotEmit.isEnabled == (ProcessInfo.processInfo.environment["ASC_EMIT_SCREENSHOTS"] != nil))
    }
}
#endif
