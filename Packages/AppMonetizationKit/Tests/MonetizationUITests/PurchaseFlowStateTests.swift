// PurchaseFlowStateTests — #881 (closing #874 F-6/F-7/F-8).
//
// `MonetizationStateController.flowState` (`PurchaseFlowState`) replaces two
// independently-guarded `Bool`s (`purchaseInFlight` / `restoreInFlight`) with
// a single closed enum. This suite pins the two properties that motivated
// the change:
//   1. A purchase in flight and a restore in flight are unrepresentable at
//      the same time — not merely guarded against (F-6).
//   2. A failed purchase leaves a state distinguishable from "never
//      attempted" until the next attempt resolves it (F-7).
//
// `flowState` is module-`internal`, so this suite lives in
// `MonetizationUITests` (`@testable import MonetizationUI`) rather than in
// SudokuKit/MinesweeperKit's app-level test targets, which only see the
// unchanged public `purchaseInFlight` / `restoreInFlight` surface.

import Foundation
import Testing

import MonetizationCore
import MonetizationTesting

@testable import MonetizationUI

/// Thrown by `PurchaseFlowStateTests.RestoreFailingIAPClient` (#894). File
/// scope, not nested inside the actor — `swiftlint --strict`'s nesting rule
/// caps types at 1 level deep inside the test `struct`.
private enum RestoreFailingIAPClientError: Error {
    case restoreFailed
}

@MainActor
@Suite("MonetizationStateController — PurchaseFlowState")
struct PurchaseFlowStateTests {

    /// An `IAPClient` whose `purchase(_:)` suspends until the test calls
    /// `release()`, so a test can observe the controller mid-flight — the
    /// stock `FakeIAPClient` returns immediately and can't be paused.
    private actor GatedIAPClient: IAPClient {
        private var purchaseContinuation: CheckedContinuation<Void, Never>?
        private var scriptedPurchaseResult: IAPPurchaseResult = .userCancelled
        private(set) var restoreCallCount = 0

        func setPurchaseResult(_ result: IAPPurchaseResult) {
            scriptedPurchaseResult = result
        }

        func release() {
            purchaseContinuation?.resume()
            purchaseContinuation = nil
        }

        func availableProducts() async throws -> [IAPProduct] { [] }

        func purchase(_ productId: String) async throws -> IAPPurchaseResult {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                purchaseContinuation = continuation
            }
            return scriptedPurchaseResult
        }

        func restorePurchases() async throws -> [IAPProduct] {
            restoreCallCount += 1
            return []
        }

        nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
            AsyncStream { _ in }
        }
    }

    private func makeStore(purchased: Bool = false) -> FakeAdGateStateStore {
        FakeAdGateStateStore(
            initial: AdGateState(
                firstLaunchAt: Date(timeIntervalSince1970: 0),
                hasPurchasedRemoveAds: purchased
            )
        )
    }

    // MARK: - F-6: mutual exclusion by construction

    @Test func purchaseInFlight_blocksRestoreFromStarting() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = GatedIAPClient()
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        let purchaseTask = Task { await controller.purchaseRemoveAds() }

        // Wait until the purchase has actually reached its in-flight state
        // (the gated client is suspended inside `purchase(_:)`).
        var iterations = 0
        while !controller.purchaseInFlight, iterations < 1000 {
            await Task.yield()
            iterations += 1
        }
        #expect(controller.purchaseInFlight == true)

        // A single stored `flowState` makes "both in flight" unrepresentable:
        // `restorePurchases()`'s guard reads the SAME enum, so it can't start
        // a restore while a purchase already owns it (#874 F-6).
        await controller.restorePurchases()
        #expect(controller.restoreInFlight == false)
        #expect(controller.purchaseInFlight == true)
        let restoreCalls = await iap.restoreCallCount
        #expect(restoreCalls == 0)

        await iap.release()
        await purchaseTask.value
        #expect(controller.purchaseInFlight == false)
    }

    @Test func restoreInFlight_blocksPurchaseFromStarting() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = FakeIAPClient()
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        // FakeIAPClient's restorePurchases() returns immediately, so drive
        // the guard check directly: start a restore and — before it can
        // suspend past the guard — assert a concurrent purchase attempt
        // observes the SAME `flowState` and refuses to start. We prove this
        // by racing the two calls with `async let` (MainActor-serial
        // scheduling processes the first-issued guard check first).
        async let restoreResult: Void = controller.restorePurchases()
        async let purchaseResult: Void = controller.purchaseRemoveAds()
        _ = await (restoreResult, purchaseResult)

        // Whichever call the MainActor scheduled first "won" the flowState;
        // the other must have been a no-op — never both in flight, and
        // never both having called through to the client.
        let purchaseCalls = await iap.purchaseCallCount
        let restoreCalls = await iap.restoreCallCount
        #expect(purchaseCalls + restoreCalls == 1)
        #expect(!(controller.purchaseInFlight && controller.restoreInFlight))
    }

    // MARK: - F-7: failed purchase is distinguishable from never-attempted

    @Test func purchaseFailure_setsDistinctFlowState() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = FakeIAPClient()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        #expect(controller.flowState == .idle)

        await controller.purchaseRemoveAds()

        // Distinct from `.idle` — RemoveAdsRow renders a "last attempt
        // failed" treatment for this case instead of looking identical to
        // never-attempted.
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))
        #expect(controller.flowState != .idle)
        #expect(controller.purchaseInFlight == false)
    }

    @Test func purchaseFailedState_clearedByNextSuccessfulPurchase() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = FakeIAPClient()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        await controller.purchaseRemoveAds()
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))

        await iap.setPurchaseResult(
            for: removeAdsProductId,
            result: .success(IAPProduct(id: removeAdsProductId, displayName: "Remove Ads", displayPrice: "$2.99", isPurchased: true))
        )
        await controller.purchaseRemoveAds()

        #expect(controller.flowState == .idle)
        #expect(controller.hasPurchasedRemoveAds == true)
    }

    @Test func purchaseFailedState_clearedByRestoreCompleting() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = FakeIAPClient()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        await controller.purchaseRemoveAds()
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))

        await controller.restorePurchases()

        // A SUCCESSFULLY completed restore resolves the flow, clearing a
        // stale failed-purchase state — the entitlement question is settled.
        #expect(controller.flowState == .idle)
    }

    // MARK: - #894: restore-failure / revoked-event lifecycle nits

    /// `restorePurchases()` that always throws, to distinguish "restore
    /// completed" (clears `.purchaseFailed`) from "restore attempted and
    /// itself failed" (must NOT clear a prior `.purchaseFailed` — #894).
    private actor RestoreFailingIAPClient: IAPClient {
        private var scriptedPurchaseResult: IAPPurchaseResult = .userCancelled
        private(set) var restoreCallCount = 0

        func setPurchaseResult(_ result: IAPPurchaseResult) {
            scriptedPurchaseResult = result
        }

        func availableProducts() async throws -> [IAPProduct] { [] }

        func purchase(_ productId: String) async throws -> IAPPurchaseResult {
            scriptedPurchaseResult
        }

        func restorePurchases() async throws -> [IAPProduct] {
            restoreCallCount += 1
            throw RestoreFailingIAPClientError.restoreFailed
        }

        nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
            AsyncStream { _ in }
        }
    }

    @Test func purchaseFailedState_persistsThroughFailedRestore() async {
        let store = makeStore()
        let gate = AdGate(store: store)
        let iap = RestoreFailingIAPClient()
        await iap.setPurchaseResult(.failed(reason: "card declined"))
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        await controller.purchaseRemoveAds()
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))

        await controller.restorePurchases()

        // #894: a restore that itself fails doesn't resolve the entitlement
        // question, so the earlier failed-purchase indicator must survive —
        // not be silently dropped to `.idle`.
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))
        let restoreCalls = await iap.restoreCallCount
        #expect(restoreCalls == 1)
    }

    /// Wait up to `timeout` for `predicate` to become true. Yields the main
    /// loop between checks so the controller's update-subscriber Task can
    /// process the emitted event (mirrors
    /// `MonetizationStateControllerUpdatesTests.waitFor` in SudokuUITests,
    /// duplicated here because `flowState` is only visible via
    /// `@testable import MonetizationUI`, which that target doesn't use).
    private func waitFor(
        timeout: Duration = .milliseconds(500),
        _ predicate: @MainActor () -> Bool
    ) async {
        let start = ContinuousClock.now
        while ContinuousClock.now - start < timeout {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
    }

    @Test func revokedEvent_clearsStalePurchaseFailedState() async {
        let store = makeStore(purchased: true)
        let gate = AdGate(store: store)
        let iap = FakeIAPClient()
        await iap.setPurchaseResult(for: removeAdsProductId, result: .failed(reason: "card declined"))
        let controller = MonetizationStateController(iapClient: iap, stateStore: store, adGate: gate)

        // Leave a stale failure behind from an unrelated earlier attempt.
        await controller.purchaseRemoveAds()
        #expect(controller.flowState == .purchaseFailed(reason: "card declined"))

        controller.startListeningForLifetimeOfApp()
        defer { Task { await iap.finishUpdates() } }

        await iap.emit(.revoked(productId: removeAdsProductId))

        // #894: a `.revoked` event settles the entitlement question
        // out-of-band — RemoveAdsRow should read fresh, not blame the old
        // failure.
        await waitFor { controller.flowState == .idle }
        #expect(controller.flowState == .idle)
    }
}
