// PrivateCKGatewayFactory — public construction seam for the live gateway
// (#455 step 4).
//
// `LivePrivateCKGateway` stays internal (its CloudKit import must not leak
// into consumers); game-specific persistence stores OUTSIDE this package
// (e.g. MinesweeperKit's `MinesweeperSavedGameStore`) receive the live
// gateway protocol-typed through this factory.
//
// LAZY by contract: the returned gateway defers `CKContainer` resolution to
// the FIRST operation. Merely constructing a `.live()` composition must stay
// CloudKit-free — the app-shape smoke tests build `.live()` in a test runner
// with no CloudKit entitlement, where `CKContainer.default()` raises an ObjC
// `CKException` (uncatchable from Swift). Mirrors how `LivePersistence`
// itself defers its gateway to per-operation construction. Zone provisioning
// remains `LivePersistence.bootstrap()`'s job; `GameRootViewModel` orders
// bootstrap before any resume fetch.

public enum PrivateCKGatewayFactory {
    /// Live CloudKit-backed gateway for the app's default container and the
    /// given per-app config. Protocol-typed so CloudKit stays encapsulated.
    public static func live(config: PrivateCKConfig) -> any PrivateCKGateway {
        DeferredLiveGateway(config: config)
    }
}

/// First-use-deferring proxy over `LivePrivateCKGateway` (see factory doc).
private actor DeferredLiveGateway: PrivateCKGateway {
    private let config: PrivateCKConfig
    private var underlying: LivePrivateCKGateway?

    init(config: PrivateCKConfig) {
        self.config = config
    }

    /// Resolves `CKContainer.default()` exactly once, on the first real op.
    private func gateway() -> LivePrivateCKGateway {
        if let underlying { return underlying }
        let made = LivePrivateCKGateway(config: config)
        underlying = made
        return made
    }

    func provisionZone() async throws {
        try await gateway().provisionZone()
    }

    func installSubscriptionIfNeeded() async throws {
        try await gateway().installSubscriptionIfNeeded()
    }

    func fetch(recordName: String) async throws -> RecordPayload? {
        try await gateway().fetch(recordName: recordName)
    }

    func save(_ payload: RecordPayload) async throws {
        try await gateway().save(payload)
    }

    func delete(recordName: String) async throws {
        try await gateway().delete(recordName: recordName)
    }

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        try await gateway().query(predicate)
    }
}
