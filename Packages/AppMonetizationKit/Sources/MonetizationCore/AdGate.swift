public import Foundation

// MARK: - AdGateState

/// Persisted state driving banner-frequency decisions. Sync target: CloudKit
/// Private (see design.md §How.3) so a player's grace-period progress + Remove
/// Ads entitlement follow them across devices.
public struct AdGateState: Sendable, Codable, Equatable {
    /// First-ever launch timestamp (per iCloud account). Set once by the
    /// concrete store on the first `loadState()` call when no record exists.
    public var firstLaunchAt: Date
    /// Calendar-day-start on which a banner was most recently shown.
    public var lastShownDate: Date?
    /// Calendar-day-start on which the user dismissed the banner.
    public var dismissedDate: Date?
    /// User has purchased the Remove Ads non-consumable IAP.
    public var hasPurchasedRemoveAds: Bool

    public init(
        firstLaunchAt: Date,
        lastShownDate: Date? = nil,
        dismissedDate: Date? = nil,
        hasPurchasedRemoveAds: Bool = false
    ) {
        self.firstLaunchAt = firstLaunchAt
        self.lastShownDate = lastShownDate
        self.dismissedDate = dismissedDate
        self.hasPurchasedRemoveAds = hasPurchasedRemoveAds
    }
}

// MARK: - AdGateStateStore

/// Persistence seam for `AdGate`. Concrete v2 implementation
/// (`LiveMonetizationStateStore`) lives in the Sudoku App's Persistence layer
/// and writes through to CloudKit Private. Tests use `FakeAdGateStateStore`
/// from `MonetizationTesting`.
public protocol AdGateStateStore: Sendable {
    func loadState() async throws -> AdGateState
    func saveState(_ state: AdGateState) async throws
}

// MARK: - AdGate
//
// Frequency arbiter. Logic (design.md §How.3, brief):
//   1. `hasPurchasedRemoveAds == true` → false (highest precedence).
//   2. `now < firstLaunchAt + 7 days` → false (grace period).
//   3. `dismissedDate` is the same calendar day as `now` → false.
//   4. Otherwise → true.
//
// `lastShownDate` is recorded for telemetry / future dynamic-frequency work
// but does NOT itself gate display: once a banner has been shown on a given
// day, it remains visible until the user dismisses it (banner is persistent,
// per design.md §How.3 / brief clarification).
//
// Concurrency: a plain `actor` (NOT `@MainActor actor` — that's a language
// contradiction; see impl-notes §未決). UI components await from MainActor
// using normal concurrency hops.

public actor AdGate {
    private let store: any AdGateStateStore
    private let calendar: Calendar
    private var cachedState: AdGateState?

    public init(store: any AdGateStateStore, calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    // MARK: Queries

    public func shouldShowBanner(now: Date) async -> Bool {
        do {
            let state = try await currentState()
            // 1. Purchased → permanently suppressed.
            if state.hasPurchasedRemoveAds { return false }
            // 2. Grace period (first 7 days from first launch).
            let graceEnd = state.firstLaunchAt.addingTimeInterval(7 * 86_400)
            if now < graceEnd { return false }
            // 3. Dismissed today → suppressed for the rest of the day.
            if let dismissed = state.dismissedDate,
               calendar.isDate(dismissed, inSameDayAs: now) {
                return false
            }
            return true
        } catch {
            // Store failure is conservative: don't surface an ad we can't track.
            return false
        }
    }

    // MARK: Mutations

    public func recordBannerShown(now: Date) async {
        await mutate { state in
            state.lastShownDate = self.calendar.startOfDay(for: now)
        }
    }

    public func recordBannerDismissed(now: Date) async {
        await mutate { state in
            state.dismissedDate = self.calendar.startOfDay(for: now)
        }
    }

    public func recordPurchase() async {
        await mutate { state in
            state.hasPurchasedRemoveAds = true
        }
    }

    // MARK: Internals

    private func currentState() async throws -> AdGateState {
        if let cached = cachedState { return cached }
        let loaded = try await store.loadState()
        cachedState = loaded
        return loaded
    }

    private func mutate(_ transform: (inout AdGateState) -> Void) async {
        do {
            var state = try await currentState()
            transform(&state)
            cachedState = state
            try await store.saveState(state)
        } catch {
            // Persistence error is surfaced via telemetry by the live store;
            // here we keep the cache consistent with what we tried to save
            // so subsequent reads behave deterministically within the session.
        }
    }
}
