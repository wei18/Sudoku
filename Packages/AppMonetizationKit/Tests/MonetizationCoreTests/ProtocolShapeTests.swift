import Foundation
import Testing
@testable import MonetizationCore

// swiftlint:disable identifier_name

// Compile-time helper — refuses to compile if the type loses Sendable.
private func assertSendable<T: Sendable>(_ value: T) {}

// MARK: - AdProvider protocol-witness fixture
//
// In-test conformer that exercises every member of `AdProvider`. If the
// protocol surface changes (signature, async-ness, sendability) this struct
// fails to compile — which is the test.

private actor _ProtocolWitnessAdProvider: AdProvider {
    var bannerStatus: AdBannerStatus { .notInitialized }
    func initialize() async throws {}
    func refreshBanner() async throws {}
    func dispose(handle: AdBannerHandle) async {}
}

// MARK: - IAPClient protocol-witness fixture

private actor _ProtocolWitnessIAPClient: IAPClient {
    func availableProducts() async throws -> [IAPProduct] { [] }
    func purchase(_ productId: String) async throws -> IAPPurchaseResult { .userCancelled }
    func restorePurchases() async throws -> [IAPProduct] { [] }
    nonisolated func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

@Suite("MonetizationCore — protocol & value-type surface")
struct ProtocolShapeTests {

    // MARK: AdProvider

    @Test func adProviderProtocolWitnessCompiles() async throws {
        let provider: any AdProvider = _ProtocolWitnessAdProvider()
        let status = await provider.bannerStatus
        #expect(status == .notInitialized)
        try await provider.initialize()
        try await provider.refreshBanner()
        await provider.dispose(handle: AdBannerHandle())
    }

    // MARK: AdBannerStatus / AdBannerHandle

    @Test func adBannerHandleEquatability() {
        let id = UUID()
        let h1 = AdBannerHandle(id: id)
        let h2 = AdBannerHandle(id: id)
        let h3 = AdBannerHandle()  // default UUID — unique
        #expect(h1 == h2)
        #expect(h1 != h3)
        assertSendable(h1)
    }

    @Test func adBannerStatusEquatability() {
        let handle = AdBannerHandle()
        let a: AdBannerStatus = .loaded(handle)
        let b: AdBannerStatus = .loaded(handle)
        let c: AdBannerStatus = .failed(reason: "no fill")
        #expect(a == b)
        #expect(a != c)
        #expect(AdBannerStatus.notInitialized == .notInitialized)
        #expect(AdBannerStatus.suppressed == .suppressed)
        assertSendable(a)
    }

    // MARK: IAPClient

    @Test func iapClientProtocolWitnessCompiles() async throws {
        let client: any IAPClient = _ProtocolWitnessIAPClient()
        let products = try await client.availableProducts()
        #expect(products.isEmpty)
        let result = try await client.purchase("foo")
        #expect(result == .userCancelled)
        let restored = try await client.restorePurchases()
        #expect(restored.isEmpty)
        let stream = client.purchaseUpdates()
        var iterator = stream.makeAsyncIterator()
        // Stream finishes immediately — first element is nil.
        let first = await iterator.next()
        #expect(first == nil)
    }

    // MARK: IAPProduct / IAPPurchaseResult / IAPPurchaseEvent

    @Test func iapProductEquatabilityAndSendability() {
        let p1 = IAPProduct(id: "x", displayName: "X", displayPrice: "$1", isPurchased: false)
        let p2 = IAPProduct(id: "x", displayName: "X", displayPrice: "$1", isPurchased: false)
        let p3 = IAPProduct(id: "x", displayName: "X", displayPrice: "$1", isPurchased: true)
        #expect(p1 == p2)
        #expect(p1 != p3)
        assertSendable(p1)
    }

    @Test func iapPurchaseResultEquatability() {
        let product = IAPProduct(id: "x", displayName: "X", displayPrice: "$1", isPurchased: true)
        let s1: IAPPurchaseResult = .success(product)
        let s2: IAPPurchaseResult = .success(product)
        #expect(s1 == s2)
        #expect(IAPPurchaseResult.userCancelled == .userCancelled)
        #expect(IAPPurchaseResult.pending == .pending)
        let f1: IAPPurchaseResult = .failed(reason: "network")
        let f2: IAPPurchaseResult = .failed(reason: "network")
        let f3: IAPPurchaseResult = .failed(reason: "cancelled")
        #expect(f1 == f2)
        #expect(f1 != f3)
        #expect(s1 != f1)
        assertSendable(s1)
    }

    @Test func iapPurchaseEventEquatability() {
        let a: IAPPurchaseEvent = .purchased(productId: "x")
        let b: IAPPurchaseEvent = .purchased(productId: "x")
        let c: IAPPurchaseEvent = .revoked(productId: "x")
        #expect(a == b)
        #expect(a != c)
        assertSendable(a)
    }

    // MARK: AdPresentationAnchor

    @Test func adPresentationAnchorIsSendableAndCarriesID() {
        let uuid = UUID()
        let anchor = AdPresentationAnchor(id: uuid)
        #expect(anchor.id == uuid)
        assertSendable(anchor)
    }

    // MARK: Value-type Sendable compile-time coverage (N6)
    //
    // `assertSendable<T: Sendable>` is a compile-time-only checker — if any of
    // these value types accidentally lose their `Sendable` conformance the
    // file stops compiling here. Runtime assertion is trivial; the test
    // exists for the compile-time signal.

    @Test func valueTypesRemainSendable() {
        let state = AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        assertSendable(state)

        let product = IAPProduct(id: "x", displayName: "X", displayPrice: "$1", isPurchased: false)
        assertSendable(product)

        let purchased: IAPPurchaseEvent = .purchased(productId: "x")
        assertSendable(purchased)

        let revoked: IAPPurchaseEvent = .revoked(productId: "x")
        assertSendable(revoked)

        let purchaseResultSuccess: IAPPurchaseResult = .success(product)
        assertSendable(purchaseResultSuccess)

        let bannerStatus: AdBannerStatus = .loaded(AdBannerHandle())
        assertSendable(bannerStatus)

        let anchor = AdPresentationAnchor()
        assertSendable(anchor)
    }
}
// swiftlint:enable identifier_name
