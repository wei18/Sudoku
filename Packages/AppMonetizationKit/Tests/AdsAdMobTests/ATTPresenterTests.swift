import Testing
import Foundation
import os
@testable import AdsAdMob

@Suite("AdsAdMob — ATTPresenter")
struct ATTPresenterTests {
    @Test func notDeterminedTriggersRequest() async {
        let bridge = FakeATTBridge(initialStatus: .notDetermined, postRequestStatus: .authorized)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .authorized)
        #expect(bridge.requestCallCount == 1)
    }

    @Test func authorizedSkipsRequest() async {
        let bridge = FakeATTBridge(initialStatus: .authorized, postRequestStatus: .authorized)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .authorized)
        #expect(bridge.requestCallCount == 0)
    }

    @Test func deniedSkipsRequest() async {
        let bridge = FakeATTBridge(initialStatus: .denied, postRequestStatus: .denied)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .denied)
        #expect(bridge.requestCallCount == 0)
    }

    @Test func restrictedSkipsRequest() async {
        let bridge = FakeATTBridge(initialStatus: .restricted, postRequestStatus: .restricted)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .restricted)
        #expect(bridge.requestCallCount == 0)
    }

    @Test func notDeterminedToDeniedFlow() async {
        let bridge = FakeATTBridge(initialStatus: .notDetermined, postRequestStatus: .denied)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .denied)
    }

    @Test func unsupportedPlatformReturnsUnsupported() async {
        let bridge = FakeATTBridge(initialStatus: .unsupported, postRequestStatus: .unsupported)

        let outcome = await ATTPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .unsupported)
        #expect(bridge.requestCallCount == 0)
    }
}

// MARK: - FakeATTBridge

internal struct FakeATTState: Sendable {
    var current: ATTOutcome
    var postRequest: ATTOutcome
    var requestCallCount: Int = 0
}

internal final class FakeATTBridge: ATTBridge, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<FakeATTState>

    internal init(initialStatus: ATTOutcome, postRequestStatus: ATTOutcome) {
        self.state = OSAllocatedUnfairLock(initialState: FakeATTState(
            current: initialStatus,
            postRequest: postRequestStatus
        ))
    }

    internal var requestCallCount: Int {
        state.withLock { $0.requestCallCount }
    }

    internal func currentStatus() async -> ATTOutcome {
        state.withLock { $0.current }
    }

    internal func requestAuthorization() async -> ATTOutcome {
        // swiftlint:disable:next identifier_name
        state.withLock { (s: inout FakeATTState) -> ATTOutcome in
            s.requestCallCount += 1
            s.current = s.postRequest
            return s.postRequest
        }
    }
}
