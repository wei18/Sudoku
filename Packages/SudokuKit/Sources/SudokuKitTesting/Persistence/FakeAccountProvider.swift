// FakeAccountProvider / FakeUserHashKeychain — in-memory seams for
// AccountMonitor tests (Phase 5.7).

public import Foundation
public import Persistence

public actor FakeAccountProvider: ICloudAccountProvider {
    public private(set) var status: ICloudAccountStatus
    public private(set) var currentHash: String?

    public init(status: ICloudAccountStatus = .available, currentHash: String? = nil) {
        self.status = status
        self.currentHash = currentHash
    }

    public func setStatus(_ status: ICloudAccountStatus) { self.status = status }
    public func setCurrentHash(_ hash: String?) { self.currentHash = hash }

    public func accountStatus() async throws -> ICloudAccountStatus { status }
    public func currentUserRecordIDHash() async throws -> String? { currentHash }
}

public actor FakeUserHashKeychain: UserHashKeychain {
    public private(set) var stored: String?

    public init(initial: String? = nil) {
        self.stored = initial
    }

    public func loadStoredHash() async throws -> String? { stored }
    public func storeHash(_ value: String) async throws { stored = value }
    public func clear() async throws { stored = nil }
}
