public import MonetizationCore

// MARK: - FakeIAPClient

public actor FakeIAPClient: IAPClient {
    private var products: [IAPProduct] = []
    private var scriptedResults: [String: IAPPurchaseResult] = [:]
    /// Stream + continuation are pre-created at init time so the `nonisolated`
    /// `purchaseUpdates()` accessor can return them without touching actor
    /// state. `AsyncStream` is single-consumer; tests should subscribe once.
    private nonisolated let updatesStream: AsyncStream<IAPPurchaseEvent>
    private nonisolated let updatesContinuation: AsyncStream<IAPPurchaseEvent>.Continuation

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
        updatesStream
    }
}
