public import Foundation
public import MonetizationCore
public import Observation
public import SwiftUI

// MARK: - BannerSlotID

/// Identity of one mounted banner slot. Status, handle and load are keyed by
/// it, so two mounted slots never share one banner view (#1058).
public struct BannerSlotID: Hashable, Sendable {
    public let rawValue: UUID

    public init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

// MARK: - BannerSessionModel
//
// Session-scoped banner state (#1058; spec: meetings/2026-09-11_1058-slot-model-design.md).
// ONE instance per app session resolves the ad gate, waits for provider
// readiness once, requests the ATT primer, drives per-slot loads and disposes
// handles; slot views only render what it publishes.
//
// Per-session order: gate → `.suppressed` check → `awaitReady()` →
// `onAdContext` → loads. `load(_:token:)` is the only path that reaches the
// provider's load, so cold launch, registration and repoll all share it.

@MainActor
@Observable
public final class BannerSessionModel {
    /// Gate decision; `nil` until the session's first resolution (#723 seed).
    public private(set) var shouldShow: Bool?
    /// The provider can never serve an ad (macOS `NoopAdProvider`, #968).
    public private(set) var providerSuppressed = false
    /// Per-slot status. A missing entry reads as `.notInitialized`.
    public private(set) var slots: [BannerSlotID: AdBannerStatus] = [:]

    public var isVisible: Bool {
        shouldShow == true && !providerSuppressed
    }

    public func status(for id: BannerSlotID) -> AdBannerStatus {
        slots[id] ?? .notInitialized
    }

    /// The live banner view for the slot's loaded handle, or `nil` when the
    /// slot holds no loaded handle or the provider hosts no real view (fakes).
    /// A suppressed provider (macOS `NoopAdProvider`) never gets a load, so a
    /// failing `BannerViewProviding` cast is unreachable by ordering — the same
    /// rule that makes Noop's `unsupported` throw unreachable.
    public func bannerView(for id: BannerSlotID) -> AnyView? {
        guard case let .loaded(handle) = slots[id] else { return nil }
        return (services?.adProvider as? any BannerViewProviding)?.bannerView(for: handle)
    }

    private struct Services {
        let adProvider: any AdProvider
        let adGate: AdGate
        let reloadCoordinator: BannerReloadCoordinator
        let onAdContext: (@Sendable () async -> Void)?
        let now: @Sendable () -> Date
    }

    private struct LoadEntry {
        let token: UUID
        let task: Task<Void, Never>
    }

    private let services: Services?
    private let sessionReady = ReadinessLatch()
    @ObservationIgnored private var readyTask: Task<Void, Never>?
    @ObservationIgnored private var startTask: Task<Void, Never>?
    @ObservationIgnored private var loads: [BannerSlotID: LoadEntry] = [:]
    @ObservationIgnored private var registered: Set<BannerSlotID> = []
    /// Bumped by every `hideAll()`. `runStart` and `sceneDidBecomeActive`
    /// capture it before their first await and drop their publish and loads
    /// when a hide (purchase, dismiss) landed while they were suspended.
    @ObservationIgnored private var hideGeneration = 0

    public init(
        adProvider: any AdProvider,
        adGate: AdGate,
        onAdContext: (@Sendable () async -> Void)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        services = Services(
            adProvider: adProvider,
            adGate: adGate,
            reloadCoordinator: BannerReloadCoordinator(adProvider: adProvider, adGate: adGate),
            onAdContext: onAdContext,
            now: now
        )
    }

    private init(disabled: Void) {
        services = nil
        shouldShow = false
    }

    /// A model that never shows a banner and holds no provider. Allowed in
    /// exactly three places: previews, snapshot fixtures that render slots
    /// without ads, and DEBUG test hooks that bypass monetization by design
    /// (the near-win covers). Any other use is a CR reject.
    public static let disabled = BannerSessionModel(disabled: ())

    // MARK: - Lifecycle

    /// Resolves the gate and, if ads can show, begins the session's single
    /// readiness wait and schedules loads. Idempotent: every caller joins the
    /// first run.
    public func start() async {
        if startTask == nil {
            startTask = Task { await self.runStart() }
        }
        await startTask?.value
    }

    /// Foreground re-poll (#341). Joins `start()`, then re-resolves the gate: a
    /// closed gate hides without touching the provider; an open one brings a
    /// hidden banner back, loads slots with no handle and retries failed ones.
    public func sceneDidBecomeActive() async {
        guard let services else { return }
        let generation = hideGeneration
        await start()
        guard await services.adGate.shouldShowBanner(now: services.now()) else {
            await hideAll()
            return
        }
        guard await providerCanServe(services), hideGeneration == generation else { return }
        if shouldShow != true { shouldShow = true }
        beginReadinessOnce()
        ensureLoads(retryingFailed: registered)
    }

    /// The user tapped ✕: records today's dismissal, then hides every slot.
    public func dismiss() async {
        guard let services else { return }
        await services.adGate.recordBannerDismissed(now: services.now())
        await hideAll()
    }

    /// Re-resolves the gate after an entitlement change (Remove Ads purchase)
    /// and hides every slot if it is now closed.
    public func refreshGate() async {
        guard let services else { return }
        if await !services.adGate.shouldShowBanner(now: services.now()) {
            await hideAll()
        }
    }

    // MARK: - Slots

    public func register(_ id: BannerSlotID) {
        guard services != nil, registered.insert(id).inserted else { return }
        ensureLoads(retryingFailed: [id])
    }

    public func unregister(_ id: BannerSlotID) {
        guard registered.remove(id) != nil else { return }
        loads.removeValue(forKey: id)?.task.cancel()
        // Every write to `slots` notifies observers, so only write when this
        // slot actually has an entry.
        guard let status = slots[id] else { return }
        slots[id] = nil
        if case let .loaded(handle) = status, let provider = services?.adProvider {
            Task { await provider.dispose(handle: handle) }
        }
    }

    // MARK: - Internals

    private func runStart() async {
        guard let services else { return }
        let generation = hideGeneration
        let open = await services.adGate.shouldShowBanner(now: services.now())
        guard hideGeneration == generation else { return }
        shouldShow = open
        guard open, await providerCanServe(services), hideGeneration == generation else { return }
        beginReadinessOnce()
        ensureLoads()
    }

    private func providerCanServe(_ services: Services) async -> Bool {
        if providerSuppressed { return false }
        guard await services.adProvider.bannerStatus != .suppressed else {
            providerSuppressed = true
            return false
        }
        return true
    }

    /// The app's only `AdProvider.awaitReady()` call.
    private func beginReadinessOnce() {
        guard let services, readyTask == nil else { return }
        let provider = services.adProvider
        let onAdContext = services.onAdContext
        let sessionReady = sessionReady
        readyTask = Task {
            // Nothing cancels this task. If something ever did, `sessionReady`
            // would stay closed and visible slots would stay reserved at
            // `.notInitialized`: no ad, and no false "Ad unavailable".
            do { try await provider.awaitReady() } catch { return }
            await onAdContext?()
            sessionReady.open()
        }
    }

    /// Schedules a load for every registered slot that needs one. A `.failed`
    /// slot is retried only when the trigger names it — its own registration,
    /// or a repoll naming every slot — so mounting one slot never re-requests
    /// another slot's failed banner.
    private func ensureLoads(retryingFailed retry: Set<BannerSlotID> = []) {
        // `runStart` publishes `shouldShow` before its suppression check, so
        // `isVisible` can be true before readiness has begun. A load scheduled
        // in that window would only park on `sessionReady` (for good, if the
        // provider turns out suppressed). No caller can observe the difference,
        // so this guard is belt-and-braces and no test pins it.
        guard isVisible, readyTask != nil else { return }
        for id in registered where loads[id] == nil && needsLoad(id, retrying: retry) {
            let token = UUID()
            loads[id] = LoadEntry(token: token, task: Task { await self.load(id, token: token) })
        }
    }

    private func needsLoad(_ id: BannerSlotID, retrying retry: Set<BannerSlotID>) -> Bool {
        if case .loaded = slots[id] { return false }
        if case .failed = slots[id] { return retry.contains(id) }
        return true
    }

    private func load(_ id: BannerSlotID, token: UUID) async {
        defer {
            if loads[id]?.token == token { loads[id] = nil }
        }
        guard let services else { return }
        do {
            try await sessionReady.wait()
            try Task.checkCancellation()
            let status = try await services.reloadCoordinator.reloadIfGateOpen(now: services.now())
            guard !Task.isCancelled, registered.contains(id) else {
                if case let .loaded(handle) = status { await services.adProvider.dispose(handle: handle) }
                return
            }
            if status == .suppressed {
                await hideAll()
                return
            }
            slots[id] = status
        } catch is CancellationError {
            return
        } catch {
            // Unreachable: `wait()`, `checkCancellation()` and the coordinator's
            // typed throw only ever throw `CancellationError`; this clause exists
            // because `ReadinessLatch.wait()` is declared with untyped `throws`.
            assertionFailure("unexpected non-cancellation error: \(error)")
        }
    }

    private func hideAll() async {
        hideGeneration &+= 1
        if shouldShow != false { shouldShow = false }
        for entry in loads.values { entry.task.cancel() }
        loads = [:]
        let handles = slots.values.compactMap { status -> AdBannerHandle? in
            if case let .loaded(handle) = status { return handle }
            return nil
        }
        if !slots.isEmpty { slots = [:] }
        guard let provider = services?.adProvider else { return }
        for handle in handles {
            await provider.dispose(handle: handle)
        }
    }
}
