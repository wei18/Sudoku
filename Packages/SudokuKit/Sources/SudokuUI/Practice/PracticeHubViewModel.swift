// PracticeHubViewModel — difficulty picker + draw + shimmer threshold.
//
// Per docs/designs/04-practice-hub.md. Shimmer (.redacted) is reserved for
// generator latencies > 100ms (design-system.md §Loading & Placeholder).
// Sub-100ms operations skip any animation to avoid flash; > 500 ms would
// switch to ProgressView but the generator p95 is already < 300 ms.

public import Foundation
public import SwiftUI
public import PuzzleStore
public import SudokuEngine

public enum PracticeHubLoadingState: Sendable, Equatable {
    case idle
    /// Drawing started < 100 ms ago — no UI indicator (no flash).
    case drawingQuiet
    /// Drawing has crossed 100 ms — show shimmer.
    case drawingShimmer
    case drawn(PuzzleEnvelope)
    case failed(String)
}

@MainActor
@Observable
public final class PracticeHubViewModel {
    public var difficulty: Difficulty = .medium
    public private(set) var loadingState: PracticeHubLoadingState = .idle

    /// Private fallback storage used only when no external binding is
    /// supplied (previews / unit tests). When `RouteFactory` hoists
    /// `RootViewModel.path` and passes a `Binding` via `init(path:)`,
    /// this stays empty and `path` reads/writes through `externalPath`
    /// instead. Mirrors `HomeViewModel`'s pattern (issue #197).
    private var localPath: [AppRoute] = []

    @ObservationIgnored
    private let externalPath: Binding<[AppRoute]>?

    /// Single public view of the navigation path. Routes to the external
    /// binding when one was injected; otherwise falls back to the local
    /// stub array.
    public var path: [AppRoute] {
        get { externalPath?.wrappedValue ?? localPath }
        set {
            if let externalPath {
                externalPath.wrappedValue = newValue
            } else {
                localPath = newValue
            }
        }
    }

    private let provider: any PuzzleProviderProtocol
    private let shimmerDelayNanos: UInt64

    public init(
        provider: any PuzzleProviderProtocol,
        shimmerDelayNanos: UInt64 = 100_000_000,  // 100 ms
        path: Binding<[AppRoute]>? = nil
    ) {
        self.provider = provider
        self.shimmerDelayNanos = shimmerDelayNanos
        self.externalPath = path
    }

    /// Internal flip used by the >100 ms shimmer task so tests can assert
    /// the transition without timing flakiness.
    public func promoteToShimmer() {
        if case .drawingQuiet = loadingState {
            loadingState = .drawingShimmer
        }
    }

    /// Snapshot-test seam: set the loading state directly for deterministic
    /// rendering of intermediate states without spinning a real generator.
    public func setLoadingStateForTesting(_ state: PracticeHubLoadingState) {
        self.loadingState = state
    }

    public func drawPuzzle() async {
        loadingState = .drawingQuiet
        let shimmerTask = Task { @MainActor [weak self, shimmerDelayNanos] in
            // try?: Task.sleep cancellation is normal control flow (the
            // outer drawPuzzle's defer cancels this shimmer task once the
            // fetch resolves). M10 (issue #67) — not an error path.
            try? await Task.sleep(nanoseconds: shimmerDelayNanos)
            guard !Task.isCancelled else { return }
            self?.promoteToShimmer()
        }
        defer { shimmerTask.cancel() }

        do {
            let envelope = try await provider.fetchPracticePool(difficulty: difficulty)
            loadingState = .drawn(envelope)
        } catch {
            loadingState = .failed(String(describing: error))
        }
    }

    public func playTapped() {
        guard case .drawn(let envelope) = loadingState else { return }
        path.append(.board(puzzleId: envelope.identity.puzzleId))
    }

    /// User switched difficulty segment — clear any drawn puzzle so the
    /// "Draw new puzzle" CTA reads as primary again.
    public func selectDifficulty(_ next: Difficulty) {
        difficulty = next
        loadingState = .idle
    }
}
