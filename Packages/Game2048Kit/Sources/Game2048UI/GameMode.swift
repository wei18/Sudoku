// GameMode — coarse 2048 game-mode classification (daily vs practice).
//
// Mirrors MinesweeperKit/GameMode.swift verbatim. A per-game leaf enum keeps
// the cross-package coupling out while preserving the daily/practice semantics.
//
// M4: if GameMode is ever promoted to a shared module (GameShellKit or
// GameAppKit), this file is deleted and replaced with an import.

public enum GameMode: String, Sendable, Equatable, Hashable, CaseIterable {
    case daily
    case practice
}
