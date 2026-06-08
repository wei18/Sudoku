public import Foundation

// MARK: - BannerReloadCoordinator (#341)
//
// The gate-aware reload seam. `AdProvider.refreshBanner()` documents that the
// slot can re-load when the gate reopens (e.g. next calendar day), but no view
// path called it a second time — once the banner was dismissed it stayed gone
// until app relaunch (#341, surfaced by #276 CR Low-2).
//
// This coordinator is that missing second pass: given a re-poll trigger
// (scene activation, returning to the banner surface, a new calendar day), it
// re-evaluates `AdGate` and re-loads the provider ONLY when the gate is open.
//
// Remove-Ads safety (the headline invariant): suppression is decided entirely
// by `AdGate.shouldShowBanner`. A purchaser's gate returns `false`, so the
// coordinator returns `.suppressed` and NEVER calls `refreshBanner()`. The
// provider is only touched after the gate has already said "yes". The same
// applies to the dismissed-today and clock-tamper gate rules.
//
// Concurrency: a plain `actor`. UI components (MainActor) await the single
// `reloadIfGateOpen(now:)` entry point on a re-poll trigger.

public actor BannerReloadCoordinator {
    private let adProvider: any AdProvider
    private let adGate: AdGate

    public init(adProvider: any AdProvider, adGate: AdGate) {
        self.adProvider = adProvider
        self.adGate = adGate
    }

    /// Re-evaluate the gate and, only if it is open, force a fresh banner load.
    ///
    /// - Returns: the resulting `AdBannerStatus` the UI slot should render.
    ///   `.suppressed` when the gate is closed (purchased / dismissed-today /
    ///   clock-tamper) — in which case the provider is never touched.
    ///   `.failed(...)` if the gate is open but the reload throws.
    @discardableResult
    public func reloadIfGateOpen(now: Date) async -> AdBannerStatus {
        guard await adGate.shouldShowBanner(now: now) else {
            // Gate closed. Remove-Ads / dismissed-today / tamper — do NOT
            // touch the provider. The slot collapses on `.suppressed`.
            return .suppressed
        }
        do {
            try await adProvider.refreshBanner()
            return await adProvider.bannerStatus
        } catch {
            return .failed(reason: String(describing: error))
        }
    }
}
