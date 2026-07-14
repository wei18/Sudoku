// LiveRouteFactory+Stats — the `.stats` destination (#773).
//
// Split into its own file purely to keep LiveRouteFactory.swift under the
// 400-line `file_length` lint ceiling (same rationale as
// `MinesweeperGameViewModel+SubmitOnWin.swift`) — this is the same route
// table, not a separate concern. The factory's stored deps are `private`
// (file-scoped), so the switch passes them in rather than the extension
// reading them.
//
// #773: Statistics screen — MinesweeperPersonalRecord readout, pushed from
// the Home secondary entry. No banner: the proposal's scope note (§7)
// introduces no monetization surface here. Mirrors Sudoku's `.stats` case.

public import SwiftUI
internal import MinesweeperPersistence
internal import MinesweeperUI
internal import Telemetry

extension LiveRouteFactory {
    @MainActor
    // Unlabeled params: the single call site (the `.stats` switch case) keeps
    // to one line under the caller file's 400-line `file_length` ceiling.
    static func statsDestination(
        _ store: MinesweeperPersonalRecordStore?,
        _ errorReporter: (any ErrorReporter)?,
        _ telemetry: Telemetry?
    ) -> AnyView {
        AnyView(
            MinesweeperStatsView(
                viewModel: MinesweeperStatsViewModel(
                    store: store,
                    errorReporter: errorReporter,
                    telemetry: telemetry
                )
            )
        )
    }
}
