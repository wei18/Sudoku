// LiveRouteFactory+Helpers.swift — static helpers extracted from
// LiveRouteFactory (SDD-003 Epic 8 pushed the main file over the 400-line
// ceiling; extraction per the repo convention instead of a file-wide
// swiftlint disable).

internal import SwiftUI
internal import MonetizationUI
// #814: `bannerSlot()` moved here from LiveRouteFactory.swift (400-line
// ceiling); it binds the `adProvider` / `adGate` existentials (MonetizationCore).
internal import MonetizationCore
internal import MinesweeperUI
internal import GameShellUI
internal import SettingsUI
internal import Persistence
internal import Telemetry
internal import MinesweeperPersistence
internal import Foundation

extension LiveRouteFactory {

    // MARK: - Banner helper

    /// Epic 5: banner slot for non-Home, non-Board screens. The cast from
    /// `AdProvider` → `BannerViewProviding` follows the §9.1 pattern (keeps
    /// MinesweeperAppComposition off GoogleMobileAds). When adProvider / adGate
    /// are nil (preview / test), the slot itself is not created — the caller
    /// passes EmptyView via the `banner: {}` default instead.
    @MainActor
    // Uses BannerSlotView's system-default colors, which today coincide with
    // Sudoku's themedBanner() values. If MS adopts per-theme accents, pass
    // theme tokens here like Sudoku's RouteFactory.themedBanner() (#468 Epic 5
    // theming note) so hub/settings banners match the themed Home banner.
    func bannerSlot() -> some View {
        if let adProvider, let adGate {
            AnyView(
                BannerSlotView(
                    adProvider: adProvider,
                    adGate: adGate,
                    bannerHost: adProvider as? any BannerViewProviding
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            )
        } else {
            AnyView(EmptyView())
        }
    }
    /// acknowledgements row deep-links to the app's iOS Settings page where
    /// LicensePlist's `Settings.bundle` surfaces (omitted on macOS, no
    /// deep-link); copyright derived locally; privacy/support URLs unwired
    /// pending a canonical public URL (see #331 meeting note).
    @MainActor
    internal static func makeSettingsNotices() -> SettingsNoticesConfig {
        let year = Calendar.current.component(.year, from: Date())
        var onAcknowledgements: (@MainActor () -> Void)?
        #if canImport(UIKit)
        onAcknowledgements = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
        return SettingsNoticesConfig(
            onAcknowledgements: onAcknowledgements,
            copyright: "© \(year) Wei"
        )
    }

    /// Deletes the active in-progress saved game, mirroring Sudoku's
    /// `SettingsViewModel.clearCache()`, and surfaces user feedback (#284).
    ///
    /// On success → a success toast ("Cache cleared"). On a thrown delete
    /// error → the error funnels through `errorReporter` (same channel Sudoku
    /// uses) AND a failure toast tells the user it didn't clear. Parity-only
    /// until MS save-flow lands: `latestInProgress()` returns nil today so the
    /// delete is a safe no-op and the success path is cosmetic, but it
    /// exercises the real `PersistenceProtocol` path and the error path is the
    /// real future-proofing.
    ///
    /// `internal` (not `private`) so `LiveRouteFactoryTests` can drive the
    /// success / failure branches directly with a fake persistence — there is
    /// no MS Settings ViewModel to host the logic (the Sudoku home).
    @MainActor
    static func clearCache(
        persistence: (any PersistenceProtocol)?,
        errorReporter: (any ErrorReporter)?,
        toastController: ToastController?
    ) async {
        guard let persistence else { return }
        do {
            if let candidate = try await persistence.latestInProgress() {
                try await persistence.deleteAbandoned(recordName: candidate.recordName)
            }
            // Localized via the app catalog (Bundle.main) — `Toast.message` is a
            // plain String rendered verbatim by `Text`, so the lookup happens
            // here, not at the view layer.
            toastController?.show(
                Toast(
                    style: .success,
                    message: String(localized: "Cache cleared", bundle: .main)
                )
            )
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "LiveRouteFactory.clearCache"
            )
            toastController?.show(
                Toast(
                    style: .failure,
                    message: String(localized: "Couldn't clear cache", bundle: .main)
                )
            )
        }
    }
}
