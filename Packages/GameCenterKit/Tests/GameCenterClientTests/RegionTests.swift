import Foundation
import Testing
@testable import GameCenterClient

@Suite("GameCenterClient — region mapping")
struct RegionMapperTests {

    @Test func gameUnrecognizedInRestrictedRegionMapsToUnavailable() {
        let result = RegionMapper.classify(gkErrorRawValue: 15, region: "CN")
        #expect(result == .unavailableInRegion)
    }

    @Test func notSupportedInRestrictedRegionMapsToUnavailable() {
        let result = RegionMapper.classify(gkErrorRawValue: 16, region: "CN")
        #expect(result == .unavailableInRegion)
    }

    @Test func gameUnrecognizedInUSDoesNotClassifyAsRegion() {
        // In an unrestricted region, the same code is treated as a
        // transient / configuration issue — not a region block.
        let result = RegionMapper.classify(gkErrorRawValue: 15, region: "US")
        #expect(result == .ok)
    }

    @Test func cancelledIsNotARegionSignal() {
        // GKError.cancelled rawValue == 2.
        let result = RegionMapper.classify(gkErrorRawValue: 2, region: "CN")
        #expect(result == .ok)
    }

    @Test func nilErrorIsOk() {
        let result = RegionMapper.classify(gkErrorRawValue: nil, region: nil)
        #expect(result == .ok)
    }

    @Test func unavailableInRegionAuthStateIsTheUISignal() {
        // Compile-time assertion: View layers (Phase 8) read
        // `GameCenterAuthState.unavailableInRegion` as the "hide
        // leaderboard UI" signal.
        let state: GameCenterAuthState = .unavailableInRegion
        switch state {
        case .unavailableInRegion: ()
        default: Issue.record("expected .unavailableInRegion case")
        }
    }
}
