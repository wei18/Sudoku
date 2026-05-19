// AccountMonitor — implements design.md §How.6.5 Cases A/B/C.
//
// Listens (via injected providers) for the iCloud account state and the
// current user record ID. Compares the hashed user record ID against the
// last value stored in Keychain. The output enum is consumed by the App
// composition root, which performs the actual side effects (Alert,
// cache wipe).
//
// Per §How.6.5 we use `CKAccountChanged` + `fetchUserRecordID` (NOT
// `NSUbiquityIdentityDidChange`) for the signal.
//
// CloudKit is not imported here — the AccountProvider seam projects the
// CKAccountStatus into a Persistence-local enum so unit tests run without
// any system framework.

internal import Foundation

// MARK: - Seams

public enum ICloudAccountStatus: Sendable, Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
}

public protocol ICloudAccountProvider: Sendable {
    func accountStatus() async throws -> ICloudAccountStatus
    /// Returns the **hash** of the current user record ID, or nil when no
    /// account is signed in. The Live implementation calls
    /// `CKContainer.fetchUserRecordID(...)` and hashes the recordName.
    func currentUserRecordIDHash() async throws -> String?
}

public protocol UserHashKeychain: Sendable {
    func loadStoredHash() async throws -> String?
    func storeHash(_ value: String) async throws
    func clear() async throws
}

// MARK: - Outcome

public enum AccountChangeOutcome: Sendable, Equatable {
    case unchanged
    case signedOut
    case switched(oldHash: String?, newHash: String)
}

// MARK: - Monitor

public actor AccountMonitor {

    private let provider: any ICloudAccountProvider
    private let keychain: any UserHashKeychain

    public init(provider: any ICloudAccountProvider, keychain: any UserHashKeychain) {
        self.provider = provider
        self.keychain = keychain
    }

    /// Probes the current state and returns the change classification.
    /// The caller (App composition root) decides Alert / wipe behavior.
    public func handleAccountChange() async throws -> AccountChangeOutcome {
        let status = try await provider.accountStatus()
        let stored = try await keychain.loadStoredHash()
        switch status {
        case .noAccount, .restricted, .couldNotDetermine:
            if stored != nil {
                try await keychain.clear()
                return .signedOut
            }
            return .unchanged
        case .available:
            guard let currentHash = try await provider.currentUserRecordIDHash() else {
                if stored != nil {
                    try await keychain.clear()
                    return .signedOut
                }
                return .unchanged
            }
            if stored == currentHash {
                return .unchanged
            }
            try await keychain.storeHash(currentHash)
            return .switched(oldHash: stored, newHash: currentHash)
        }
    }

    /// Convenience guard for CRUD entry points — throws the right error
    /// without performing any side-effects on the keychain.
    public func currentGuard(everSignedIn: Bool) async throws {
        let status = try await provider.accountStatus()
        switch status {
        case .available:
            return
        case .noAccount, .restricted, .couldNotDetermine:
            if everSignedIn {
                throw PersistenceError.iCloudSignedOutDuringSession
            } else {
                throw PersistenceError.iCloudNotSignedIn
            }
        }
    }
}
