// PrivacyManifestTests — Phase 9.3 + v2.4.
//
// Locks the privacy manifest contents. v2 (post #62) declares AdMob
// tracking: NSPrivacyTracking=true, 8 tracking domains, OtherUsageData
// collection (Tracking=true, ThirdPartyAdvertising purpose), and the
// UserDefaults Required Reason API (CA92.1). The manifest lives next to
// the App target (`App/Resources/PrivacyInfo.xcprivacy`) — we navigate
// up from the test source file's path to read it.

import Foundation
import Testing

@Suite("PrivacyInfo.xcprivacy — Phase 9.3")
struct PrivacyManifestTests {

    private static func manifestURL() throws -> URL {
        // Bundle.module resolves the symlinked `Resources/PrivacyInfo.xcprivacy`
        // declared in Package.swift testTarget resources. Works on Xcode Cloud
        // where the source tree isn't on the test runner machine.
        guard let url = Bundle.module.url(forResource: "PrivacyInfo", withExtension: "xcprivacy") else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return url
    }

    @Test
    func manifestPresent() throws {
        let url = try Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        )
        #expect(plist is [String: Any])
    }

    @Test
    func adMobTrackingDeclared() throws {
        // v2 (post #62): AdMob is the third-party tracker; the manifest
        // must declare tracking + the 8 AdMob domains + the OtherUsageData
        // collection mapped to ThirdPartyAdvertising.
        let url = try Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        let tracking = plist?["NSPrivacyTracking"] as? Bool
        let domains = plist?["NSPrivacyTrackingDomains"] as? [String]
        let collected = plist?["NSPrivacyCollectedDataTypes"] as? [[String: Any]]
        #expect(tracking == true)
        #expect(domains?.contains("googleadservices.com") == true)
        #expect(domains?.contains("doubleclick.net") == true)
        #expect((domains?.count ?? 0) >= 8)
        #expect(collected?.isEmpty == false)
        let entry = collected?.first
        #expect(entry?["NSPrivacyCollectedDataType"] as? String == "NSPrivacyCollectedDataTypeOtherUsageData")
        #expect(entry?["NSPrivacyCollectedDataTypeTracking"] as? Bool == true)
        let purposes = entry?["NSPrivacyCollectedDataTypePurposes"] as? [String]
        #expect(purposes?.contains("NSPrivacyCollectedDataTypePurposeThirdPartyAdvertising") == true)
    }

    @Test
    func requiredReasonsAPIsDeclared() throws {
        // v2 (post #62): AdMob reads UserDefaults internally per Google's
        // privacy manifest docs — declared with reason CA92.1.
        let url = try Self.manifestURL()
        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any]
        let apis = plist?["NSPrivacyAccessedAPITypes"] as? [[String: Any]]
        #expect(apis?.isEmpty == false)
        let userDefaults = apis?.first { entry in
            (entry["NSPrivacyAccessedAPIType"] as? String) == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        #expect(userDefaults != nil)
        let reasons = userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String]
        #expect(reasons?.contains("CA92.1") == true)
    }
}
