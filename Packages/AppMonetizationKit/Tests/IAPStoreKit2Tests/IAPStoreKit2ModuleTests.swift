// swiftlint:disable redundant_discardable_let

import Testing
@testable import IAPStoreKit2

// Module-presence test. Real coverage arrives in Phase v2.1 alongside
// `LiveStoreKit2IAPClient`. Intentionally left minimal until v2.1.1.

@Suite("IAPStoreKit2 — module presence")
struct IAPStoreKit2ModuleTests {
    @Test func moduleLinks() {
        let _ = IAPStoreKit2.ModuleAnchor.self
    }
}
