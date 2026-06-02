import Testing
import Foundation
import os
@testable import AdsAdMob

@Suite("AdsAdMob — UMPConsentPresenter")
struct UMPConsentPresenterTests {
    @Test func consentNotRequiredReturnsNotRequired() async {
        let bridge = FakeUMPBridge(consentRequired: false)

        let outcome = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .notRequired)
        #expect(bridge.requestInfoCallCount == 1)
        #expect(bridge.presentFormCallCount == 0)
    }

    @Test func consentRequiredPresentsForm() async {
        let bridge = FakeUMPBridge(consentRequired: true)

        let outcome = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        #expect(outcome == .obtained)
        #expect(bridge.presentFormCallCount == 1)
    }

    @Test func consentInfoRequestErrorReturnsFailed() async {
        let bridge = FakeUMPBridge(consentRequired: false)
        bridge.setRequestInfoError(FakeUMPError.network)

        let outcome = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        guard case let .failed(reason) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(reason.contains("network"))
    }

    @Test func formPresentationErrorReturnsFailed() async {
        let bridge = FakeUMPBridge(consentRequired: true)
        bridge.setPresentFormError(FakeUMPError.formLoad)

        let outcome = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        guard case let .failed(reason) = outcome else {
            Issue.record("Expected .failed, got \(outcome)")
            return
        }
        #expect(reason.contains("formLoad"))
    }

    @Test func requestInfoFailureSkipsFormPresentation() async {
        let bridge = FakeUMPBridge(consentRequired: true)
        bridge.setRequestInfoError(FakeUMPError.network)

        _ = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        #expect(bridge.presentFormCallCount == 0)
    }

    @Test func repeatedCallsAreIdempotentInShape() async {
        let bridge = FakeUMPBridge(consentRequired: false)

        _ = await UMPConsentPresenter.requestIfNeeded(using: bridge)
        _ = await UMPConsentPresenter.requestIfNeeded(using: bridge)

        #expect(bridge.requestInfoCallCount == 2)
        #expect(bridge.presentFormCallCount == 0)
    }
}

// MARK: - FakeUMPBridge

internal enum FakeUMPError: Error, Equatable {
    case network
    case formLoad
}

internal struct FakeUMPState: Sendable {
    var consentRequired: Bool
    var requestInfoError: (any Error)?
    var presentFormError: (any Error)?
    var requestInfoCallCount: Int = 0
    var presentFormCallCount: Int = 0
}

internal final class FakeUMPBridge: UMPBridge, @unchecked Sendable {
    private let state: OSAllocatedUnfairLock<FakeUMPState>

    internal init(consentRequired: Bool) {
        self.state = OSAllocatedUnfairLock(initialState: FakeUMPState(consentRequired: consentRequired))
    }

    internal func setRequestInfoError(_ error: (any Error)?) {
        state.withLock { $0.requestInfoError = error }
    }

    internal func setPresentFormError(_ error: (any Error)?) {
        state.withLock { $0.presentFormError = error }
    }

    internal var requestInfoCallCount: Int {
        state.withLock { $0.requestInfoCallCount }
    }

    internal var presentFormCallCount: Int {
        state.withLock { $0.presentFormCallCount }
    }

    // MARK: UMPBridge

    // swiftlint:disable identifier_name
    internal func requestConsentInfoUpdate() async throws {
        let err = state.withLock { (s: inout FakeUMPState) -> (any Error)? in
            s.requestInfoCallCount += 1
            return s.requestInfoError
        }
        if let err { throw err }
    }

    internal func isConsentFormRequired() async -> Bool {
        state.withLock { $0.consentRequired }
    }

    internal func loadAndPresentConsentFormIfRequired() async throws {
        let err = state.withLock { (s: inout FakeUMPState) -> (any Error)? in
            s.presentFormCallCount += 1
            return s.presentFormError
        }
        if let err { throw err }
    }
    // swiftlint:enable identifier_name
}
