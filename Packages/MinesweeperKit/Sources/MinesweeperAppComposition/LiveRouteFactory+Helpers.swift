// LiveRouteFactory+Helpers.swift — static helpers extracted from
// LiveRouteFactory (SDD-003 Epic 8 pushed the main file over the 400-line
// ceiling; extraction per the repo convention instead of a file-wide
// swiftlint disable).

internal import SettingsUI
internal import Foundation
#if canImport(UIKit)
internal import UIKit
#endif

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
}
