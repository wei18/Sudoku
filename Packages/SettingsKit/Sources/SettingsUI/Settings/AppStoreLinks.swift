// AppStoreLinks — pure URL builders for the Share App / Write a Review
// Settings rows (#744).
//
// Deliberately Foundation-only + no Bundle access: the composition root
// (each app's `LiveRouteFactory`, mirroring the existing `CFBundleShortVersionString`
// / `GADBannerUnitID` reads) resolves `Bundle.main.object(forInfoDictionaryKey:
// "AppStoreID")` ONCE and injects the plain `String?` into `SettingsScreen`.
// Reading `Bundle.main` directly inside a SwiftPM library (SettingsKit) is
// flaky in the SPM test-host context (build-time-secret-injection skill,
// anti-pattern #6) — resolving it at the composition root and passing a typed
// value down keeps this helper (and `SettingsScreen`) trivially unit-testable
// with a literal fake id, no Bundle involved.

public import Foundation

public enum AppStoreLinks {
    /// `true` when `appStoreID` is present, non-empty, and not an unresolved
    /// xcconfig substitution token (`"$(...)"`) — mirrors the `GADBannerUnitID`
    /// validity check in `GameAppKit.MakeGameApp`. A syntactically-valid but
    /// fake id (e.g. the committed `0000000000` template value) still counts
    /// as valid: it renders a well-formed (if non-functional) storefront URL,
    /// the same tradeoff `ADMOB_APP_ID`'s check makes.
    public static func isValid(appStoreID: String?) -> Bool {
        guard let id = appStoreID, !id.isEmpty, !id.hasPrefix("$(") else { return false }
        return true
    }

    /// The app's App Store listing URL, for `ShareLink`. `nil` when
    /// `appStoreID` fails `isValid`.
    public static func shareURL(appStoreID: String?) -> URL? {
        guard isValid(appStoreID: appStoreID), let id = appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)")
    }

    /// The app's "write a review" deep link (`?action=write-review`) — always
    /// available, unlike the system `requestReview` prompt's 3×/365-day quota.
    /// `nil` when `appStoreID` fails `isValid`.
    public static func reviewURL(appStoreID: String?) -> URL? {
        guard isValid(appStoreID: appStoreID), let id = appStoreID else { return nil }
        return URL(string: "https://apps.apple.com/app/id\(id)?action=write-review")
    }
}
