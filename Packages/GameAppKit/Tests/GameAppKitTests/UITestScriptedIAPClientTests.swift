// UITestScriptedIAPClientTests — #935 batch 5 N22 fake contract.
//
// The whole fake is `#if DEBUG` (defined in UITestFakeSeams.swift), so this
// suite is too. Confirms the one behavior the N22 E2E flow actually depends
// on — successive `purchase()` calls walk the script in order (cancel → fail
// → pending) — plus the "script exhausted" tail keeps repeating the last
// result rather than crashing a stray extra tap.

#if DEBUG

import Testing
import MonetizationCore
@testable import GameAppKit

@Suite("UITestScriptedIAPClient (#935 batch 5)")
struct UITestScriptedIAPClientTests {

    @Test func defaultScriptWalksCancelThenFailThenPendingInOrder() async throws {
        let fake = UITestScriptedIAPClient()

        let first = try await fake.purchase("any.product")
        #expect(first == .userCancelled)

        let second = try await fake.purchase("any.product")
        guard case .failed = second else {
            Issue.record("expected .failed, got \(second)")
            return
        }

        let third = try await fake.purchase("any.product")
        #expect(third == .pending)
    }

    @Test func repeatsTheLastScriptedResultOnceExhausted() async throws {
        let fake = UITestScriptedIAPClient(script: [.userCancelled, .pending])

        _ = try await fake.purchase("any.product")
        let second = try await fake.purchase("any.product")
        let third = try await fake.purchase("any.product")

        #expect(second == .pending)
        #expect(third == .pending)
    }

    @Test func availableProductsAndRestorePurchasesReturnEmpty() async throws {
        let fake = UITestScriptedIAPClient()
        let products = try await fake.availableProducts()
        let restored = try await fake.restorePurchases()
        #expect(products.isEmpty)
        #expect(restored.isEmpty)
    }

    @Test func purchaseUpdatesFinishesImmediately() async {
        let fake = UITestScriptedIAPClient()
        var sawValue = false
        for await _ in fake.purchaseUpdates() {
            sawValue = true
        }
        #expect(sawValue == false)
    }
}

#endif
