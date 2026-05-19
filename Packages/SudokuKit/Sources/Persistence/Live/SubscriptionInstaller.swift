// SubscriptionInstaller — installs the single `CKDatabaseSubscription`
// per §How.2.
//
// Thin wrapper over `PrivateCKGateway.installSubscriptionIfNeeded()` so
// the App composition root has a named handle to call at launch (and so
// tests can target a specific surface).

internal import Foundation

internal struct SubscriptionInstaller: Sendable {
    private let gateway: any PrivateCKGateway

    init(gateway: any PrivateCKGateway) {
        self.gateway = gateway
    }

    /// Idempotent: a second call is a no-op once installed (the gateway
    /// short-circuits internally).
    func installIfNeeded() async throws {
        try await gateway.installSubscriptionIfNeeded()
    }
}
