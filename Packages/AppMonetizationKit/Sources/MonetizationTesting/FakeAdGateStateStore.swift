public import MonetizationCore

// MARK: - FakeAdGateStateStore

/// In-memory `AdGateStateStore` for unit tests. Call `script(_:)` to seed the
/// initial state; subsequent `loadState()` / `saveState(_:)` calls are
/// counted via `loadCallCount` / `saveCallCount`.
public actor FakeAdGateStateStore: AdGateStateStore {
    private var state: AdGateState?
    private var loadError: (any Error)?
    private var saveError: (any Error)?

    public private(set) var loadCallCount: Int = 0
    public private(set) var saveCallCount: Int = 0

    public init(initial: AdGateState? = nil) {
        self.state = initial
    }

    // MARK: Scripting API

    public func script(_ initial: AdGateState) {
        self.state = initial
    }

    public func scriptLoadError(_ error: any Error) {
        self.loadError = error
    }

    public func scriptSaveError(_ error: any Error) {
        self.saveError = error
    }

    /// Read the current persisted state without bumping `loadCallCount`.
    /// Use this in tests to assert "did `saveState` actually land".
    public func peekState() -> AdGateState? {
        state
    }

    // MARK: AdGateStateStore

    public func loadState() async throws -> AdGateState {
        loadCallCount += 1
        if let error = loadError { throw error }
        guard let state else {
            throw FakeAdGateStateStoreError.notSeeded
        }
        return state
    }

    public func saveState(_ state: AdGateState) async throws {
        saveCallCount += 1
        if let error = saveError { throw error }
        self.state = state
    }
}

public enum FakeAdGateStateStoreError: Error, Equatable {
    case notSeeded
}
