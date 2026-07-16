// SettingsView / SettingsViewModel — #832 mirror-principle unification.
//
// The Settings wrapper (Form assembly config + `.task` bootstrap side-effects)
// and its view model used to be hand-written per app; Sudoku carried a
// `SettingsViewModel`-driven bootstrap Minesweeper's copy lacked, and the two
// otherwise-identical `SettingsView` structs had structurally diverged. Both
// now live once in `GameAppKit` (the "shared composition, deps allowed" layer
// — SettingsKit/GameShellKit stay zero/near-zero-dep and cannot host the
// `Persistence`/`MonetizationUI`/`GameCenterClient` surface this wrapper
// needs). These typealiases keep `SudokuUI.SettingsView(...)` /
// `SudokuUI.SettingsViewModel(...)` call sites (production + tests)
// unqualified and source-compatible.
public import GameAppKit
public import SwiftUI

public typealias SettingsView<Banner: View> = GameAppKit.SettingsView<Banner>
public typealias SettingsViewModel = GameAppKit.SettingsViewModel
