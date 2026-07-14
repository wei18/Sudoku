// InfoPlistAdMobKeysTests — replaces the old Release-only fatalError gate
// that previously guarded a missing production AdMob banner unit ID.
//
// The keys `GADApplicationIdentifier` and `GADBannerUnitID` in
// `Sudoku/Info.plist` are now substituted at build time from
// `Tuist/AdMob.xcconfig` (gitignored — see Tuist/AdMob.xcconfig.example).
// These tests catch accidental deletion of either key pre-archive.
//
// Note: the literal source-file value is `$(ADMOB_APP_ID)` /
// `$(ADMOB_BANNER_UNIT_ID)` — the test only asserts the keys are present
// and non-empty as strings, NOT that they resolve to a real AdMob ID.
// Runtime resolution is the AdMob SDK's responsibility (it crashes loudly
// at `MobileAds.shared.start` if misconfigured), and any
// xcconfig-not-found case at build time leaves the unresolved `$(…)`
// string in place — still non-nil, still non-empty.

import Foundation
import Testing

@Suite("Info.plist — AdMob keys present")
struct InfoPlistAdMobKeysTests {

    private static func infoPlist() throws -> [String: Any] {
        // Mirrors `PrivacyManifestTests`' approach: the App target's
        // Info.plist is duplicated into this test target's resources so
        // Xcode Cloud (where the source tree isn't on the test runner)
        // can still read it via Bundle.module.
        // `AppInfo.plist` (not `Info.plist`) because SPM bans the literal
        // name as a top-level bundle resource. Contents are the App
        // target's Info.plist verbatim — see Package.swift testTarget
        // resources block.
        //
        // Drift risk (issue #267, accepted): this copy can fall out of sync
        // if a future PR adds an Info.plist key without mirroring it here —
        // the smoke test would pass against a stale plist. Accepted because
        // this test only guards the two AdMob keys, which are not plausibly
        // deleted by accident. Escalate to a byte-for-byte sync sentinel
        // only if a real drift incident occurs.
        guard let url = Bundle.module.url(forResource: "AppInfo", withExtension: "plist") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        let data = try Data(contentsOf: url)
        guard
            let plist = try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            ) as? [String: Any]
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return plist
    }

    @Test
    func gadApplicationIdentifierPresent() throws {
        let plist = try Self.infoPlist()
        let value = plist["GADApplicationIdentifier"] as? String
        #expect(value != nil)
        #expect(value?.isEmpty == false)
    }

    @Test
    func gadBannerUnitIDPresent() throws {
        let plist = try Self.infoPlist()
        let value = plist["GADBannerUnitID"] as? String
        #expect(value != nil)
        #expect(value?.isEmpty == false)
    }

    // #744: `AppStoreID` — same build-time-secret-injection shape as the
    // AdMob keys above, substituted from `Tuist/AppStore.xcconfig`.
    @Test
    func appStoreIDPresent() throws {
        let plist = try Self.infoPlist()
        let value = plist["AppStoreID"] as? String
        #expect(value != nil)
        #expect(value?.isEmpty == false)
    }
}
