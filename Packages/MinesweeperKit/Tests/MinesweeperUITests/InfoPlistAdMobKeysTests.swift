// InfoPlistAdMobKeysTests — replaces the old Release-only fatalError gate
// that previously guarded a missing production AdMob banner unit ID in
// `MinesweeperAppComposition/Live.swift`.
//
// The keys `GADApplicationIdentifier` and `GADBannerUnitID` in
// `Minesweeper/Info.plist` are now substituted at build time from
// `Tuist/AdMob.xcconfig` (gitignored — see Tuist/AdMob.xcconfig.example).
// These tests catch accidental deletion of either key pre-archive.
//
// See the Sudoku-side mirror test for the full rationale; this file uses
// the same shape so a single change to the Info.plist convention is
// caught across both apps.

import Foundation
import Testing

@Suite("Info.plist — AdMob keys present (Minesweeper)")
struct InfoPlistAdMobKeysTests {

    private static func infoPlist() throws -> [String: Any] {
        // `AppInfo.plist` (not `Info.plist`) because SPM bans the literal
        // name as a top-level bundle resource. Contents are the App
        // target's Info.plist verbatim — see Package.swift testTarget
        // resources block.
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
}
