// PlatformVersionResolverTests — pure (no-network) coverage for the
// platform-aware version selection that fixes the multi-platform defect
// (one ASC app holds a separate appStoreVersion per platform). Complements the
// URLProtocol-stub end-to-end coverage in ASCClientURLProtocolTests.

import Testing
@testable import ASCRegister

@Suite("PlatformVersionResolver")
internal struct PlatformVersionResolverTests {

    /// Build a platform-tagged version fixture.
    private func make(
        _ platform: String, _ id: String, _ version: String, _ state: String
    ) -> PlatformVersionResolver.PlatformVersion {
        PlatformVersionResolver.PlatformVersion(
            platform: platform,
            version: SetVersionResolver.Version(id: id, versionString: version, state: state)
        )
    }

    @Test("resolve all picks one editable version per platform")
    internal func resolveAllGroupsByPlatform() {
        let outcome = PlatformVersionResolver.resolve(
            versions: [
                make("IOS", "ios-v", "1.0", "PREPARE_FOR_SUBMISSION"),
                make("MAC_OS", "mac-v", "2.3.5", "PREPARE_FOR_SUBMISSION"),
            ],
            filter: .all, versionFilter: nil
        )
        #expect(outcome.skipped.isEmpty)
        #expect(outcome.resolved.count == 2)
        #expect(Set(outcome.resolved.map(\.platform)) == ["IOS", "MAC_OS"])
        #expect(outcome.resolved.first { $0.platform == "IOS" }?.version.id == "ios-v")
        #expect(outcome.resolved.first { $0.platform == "MAC_OS" }?.version.id == "mac-v")
    }

    @Test("resolve ios filter keeps only the iOS platform")
    internal func resolveIOSFilter() {
        let outcome = PlatformVersionResolver.resolve(
            versions: [
                make("IOS", "ios-v", "1.0", "PREPARE_FOR_SUBMISSION"),
                make("MAC_OS", "mac-v", "2.3.5", "PREPARE_FOR_SUBMISSION"),
            ],
            filter: .ios, versionFilter: nil
        )
        #expect(outcome.resolved.map(\.platform) == ["IOS"])
        #expect(outcome.skipped.isEmpty)
    }

    @Test("resolve skips a platform whose only version is locked")
    internal func resolveSkipsLockedPlatform() {
        let outcome = PlatformVersionResolver.resolve(
            versions: [
                make("IOS", "ios-v", "1.0", "PREPARE_FOR_SUBMISSION"),
                make("MAC_OS", "mac-v", "2.3.5", "READY_FOR_SALE"),
            ],
            filter: .all, versionFilter: nil
        )
        #expect(outcome.resolved.map(\.platform) == ["IOS"])
        #expect(outcome.skipped.map(\.platform) == ["MAC_OS"])
    }

    @Test("single-platform app (untagged → IOS default) still resolves")
    internal func resolveSinglePlatformLegacy() {
        // platformVersions() tags an attribute-less version as IOS; the resolver
        // must still pick it under the default `all` filter (backward-compat).
        let outcome = PlatformVersionResolver.resolve(
            versions: [make("IOS", "only-v", "2.3.5", "PREPARE_FOR_SUBMISSION")],
            filter: .all, versionFilter: nil
        )
        #expect(outcome.resolved.count == 1)
        #expect(outcome.resolved[0].version.id == "only-v")
    }
}
