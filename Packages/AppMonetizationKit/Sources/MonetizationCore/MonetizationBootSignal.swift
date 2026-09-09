// MARK: - MonetizationBootSignal (#1058)
//
// A one-shot, awaitable latch marking "the app-launch monetization boot
// sequence (UMP consent → ATT → AdMob SDK initialize, `bootMonetization` /
// `MonetizationBootCoordinator`) has run to completion — every step
// ATTEMPTED, not necessarily succeeded".
//
// Why this exists: `BannerSlotView`'s first ad load used to fire from mount
// timing alone, racing `bootMonetization`'s async boot `Task` at the app
// root. `MonetizationBootCoordinator.boot()` already runs UMP → ATT → AdMob
// strictly in order (see that type's contract), so "boot finished" is a
// point at which UMP consent is GUARANTEED already resolved — by
// construction of the sequential coordinator, not by timing luck. Gating the
// FIRST ad request behind this signal (not gate resolution itself, which is
// consent-independent) makes "consent before request" hold unconditionally.
//
// Late-mount safety: a slot created AFTER boot already completed must not
// wait forever. `markReady()` is idempotent and resumes every waiter
// exactly once; `awaitReady()` returns immediately when called after that
// point, since it only suspends when `isReady` is still `false`.
//
// Concurrency: a plain `actor` — the same shape as `AdGate` /
// `BannerReloadCoordinator` in this file's neighborhood.
public actor MonetizationBootSignal {
    private var isReady: Bool
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameter alreadyReady: `true` builds a signal that never suspends —
    ///   the default for every `BannerSlotView` call site that isn't the
    ///   cold-launch Today-tab slot (Board / Practice / Settings banners
    ///   mount only after user navigation, well after boot has finished in
    ///   practice) and for every test / preview construction. Composition
    ///   roots that actually run `bootMonetization` construct `false` and
    ///   call `markReady()` once the real boot sequence completes.
    public init(alreadyReady: Bool = false) {
        self.isReady = alreadyReady
    }

    /// Suspends until `markReady()` has been called, or returns immediately
    /// if it already has been (including signals built `alreadyReady`).
    public func awaitReady() async {
        if isReady { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    /// Marks the signal ready and resumes every waiter. Idempotent — a
    /// second call is a no-op, matching `MonetizationBootCoordinator.boot()`'s
    /// own idempotency contract.
    public func markReady() {
        guard !isReady else { return }
        isReady = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }
}
