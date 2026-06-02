public import Foundation

// MARK: - AdGateState

/// Persisted state driving banner-frequency decisions. Sync target: CloudKit
/// Private (see docs/v1/design.md §How.3) so a player's grace-period progress + Remove
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
    /// Monotonic high-water mark of `now` observed by `shouldShowBanner`.
    /// Used purely as anti-tamper baseline (docs/v1/design.md §How.3.1): if a later
    /// query arrives with `now` materially before this value, we treat the
    /// system clock as moved backwards and refuse to advance the grace
    /// window. `nil` for fresh installs (and for records persisted before
    /// this field was introduced — see `LiveMonetizationStateStore`).
    public var lastSeenWallClock: Date?

    public init(
        firstLaunchAt: Date,
        lastShownDate: Date? = nil,
        dismissedDate: Date? = nil,
        hasPurchasedRemoveAds: Bool = false,
        lastSeenWallClock: Date? = nil
    ) {
        self.firstLaunchAt = firstLaunchAt
        self.lastShownDate = lastShownDate
        self.dismissedDate = dismissedDate
        self.hasPurchasedRemoveAds = hasPurchasedRemoveAds
        self.lastSeenWallClock = lastSeenWallClock
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
// Frequency arbiter. Logic (docs/v1/design.md §How.3, brief):
//   1. `hasPurchasedRemoveAds == true` → false (highest precedence).
//   2. (grace period removed 2026-06-02 — banner shows from first launch)
//   3. `dismissedDate` is the same calendar day as `now` → false.
//   4. Clock-tamper guard (docs/v1/design.md §How.3.1): if `lastSeenWallClock` is set
//      and `now < lastSeenWallClock - 24h tolerance`, treat as a clock
//      manipulation attempt and return false. 24h tolerance accommodates
//      DST shifts, NTP corrections, and timezone-jumping travel.
//   5. Otherwise → true.
//
// `lastShownDate` is recorded for telemetry / future dynamic-frequency work
// but does NOT itself gate display: once a banner has been shown on a given
// day, it remains visible until the user dismisses it (banner is persistent,
// per docs/v1/design.md §How.3).
//
// Concurrency: a plain `actor` (NOT `@MainActor actor` — that's a language
// contradiction; see impl-notes §未決). UI components await from MainActor
// using normal concurrency hops.

public actor AdGate {
    /// Tolerance window for backwards clock motion before we treat it as
    /// tampering. 24h covers DST + cross-timezone travel + NTP drift.
    /// Exposed as a constant rather than a parameter — the spec value is
    /// authoritative; tests inject `now` instead.
    internal static let clockTamperTolerance: TimeInterval = 86_400

    /// Minimum interval between `lastSeenWallClock` persisted advances on
    /// the read path. `shouldShowBanner` is called every Home appear; without
    /// a throttle each call writes through to CloudKit (docs/v1/design.md §How.3.1
    /// trade-off — "always-consistent baseline" vs "extra CloudKit save per
    /// Home appear"). 6h is short enough that the tamper-guard baseline stays
    /// fresh (well under the 24h tolerance window) while collapsing typical
    /// session traffic into ≤4 writes/day. The in-memory cache still updates
    /// on every call so anti-tamper checks within a session remain exact.
    internal static let wallClockAdvanceMinInterval: TimeInterval = 6 * 3_600

    private let store: any AdGateStateStore
    private let calendar: Calendar
    private let onPersistenceError: (@Sendable (any Error) -> Void)?
    private var cachedState: AdGateState?
    /// Last `lastSeenWallClock` value we actually persisted via `saveState`.
    /// Separate from `cachedState.lastSeenWallClock` because the cache is
    /// advanced on every forward step (for in-session tamper checks), while
    /// persistence is throttled to ≤ once per `wallClockAdvanceMinInterval`.
    private var lastPersistedWallClock: Date?

    /// - Parameters:
    ///   - store: Persistence seam (CloudKit-backed in production, fake in
    ///     tests).
    ///   - calendar: Calendar used for "same calendar day" comparisons.
    ///     Defaults to `.current`; host injects `.utc` for cross-timezone
    ///     determinism if needed.
    ///   - onPersistenceError: Optional sink for `saveState` failures. We
    ///     deliberately do NOT depend on Telemetry here — the host
    ///     (`AppComposition`) wires this closure to its Telemetry facade so
    ///     MonetizationCore stays observability-stack-free. Closure runs
    ///     synchronously after the failed save inside the actor; keep it
    ///     short and non-throwing.
    public init(
        store: any AdGateStateStore,
        calendar: Calendar = .current,
        onPersistenceError: (@Sendable (any Error) -> Void)? = nil
    ) {
        self.store = store
        self.calendar = calendar
        self.onPersistenceError = onPersistenceError
    }

    // MARK: Queries

    /// First-launch grace period during which the banner would be suppressed.
    /// **Spec change 2026-06-02 (closes #212): policy is now 0 — banner shows
    /// from first launch, no onboarding grace.** Field retained as a
    /// 0-valued knob to preserve the existing `shouldShowBanner` branch
    /// + state machine; removing it would change `AdGate`'s public surface
    /// for no benefit. If a future spec re-introduces a grace, just flip
    /// the value (no other code change needed).
    public static let gracePeriodDays: TimeInterval = 0

    public func shouldShowBanner(now: Date) async -> Bool {
        do {
            let state = try await currentState()
            // 1. Purchased → permanently suppressed.
            if state.hasPurchasedRemoveAds { return false }
            // 2. Grace period from first launch — currently 0 per spec change
            // 2026-06-02 (closes #212). Branch retained as a 0-valued knob so
            // re-introducing a grace is a one-constant change.
            let graceEnd = state.firstLaunchAt.addingTimeInterval(AdGate.gracePeriodDays * 86_400)
            if now < graceEnd { return false }
            // 3. Dismissed today → suppressed for the rest of the day.
            if let dismissed = state.dismissedDate,
               calendar.isDate(dismissed, inSameDayAs: now) {
                return false
            }
            // 4. Clock-tamper guard (§How.3.1). `now` arriving materially
            //    earlier than the high-water mark means the user moved the
            //    system clock backwards; refuse to advance the grace window.
            if let lastSeen = state.lastSeenWallClock,
               now < lastSeen.addingTimeInterval(-Self.clockTamperTolerance) {
                return false
            }
            // 5. Show. Advance the wall-clock high-water mark as a side
            //    effect so a subsequent clock rewind is caught.
            await advanceWallClock(to: now)
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
            state.lastSeenWallClock = max(state.lastSeenWallClock ?? .distantPast, now)
        }
    }

    public func recordBannerDismissed(now: Date) async {
        await mutate { state in
            state.dismissedDate = self.calendar.startOfDay(for: now)
            state.lastSeenWallClock = max(state.lastSeenWallClock ?? .distantPast, now)
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

    /// Bump `lastSeenWallClock` monotonically. The in-memory cache is updated
    /// on every forward step so within-session tamper checks stay exact;
    /// persistence (`mutate → saveState`) only runs when the previous
    /// persisted advance is at least `wallClockAdvanceMinInterval` (6h) old.
    /// `shouldShowBanner` is on the read path and must stay cheap — without
    /// the throttle each Home appear would write through to CloudKit.
    private func advanceWallClock(to now: Date) async {
        let cachedHighWater = cachedState?.lastSeenWallClock ?? .distantPast
        guard now > cachedHighWater else { return }
        // Throttle persistence: compare against the last value we actually
        // wrote through, NOT the cached high-water mark (which advances on
        // every forward call).
        let lastPersisted = lastPersistedWallClock
            ?? cachedState?.lastSeenWallClock  // first call after load
            ?? .distantPast
        let shouldPersist = now.timeIntervalSince(lastPersisted) >= Self.wallClockAdvanceMinInterval
        if shouldPersist {
            await mutate { state in
                state.lastSeenWallClock = max(state.lastSeenWallClock ?? .distantPast, now)
            }
            lastPersistedWallClock = now
        } else if var state = cachedState {
            // Cache-only update: keep the high-water mark current for the
            // session without burning a CloudKit save. `cachedState` is
            // guaranteed non-nil here because `shouldShowBanner` populates
            // it via `currentState()` before calling `advanceWallClock`.
            state.lastSeenWallClock = max(state.lastSeenWallClock ?? .distantPast, now)
            cachedState = state
        }
    }

    /// Apply `transform` to the cached state and persist. Cache is updated
    /// even on persistence failure so in-session reads remain consistent;
    /// the failure itself is forwarded via `onPersistenceError` (M2 — host
    /// wires this to Telemetry.errorOccurred) so save-time errors stop
    /// being invisible.
    private func mutate(_ transform: (inout AdGateState) -> Void) async {
        do {
            var state = try await currentState()
            transform(&state)
            cachedState = state
            try await store.saveState(state)
        } catch {
            // Surface to host telemetry. We do NOT rethrow — `AdGate`'s public
            // mutation API is fire-and-forget by design (UI doesn't await a
            // save outcome on banner dismiss).
            onPersistenceError?(error)
        }
    }
}
