// swiftlint:disable identifier_name

import Foundation
@testable import IAPStoreKit2

// MARK: - FakeStoreKitBridge
//
// Test double for `StoreKitBridge`. Mirrors `FakeIAPClient`'s scripting style
// from `MonetizationTesting`: explicit setters, call-count introspection,
// pre-built `AsyncStream` so `transactionUpdates()` is nonisolated.

internal final class FakeStoreKitBridge: StoreKitBridge, @unchecked Sendable {
    // MARK: Scripted state (guarded by `lock` for cross-task safety)

    private let lock = NSLock()
    private var _products: [String: BridgeProduct] = [:]
    private var _entitlements: Set<String> = []
    private var _purchaseOutcomes: [String: BridgePurchaseOutcome] = [:]
    private var _productsError: (any Error)?
    private var _purchaseError: (any Error)?
    private var _syncError: (any Error)?

    // MARK: Call counters (guarded by `lock`)

    private var _productsCallCount: Int = 0
    private var _currentEntitlementsCallCount: Int = 0
    private var _purchaseCallCount: Int = 0
    private var _syncCallCount: Int = 0
    private var _transactionUpdatesCallCount: Int = 0

    var productsCallCount: Int { locked { _productsCallCount } }
    var currentEntitlementsCallCount: Int { locked { _currentEntitlementsCallCount } }
    var purchaseCallCount: Int { locked { _purchaseCallCount } }
    var syncCallCount: Int { locked { _syncCallCount } }
    var transactionUpdatesCallCount: Int { locked { _transactionUpdatesCallCount } }

    // MARK: Updates stream

    private let updatesStream: AsyncStream<BridgeTransactionEvent>
    private let updatesContinuation: AsyncStream<BridgeTransactionEvent>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<BridgeTransactionEvent>.makeStream()
        self.updatesStream = stream
        self.updatesContinuation = continuation
    }

    // MARK: Scripting API

    func setProduct(_ product: BridgeProduct) {
        locked { _products[product.id] = product }
    }

    func setEntitlements(_ ids: Set<String>) {
        locked { _entitlements = ids }
    }

    func setPurchaseOutcome(for productId: String, outcome: BridgePurchaseOutcome) {
        locked { _purchaseOutcomes[productId] = outcome }
    }

    func setProductsError(_ error: any Error) {
        locked { _productsError = error }
    }

    func setPurchaseError(_ error: any Error) {
        locked { _purchaseError = error }
    }

    func setSyncError(_ error: any Error) {
        locked { _syncError = error }
    }

    func emit(_ event: BridgeTransactionEvent) {
        updatesContinuation.yield(event)
    }

    func finishUpdates() {
        updatesContinuation.finish()
    }

    // MARK: StoreKitBridge

    func products(for ids: Set<String>) async throws -> [BridgeProduct] {
        let err: (any Error)? = locked {
            _productsCallCount += 1
            return _productsError
        }
        if let err { throw err }
        return locked {
            ids.compactMap { _products[$0] }
        }
    }

    func currentEntitlements() async -> Set<String> {
        locked {
            _currentEntitlementsCallCount += 1
            return _entitlements
        }
    }

    func purchase(productId: String) async throws -> BridgePurchaseOutcome {
        let err: (any Error)? = locked {
            _purchaseCallCount += 1
            return _purchaseError
        }
        if let err { throw err }
        let outcome = locked { _purchaseOutcomes[productId] }
        return outcome ?? .failed(reason: "no scripted outcome for \(productId)")
    }

    func sync() async throws {
        let err: (any Error)? = locked {
            _syncCallCount += 1
            return _syncError
        }
        if let err { throw err }
    }

    func transactionUpdates() -> AsyncStream<BridgeTransactionEvent> {
        locked { _transactionUpdatesCallCount += 1 }
        return updatesStream
    }

    // MARK: - Lock helper

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock(); defer { lock.unlock() }
        return body()
    }
}
