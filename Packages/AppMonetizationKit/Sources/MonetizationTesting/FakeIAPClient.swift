internal import Foundation
public import MonetizationCore
internal import os

// MARK: - FakeIAPClient

public actor FakeIAPClient: IAPClient {
    private var products: [IAPProduct] = []
    private var scriptedResults: [String: IAPPurchaseResult] = [:]

    /// Fan-out broadcaster for `purchaseUpdates()` subscribers.
    ///
    /// N5-followup (impl-notes 2026-05-23 §未決 #3): the Live StoreKit2 client
    /// returns a fresh `AsyncStream` per `purchaseUpdates()` call, so multiple
    /// concurrent subscribers each get their own iterator. The previous Fake
    /// shared a single `AsyncStream` and only the first subscriber received
    /// events. We now mirror Live semantics: each `purchaseUpdates()` call
    /// allocates a new stream whose continuation is registered in
    /// `subscribers`; `emit(_:)` fans out to all live continuations.
    ///
    /// Continuations are held by token (`UUID`) so we can remove them when
    /// the consumer cancels iteration (via the stream's `onTermination`
    /// hook). The lock keeps `subscribers` writes safe across the
    /// `nonisolated` `purchaseUpdates()` accessor and the actor-isolated
    /// `emit`.
    private nonisolated let subscribers = OSAllocatedUnfairLock<
        [UUID: AsyncStream<IAPPurchaseEvent>.Continuation]
    >(initialState: [:])

    public private(set) var availableProductsCallCount: Int = 0
    public private(set) var purchaseCallCount: Int = 0
    public private(set) var restoreCallCount: Int = 0

    public init() {}

    // MARK: Scripting API

    public func setProducts(_ products: [IAPProduct]) {
        self.products = products
    }

    public func setPurchaseResult(for productId: String, result: IAPPurchaseResult) {
        scriptedResults[productId] = result
    }

    /// Emit a purchase event to every live `purchaseUpdates()` subscriber.
    public func emit(_ event: IAPPurchaseEvent) {
        let snapshot = subscribers.withLock { $0 }
        for continuation in snapshot.values {
            continuation.yield(event)
        }
    }

    /// Finish all live `purchaseUpdates()` streams — used by tests that
    /// want bounded iteration. After this, in-flight `for await` loops
    /// exit; subsequent `purchaseUpdates()` calls allocate new streams
    /// (the broadcaster itself is not "closed", only the live continuations
    /// at the moment of the call).
    public func finishUpdates() {
        let snapshot = subscribers.withLock { current in
            let copy = current
            current.removeAll()
            return copy
        }
        for continuation in snapshot.values {
            continuation.finish()
        }
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
        // Fresh stream per call (mirrors Live). The continuation is
        // registered in `subscribers` under a UUID token so `emit(_:)` can
        // fan out and `onTermination` can unregister when the consumer
        // cancels.
        let token = UUID()
        let subs = subscribers
        return AsyncStream<IAPPurchaseEvent> { continuation in
            subs.withLock { current in
                current[token] = continuation
            }
            continuation.onTermination = { _ in
                subs.withLock { current in
                    _ = current.removeValue(forKey: token)
                }
            }
        }
    }

    /// Diagnostic: number of currently-live `purchaseUpdates()` subscribers.
    /// Useful in tests that need to assert subscribe / cancel lifecycle.
    public nonisolated var purchaseUpdatesSubscriberCount: Int {
        subscribers.withLock { $0.count }
    }
}
