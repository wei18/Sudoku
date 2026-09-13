import Foundation
import os
import SwiftUI
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
    var loadGate: ReadinessLatch?
    var startCallCount: Int = 0
    var loadCallCount: Int = 0
    var disposedHandles: [AdBannerHandle] = []
}

internal final class FakeAdMobBridge: AdMobBridge, @unchecked Sendable {
    private let state = OSAllocatedUnfairLock<FakeAdMobBridgeState>(initialState: .init())
    private let startGate: ReadinessLatch

    /// - Parameter startGate: `start()` records its call, then suspends until
    ///   this latch opens — lets a test hold `initialize()` in flight. Open by
    ///   default, so `start()` returns immediately.
    internal init(startGate: ReadinessLatch = ReadinessLatch(isOpen: true)) {
        self.startGate = startGate
    }

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

    /// Subsequent `loadBanner()` calls record themselves, then suspend until
    /// `gate` opens — lets a test hold a load in flight and cancel it. A
    /// cancelled wait throws `CancellationError` out of `loadBanner()`.
    internal func setLoadGate(_ gate: ReadinessLatch?) {
        state.withLock { $0.loadGate = gate }
    }

    internal var startCallCount: Int {
        state.withLock { $0.startCallCount }
    }

    internal var loadCallCount: Int {
        state.withLock { $0.loadCallCount }
    }

    internal var disposedHandles: [AdBannerHandle] {
        state.withLock { $0.disposedHandles }
    }

    // MARK: AdMobBridge

    // swiftlint:disable identifier_name
    internal func start() async throws {
        let err = state.withLock { (s: inout FakeAdMobBridgeState) -> (any Error)? in
            s.startCallCount += 1
            return s.startError
        }
        try await startGate.wait()
        if let err { throw err }
    }

    internal func loadBanner() async throws -> AdBannerHandle {
        let (err, handle, gate) = state.withLock { s in
            s.loadCallCount += 1
            return (s.loadError, s.nextHandle, s.loadGate)
        }
        if let gate { try await gate.wait() }
        if let err { throw err }
        return handle
    }
    // swiftlint:enable identifier_name

    internal func dispose(handle: AdBannerHandle) async {
        state.withLock { $0.disposedHandles.append(handle) }
    }

    // #441: the fake serves no real ad, so there is no view to host. Returning
    // nil exercises the `BannerSlotView` "loaded-but-no-host" fallback path
    // (the slot renders nothing inside the rect rather than a placeholder).
    @MainActor
    internal func bannerView(for handle: AdBannerHandle) -> AnyView? {
        nil
    }
}
