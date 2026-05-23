// LiveMonetizationStateStore — CloudKit Private implementation of
// `MonetizationStateStore` (plan.md v2.3.1, docs/v1/design.md §How.3).
//
// Record schema (auto-created on first write — CloudKit Dashboard pre-decl
// not required):
//   recordType:  "MonetizationState"
//   recordName:  "monetization-state"      (singleton per iCloud account)
//   zone:        com.wei18.sudoku.userZone (existing private zone)
//   fields:
//     firstLaunchAt        Date
//     lastShownDate        Date?   (omitted when nil)
//     dismissedDate        Date?   (omitted when nil)
//     hasPurchasedRemoveAds Int    (0 / 1 — RecordValue lacks a Bool case)
//     lastSeenWallClock    Date?   (omitted when nil — added v2-audit-polish
//                                   per docs/v1/design.md §How.3.1; CloudKit adds the
//                                   field on first write of a non-nil value,
//                                   old records parse missing field as nil)
//
// First-launch seeding: if `fetch` returns nil, the store synthesises an
// `AdGateState(firstLaunchAt: Date())` AND immediately writes it back so
// subsequent launches (and other devices on the same iCloud account) read
// the same anchor — required for the 7-day grace-period math to be stable
// across cold launches (per design §How.3 and v2.0 impl-notes §未決 #3).

public import Foundation
public import MonetizationCore

public actor LiveMonetizationStateStore: MonetizationStateStore {

    enum Field {
        static let firstLaunchAt = "firstLaunchAt"
        static let lastShownDate = "lastShownDate"
        static let dismissedDate = "dismissedDate"
        static let hasPurchasedRemoveAds = "hasPurchasedRemoveAds"
        static let lastSeenWallClock = "lastSeenWallClock"
    }

    public static let recordType = PrivateCKConstants.monetizationStateRecordType
    public static let recordName = "monetization-state"

    private let gatewayProvider: @Sendable () -> any PrivateCKGateway
    private var cachedGateway: (any PrivateCKGateway)?
    private let clock: @Sendable () -> Date

    public init(
        gateway: any PrivateCKGateway,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gatewayProvider = { gateway }
        self.cachedGateway = gateway
        self.clock = clock
    }

    /// Lazy-gateway initializer used by `LivePersistence.monetizationStateStore`:
    /// the provider closure is invoked the first time a load/save actually
    /// needs CloudKit, NOT at composition time. This matches `LivePersistence`'s
    /// existing pattern of deferring `CKContainer.default()` until IO so
    /// `AppComposition.live()` stays callable from unit tests.
    public init(
        gatewayProvider: @escaping @Sendable () -> any PrivateCKGateway,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.gatewayProvider = gatewayProvider
        self.cachedGateway = nil
        self.clock = clock
    }

    private func gateway() -> any PrivateCKGateway {
        if let cached = cachedGateway { return cached }
        let gateway = gatewayProvider()
        cachedGateway = gateway
        return gateway
    }

    // MARK: - MonetizationStateStore

    public func loadState() async throws -> AdGateState {
        let gw = gateway()
        if let payload = try await gw.fetch(recordName: Self.recordName),
           let state = Self.state(from: payload) {
            return state
        }
        // First-launch seed: persist immediately so the firstLaunchAt anchor
        // survives across cold launches + propagates via CloudKit sync.
        let seeded = AdGateState(firstLaunchAt: clock())
        try await gw.save(Self.payload(from: seeded))
        return seeded
    }

    public func saveState(_ state: AdGateState) async throws {
        try await gateway().save(Self.payload(from: state))
    }

    // MARK: - Mapping

    static func payload(from state: AdGateState) -> RecordPayload {
        var fields: [String: RecordValue] = [
            Field.firstLaunchAt: .date(state.firstLaunchAt),
            Field.hasPurchasedRemoveAds: .int(state.hasPurchasedRemoveAds ? 1 : 0),
        ]
        if let lastShown = state.lastShownDate {
            fields[Field.lastShownDate] = .date(lastShown)
        }
        if let dismissed = state.dismissedDate {
            fields[Field.dismissedDate] = .date(dismissed)
        }
        if let wallClock = state.lastSeenWallClock {
            fields[Field.lastSeenWallClock] = .date(wallClock)
        }
        return RecordPayload(
            recordType: recordType,
            recordName: recordName,
            fields: fields
        )
    }

    static func state(from payload: RecordPayload) -> AdGateState? {
        guard
            case .date(let firstLaunch) = payload.fields[Field.firstLaunchAt]
        else {
            return nil
        }
        let lastShown: Date?
        if case .date(let value) = payload.fields[Field.lastShownDate] {
            lastShown = value
        } else {
            lastShown = nil
        }
        let dismissed: Date?
        if case .date(let value) = payload.fields[Field.dismissedDate] {
            dismissed = value
        } else {
            dismissed = nil
        }
        let purchased: Bool
        if case .int(let value) = payload.fields[Field.hasPurchasedRemoveAds] {
            purchased = value != 0
        } else {
            purchased = false
        }
        // Old records (pre-v2-audit-polish) don't carry `lastSeenWallClock`;
        // absent field → nil → fresh anti-tamper baseline next observation.
        let lastSeenWallClock: Date?
        if case .date(let value) = payload.fields[Field.lastSeenWallClock] {
            lastSeenWallClock = value
        } else {
            lastSeenWallClock = nil
        }
        return AdGateState(
            firstLaunchAt: firstLaunch,
            lastShownDate: lastShown,
            dismissedDate: dismissed,
            hasPurchasedRemoveAds: purchased,
            lastSeenWallClock: lastSeenWallClock
        )
    }
}
