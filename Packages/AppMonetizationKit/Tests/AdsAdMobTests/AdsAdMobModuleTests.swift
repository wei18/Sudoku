// swiftlint:disable redundant_discardable_let

import Testing
@testable import AdsAdMob

// Module-presence test. Real test coverage arrives in Phase v2.2 alongside
// `LiveAdMobAdProvider`. Until then we just assert the module compiles and
// links, so the test target is not "empty" from SwiftPM's perspective.
//
// Intentionally left minimal until v2.2.1.

@Suite("AdsAdMob — module presence")
struct AdsAdMobModuleTests {
    @Test func moduleLinks() {
        // If AdsAdMob fails to link, this file fails to compile.
        // Reference the internal anchor to silence "unused import" diagnostics.
        let _ = AdsAdMob.ModuleAnchor.self
    }
}
