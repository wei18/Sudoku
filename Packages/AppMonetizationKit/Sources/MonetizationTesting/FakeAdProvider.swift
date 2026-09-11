public import MonetizationCore

// MARK: - ScriptedAdProviderState

/// Pre-loaded behavior for `FakeAdProvider`. Each call to `bannerStatus`
/// consumes the next status in `statusSequence` (last value sticks); each
/// `refreshBanner()` advances the cursor explicitly as well.
public struct ScriptedAdProviderState: Sendable {
    public var statusSequence: [AdBannerStatus]
    public var initializeThrows: (any Error)?
    public var refreshThrows: (any Error)?

    public init(
        statusSequence: [AdBannerStatus] = [.notInitialized],
        initializeThrows: (any Error)? = nil,
        refreshThrows: (any Error)? = nil
    ) {
        self.statusSequence = statusSequence
        self.initializeThrows = initializeThrows
        self.refreshThrows = refreshThrows
    }
}

// MARK: - FakeAdProvider

public actor FakeAdProvider: AdProvider {
    private var scripted: ScriptedAdProviderState
    private var cursor: Int = 0
    public private(set) var initializeCallCount: Int = 0
    public private(set) var refreshCallCount: Int = 0
    /// Handles passed to `dispose(handle:)`, in call order, for test assertions.
    public private(set) var disposedHandles: [AdBannerHandle] = []
    private nonisolated let readiness: ReadinessLatch

    /// - Parameter readinessHeld: `true` makes `awaitReady()` suspend until
    ///   `markReady()` — for tests that must prove a caller waits for provider
    ///   readiness. `refreshBanner()` deliberately does NOT wait on it, so a
    ///   caller that skips `awaitReady()` shows up in `refreshCallCount`.
    public init(
        scripted: ScriptedAdProviderState = ScriptedAdProviderState(),
        readinessHeld: Bool = false
    ) {
        self.scripted = scripted
        self.readiness = ReadinessLatch(isOpen: !readinessHeld)
    }

    /// Releases a `readinessHeld` fake. Idempotent; readiness never re-closes.
    public nonisolated func markReady() {
        readiness.open()
    }

    public func script(_ scripted: ScriptedAdProviderState) {
        self.scripted = scripted
        self.cursor = 0
    }

    // MARK: AdProvider

    public var bannerStatus: AdBannerStatus {
        get async {
            guard !scripted.statusSequence.isEmpty else { return .notInitialized }
            let index = min(cursor, scripted.statusSequence.count - 1)
            return scripted.statusSequence[index]
        }
    }

    public func initialize() async throws {
        initializeCallCount += 1
        if let error = scripted.initializeThrows { throw error }
    }

    public func awaitReady() async throws {
        try await readiness.wait()
    }

    public func refreshBanner() async throws {
        refreshCallCount += 1
        if let error = scripted.refreshThrows { throw error }
        // Advance status cursor on successful refresh.
        if cursor + 1 < scripted.statusSequence.count {
            cursor += 1
        }
    }

    public func dispose(handle: AdBannerHandle) async {
        disposedHandles.append(handle)
    }
}
