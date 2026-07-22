// UITestFaultingPuzzleProvider — #935 batch 2, DEBUG-only fault injection for
// `PuzzleProviderProtocol`, gated by `-uitest-puzzle-fault <mode>`
// (`GameAppKit.UITestLaunchArg.puzzleFault`). Wraps the live `PuzzleStore` and
// overrides exactly the one call the requested mode needs to fail; every
// other call delegates to the wrapped live provider unchanged.
//
// Lets the E2E suite deterministically drive the Sudoku-only N3 (Practice
// draw failure), N4 (Daily `.exhausted`), and N5 (Daily `.failed`) negative
// flows in docs/navigation-flows.md §4 — Sudoku's `PuzzleStore` is a live
// generator, so there is no reliable way to force these outcomes from a real
// fetch on demand (mirrors the `-uitest-loader-fail` rationale for N1/N2).
// Absent from Release builds via the `#if DEBUG` guard.

internal import Foundation
internal import SudokuEngine
internal import SudokuPersistence
#if DEBUG
internal import GameAppKit
#endif

#if DEBUG

/// The fault mode selected via `-uitest-puzzle-fault <mode>`.
enum UITestPuzzleFaultMode: String {
    /// N3: `fetchPracticePool` throws a generic error → `PracticeHubViewModel`
    /// lands in `.failed(reason)` (`PracticeHubViewModel.swift:94-96`).
    case practiceFail
    /// N4: `fetchDailyTrio` throws `PuzzleStoreError.generatorFailed` →
    /// `DailyHubViewModel` lands in `.exhausted` (`DailyHubViewModel.swift:138-141`).
    case dailyExhausted
    /// N5: `fetchDailyTrio` throws a generic (non-`generatorFailed`) error →
    /// `DailyHubViewModel` lands in `.failed(reason)` (`DailyHubViewModel.swift:142-149`).
    case dailyFail
}

/// Generic error thrown by the `practiceFail` / `dailyFail` modes — anything
/// that is NOT `PuzzleStoreError.generatorFailed`, so `DailyHubViewModel`'s
/// `onPhase1Error` branch takes the `.failed` path rather than `.exhausted`.
struct UITestPuzzleFaultError: Error, Sendable {}

/// Wraps a live `PuzzleProviderProtocol` and overrides one call per fault
/// mode. `puzzle(for:)` always delegates — no negative flow in this batch
/// exercises the reverse-lookup path.
struct UITestFaultingPuzzleProvider: PuzzleProviderProtocol {
    private let wrapped: any PuzzleProviderProtocol
    private let mode: UITestPuzzleFaultMode

    init(wrapping wrapped: any PuzzleProviderProtocol, mode: UITestPuzzleFaultMode) {
        self.wrapped = wrapped
        self.mode = mode
    }

    func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope] {
        switch mode {
        case .dailyExhausted:
            throw PuzzleStoreError.generatorFailed(underlying: "uitest-forced-exhausted")
        case .dailyFail:
            throw UITestPuzzleFaultError()
        case .practiceFail:
            return try await wrapped.fetchDailyTrio(date: date)
        }
    }

    func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope {
        switch mode {
        case .practiceFail:
            throw UITestPuzzleFaultError()
        case .dailyExhausted, .dailyFail:
            return try await wrapped.fetchPracticePool(difficulty: difficulty)
        }
    }

    func puzzle(for puzzleId: String) async throws -> Puzzle {
        try await wrapped.puzzle(for: puzzleId)
    }
}

#endif

/// Resolves the `PuzzleProviderProtocol` `live()` wires into
/// `SudokuAppComposition` + `LiveRouteFactory`. Under `-uitest-puzzle-fault
/// <mode>` (DEBUG only), wraps `live` in `UITestFaultingPuzzleProvider` for a
/// recognized mode key; any other/missing value falls through to `live`
/// unchanged. Always defined (mirrors
/// `GameAppKit/MakeGameApp+UITestOverrides.swift`'s `resolve*` shape) so
/// `Live.swift` can call it unconditionally without its own `#if DEBUG`.
func resolvePuzzleProvider(live: any PuzzleProviderProtocol) -> any PuzzleProviderProtocol {
    #if DEBUG
    guard let value = UITestLaunchArg.puzzleFaultValue(),
          let mode = UITestPuzzleFaultMode(rawValue: value) else {
        return live
    }
    return UITestFaultingPuzzleProvider(wrapping: live, mode: mode)
    #else
    return live
    #endif
}
