// swiftlint:disable identifier_name

import Foundation
import os
@testable import AdsAdMob
import MonetizationCore

// MARK: - FakeAdMobBridge
//
// Test seam mirroring `FakeStoreKitBridge` from `IAPStoreKit2Tests` (v2.1) but
// using `OSAllocatedUnfairLock` instead of `NSLock` — strict concurrency
// (Swift 6) forbids `NSLock.lock()` from async contexts; OSAllocatedUnfairLock
// is the documented async-safe scoped-locking equivalent.

internal struct FakeAdMobBridgeState: Sendable {
    var startError: (any Error)?
    var loadError: (any Error)?
    var nextHandle: AdBannerHandle = .init()
    var cachedStatus: AdBannerStatus = .notInitialized
    var startCallCount: Int = 0
    var loadCallCount: Int = 0
}

internal final class FakeAdMobBridge: AdMobBridge, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<FakeAdMobBridgeState>(initialState: .init())

    internal init() {}

    // MARK: Scripting API

    internal func setStartError(_ error: (any Error)?) {
        state.withLock { $0.startError = error }
    }

    internal func setLoadError(_ error: (any Error)?) {
        state.withLock { $0.loadError = error }
    }

    internal func setNextHandle(_ handle: AdBannerHandle) {
        state.withLock { $0.nextHandle = handle }
    }

    internal func setCachedStatus(_ status: AdBannerStatus) {
        state.withLock { $0.cachedStatus = status }
    }

    internal var startCallCount: Int {
        state.withLock { $0.startCallCount }
    }

    internal var loadCallCount: Int {
        state.withLock { $0.loadCallCount }
    }

    // MARK: AdMobBridge

    internal func start() async throws {
        let err = state.withLock { (s: inout FakeAdMobBridgeState) -> (any Error)? in
            s.startCallCount += 1
            return s.startError
        }
        if let err { throw err }
        setCachedStatus(.loading)
    }

    internal func loadBanner() async throws -> AdBannerHandle {
        let (err, handle) = state.withLock { (s: inout FakeAdMobBridgeState) -> ((any Error)?, AdBannerHandle) in
            s.loadCallCount += 1
            return (s.loadError, s.nextHandle)
        }
        if let err { throw err }
        setCachedStatus(.loaded(handle))
        return handle
    }

    internal func currentBannerStatus() async -> AdBannerStatus {
        state.withLock { $0.cachedStatus }
    }
}
