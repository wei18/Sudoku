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

    public init(scripted: ScriptedAdProviderState = ScriptedAdProviderState()) {
        self.scripted = scripted
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

    public func refreshBanner() async throws {
        refreshCallCount += 1
        if let error = scripted.refreshThrows { throw error }
        // Advance status cursor on successful refresh.
        if cursor + 1 < scripted.statusSequence.count {
            cursor += 1
        }
    }
}
