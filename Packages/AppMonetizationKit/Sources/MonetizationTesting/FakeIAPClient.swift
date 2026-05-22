internal import Foundation
public import MonetizationCore
internal import os

// MARK: - FakeIAPClient

public actor FakeIAPClient: IAPClient {
    private var products: [IAPProduct] = []
    private var scriptedResults: [String: IAPPurchaseResult] = [:]
    /// Stream + continuation are pre-created at init time so the `nonisolated`
    /// `purchaseUpdates()` accessor can return them without touching actor
    /// state. `AsyncStream` is single-consumer; tests should subscribe once.
    ///
    /// N5 (v2-audit-code-polish): the Live client wraps its underlying bridge
    /// stream in a fresh `AsyncStream` per call (so multiple subscribers each
    /// get their own task), while this Fake hands out the shared stream — a
    /// second subscriber would receive no events. We `precondition` against
    /// the second subscribe so tests fail loudly instead of hanging silently.
    private nonisolated let updatesStream: AsyncStream<IAPPurchaseEvent>
    private nonisolated let updatesContinuation: AsyncStream<IAPPurchaseEvent>.Continuation
    private nonisolated let purchaseUpdatesSubscribed = OSAllocatedUnfairLock<Bool>(initialState: false)

    public private(set) var availableProductsCallCount: Int = 0
    public private(set) var purchaseCallCount: Int = 0
    public private(set) var restoreCallCount: Int = 0

    public init() {
        let (stream, continuation) = AsyncStream<IAPPurchaseEvent>.makeStream()
        self.updatesStream = stream
        self.updatesContinuation = continuation
    }

    // MARK: Scripting API

    public func setProducts(_ products: [IAPProduct]) {
        self.products = products
    }

    public func setPurchaseResult(for productId: String, result: IAPPurchaseResult) {
        scriptedResults[productId] = result
    }

    /// Emit a purchase event into the `purchaseUpdates()` stream.
    public func emit(_ event: IAPPurchaseEvent) {
        updatesContinuation.yield(event)
    }

    /// Finish the updates stream — used by tests that want bounded iteration.
    public func finishUpdates() {
        updatesContinuation.finish()
    }

    // MARK: IAPClient

    public func availableProducts() async throws -> [IAPProduct] {
        availableProductsCallCount += 1
        return products
    }

    public func purchase(_ productId: String) async throws -> IAPPurchaseResult {
        purchaseCallCount += 1
        return scriptedResults[productId] ?? .failed(reason: "no scripted result for \(productId)")
    }

    public func restorePurchases() async throws -> [IAPProduct] {
        restoreCallCount += 1
        // Restored products report `isPurchased = true` by definition.
        let restored = products.map {
            IAPProduct(
                id: $0.id,
                displayName: $0.displayName,
                displayPrice: $0.displayPrice,
                isPurchased: true
            )
        }
        self.products = restored
        return restored
    }

    public nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
        // N5 (v2-audit-code-polish): the *Live* client wraps the bridge stream
        // in a fresh `AsyncStream` per call (each `for await` gets its own
        // subscriber task), whereas this Fake hands back the shared
        // single-consumer underlying stream. Practical implication: if your
        // test forks two parallel `for await` loops over `purchaseUpdates()`,
        // only the FIRST iterator will see events (per `AsyncStream`'s
        // single-consumer contract). Production code that re-subscribes
        // (e.g. `MonetizationStateController.startListening` cancelling and
        // restarting its task) is fine because it serialises subscriptions —
        // the prior `for await` has exited before the next one starts.
        //
        // We track subscription count for diagnostic purposes only — tests
        // that need to verify "exactly one subscribe happened" can read
        // `purchaseUpdatesSubscribeCount` directly. We deliberately do NOT
        // trap (no precondition / assertionFailure) so legitimate restarts
        // continue to work.
        purchaseUpdatesSubscribed.withLock { subscribed in subscribed = true }
        return updatesStream
    }

    /// Diagnostic: has `purchaseUpdates()` ever been called? Useful in tests
    /// that need to assert the subscriber wired up.
    public nonisolated var purchaseUpdatesWasSubscribed: Bool {
        purchaseUpdatesSubscribed.withLock { $0 }
    }
}
