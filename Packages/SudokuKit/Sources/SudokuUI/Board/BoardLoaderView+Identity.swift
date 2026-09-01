// BoardLoaderView+Identity — pure, `self`-free helpers extracted from
// BoardLoaderView.swift (repo convention: extract a `+Feature.swift` sibling
// rather than growing the host file past SwiftLint's 400-line `file_length`
// ceiling — #1023 Phase B's `fetchStreakAdvance` plumbing pushed it over).

import Foundation
import GameAppKit
import SudokuEngine
import SudokuPersistence

extension BoardLoaderView {

    #if DEBUG
    /// #719 testable core — extracted from `load()` so a unit test can drive
    /// the `-uitest-loader-fail` hook without needing a live process launch
    /// argument. `load()` calls the no-arg overload (real
    /// `ProcessInfo.processInfo.arguments`).
    static func isLoaderFailLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(UITestLaunchArg.loaderFail)
    }
    #endif

    /// Derive `PuzzleIdentity` from `puzzleId` string.
    ///
    /// Two formats per `PuzzleIdentity` static factories:
    ///   - daily:    "YYYY-MM-DD-{difficulty}"
    ///   - practice: "practice-{base32}-{difficulty}"
    ///
    /// Difficulty is the suffix after the last `-`. If parsing fails the
    /// difficulty falls back to `.easy` so the load path still progresses;
    /// the snapshot's `puzzle.difficulty` is the authoritative value used
    /// by `BoardView` (this identity only feeds the header label).
    ///
    /// `internal` (not `private`) — moved out of `BoardLoaderView.swift`
    /// itself, so `load()` there calls this across the file boundary.
    static func identity(from puzzleId: String) -> PuzzleIdentity {
        let kind: Mode = puzzleId.hasPrefix("practice-") ? .practice : .daily
        let difficultyRaw = puzzleId.split(separator: "-").last.map(String.init) ?? Difficulty.easy.rawValue
        let difficulty = Difficulty(rawValue: difficultyRaw) ?? .easy
        return PuzzleIdentity(puzzleId: puzzleId, kind: kind, difficulty: difficulty)
    }
}
