// PrivacyManifestTests — Phase 9.3.
//
// Locks the privacy manifest contents: no third-party tracking, empty
// `NSPrivacyCollectedDataTypes`, and a parseable plist. The manifest
// lives next to the App target (`App/Resources/PrivacyInfo.xcprivacy`)
// — we navigate up from the test source file's path to read it.

import Foundation
import Testing

@Suite("PrivacyInfo.xcprivacy — Phase 9.3")
struct PrivacyManifestTests {

    private static func manifestURL(_ filePath: StaticString = #filePath) -> URL {
        // <repo>/Packages/SudokuKit/Tests/AppCompositionTests/<this file>
        // → <repo>/App/Resources/PrivacyInfo.xcprivacy
        let path = String(describing: filePath)
        let testFile = URL(fileURLWithPath: path)
        let repoRoot = testFile
            .deletingLastPathComponent()  // AppCompositionTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // SudokuKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // <repo>
        return repoRoot
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent("PrivacyInfo.xcprivacy")
    }

    @Test
    func manifestPresent() throws {
        let url = Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        #expect(plist is [String: Any])
    }

    @Test
    func noThirdPartyTrackingDomains() throws {
        let url = Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        let tracking = plist?["NSPrivacyTracking"] as? Bool
        let domains = plist?["NSPrivacyTrackingDomains"] as? [Any]
        let collected = plist?["NSPrivacyCollectedDataTypes"] as? [Any]
        #expect(tracking == false)
        #expect(domains?.isEmpty == true)
        #expect(collected?.isEmpty == true)
    }

    @Test
    func requiredReasonsAPIsDeclared() throws {
        // v1 production code does not invoke any "Required Reason" API
        // category — so the array is intentionally empty. The test guards
        // the shape: the key must be present (even if empty) so that the
        // App Store validator does not warn.
        let url = Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        let apis = plist?["NSPrivacyAccessedAPITypes"] as? [Any]
        #expect(apis != nil)
        #expect(apis?.isEmpty == true)
    }
}
