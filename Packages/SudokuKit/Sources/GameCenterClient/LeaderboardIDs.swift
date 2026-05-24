// LeaderboardIDs — `LeaderboardKind → identifier string` mapping.
//
// Identifier *strings* live in `SudokuEngine/GameCenterIdentifiers.swift`
// (single source-of-truth shared with ASCRegister per issue #66 / M6).
// This file owns the kind→string mapping because `LeaderboardKind` is a
// GameCenterClient public type that SudokuEngine should not import.

internal import SudokuEngine

public enum LeaderboardIDs {

    /// Re-exported for backwards-compatible call sites; canonical source
    /// is `SudokuEngine.LeaderboardID.dailyPrefix`.
    public static let dailyPrefix = LeaderboardID.dailyPrefix
    /// Re-exported; canonical source is `SudokuEngine.LeaderboardID.versionSuffix`.
    public static let versionSuffix = LeaderboardID.versionSuffix

    public static func id(for kind: LeaderboardKind) -> String {
        switch kind {
        case .dailyEasy: return LeaderboardID.dailyEasy
        case .dailyMedium: return LeaderboardID.dailyMedium
        case .dailyHard: return LeaderboardID.dailyHard
        }
    }
}
