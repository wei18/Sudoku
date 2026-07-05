// LiveRouteFactory+Helpers.swift — static helpers extracted from
// LiveRouteFactory (SDD-003 Epic 8 pushed the main file over the 400-line
// ceiling; extraction per the repo convention instead of a file-wide
// swiftlint disable).

internal import SwiftUI
internal import MonetizationUI
internal import MinesweeperUI
internal import GameShellUI
internal import SettingsUI
internal import Persistence
internal import Telemetry
internal import MinesweeperPersistence
internal import Foundation

extension LiveRouteFactory {
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
