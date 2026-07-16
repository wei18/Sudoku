// SettingsView / SettingsViewModel — #832 mirror-principle unification.
//
// Previously a hand-written wrapper taking primitive `version:`/`clearCache:`
// params with no view model or bootstrap task — structurally diverged from
// Sudoku's `SettingsViewModel`-driven wrapper. Both now live once in
// `GameAppKit` (see that module's `SettingsView.swift` / `SettingsViewModel.swift`
// for the full implementation + rationale). These typealiases keep
// `MinesweeperUI.SettingsView(...)` / `SettingsViewModel(...)` call sites
// (production + tests) unqualified and source-compatible.
public import GameAppKit
public import SwiftUI

public typealias SettingsView<Banner: View> = GameAppKit.SettingsView<Banner>
public typealias SettingsViewModel = GameAppKit.SettingsViewModel
