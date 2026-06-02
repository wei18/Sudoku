// Live + Preview composition for MinesweeperAppComposition.
//
// Mirrors Sudoku's split (`AppComposition/Live.swift` + `Preview.swift`)
// collapsed into one file — the Minesweeper bag is small enough that
// Phase 2 doesn't justify a second file. Will split when monetization /
// persistence wiring lands.
//
// `.live()` wires:
//   - `Telemetry(sinks: [OSLogSink, NoOpTrackingSink])` — OSLog subsystem
//     `com.wei18.minesweeper`, category `Telemetry`. Mirror of Sudoku's
//     pattern, swapped subsystem string. MetricKit sink intentionally NOT
//     installed yet — Minesweeper has no diagnostic surface yet.
//   - `LiveErrorReporter(telemetry:)` — same shape as Sudoku.
//
// `.preview()` / `.tests()` wire empty-sinks `Telemetry` + `NoopErrorReporter`
// for zero-IO SwiftUI previews and unit tests.

internal import Telemetry

extension MinesweeperAppComposition {

    /// Production wiring. Constructs `Telemetry` fan-out + `LiveErrorReporter`
    /// over `LiveRouteFactory()`. Expands once Persistence / Monetization /
    /// GameCenter land for Minesweeper.
    public static func live() -> MinesweeperAppComposition {
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.minesweeper", category: "Telemetry"),
            NoOpTrackingSink()
        ])
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)
        return MinesweeperAppComposition(
            routeFactory: LiveRouteFactory(),
            telemetry: telemetry,
            errorReporter: errorReporter
        )
    }

    /// Preview / test wiring. Empty-sinks `Telemetry` + `NoopErrorReporter`
    /// guarantee zero-IO so SwiftUI Previews and unit tests don't touch
    /// OSLog or any external sink.
    public static func preview() -> MinesweeperAppComposition {
        MinesweeperAppComposition(
            routeFactory: LiveRouteFactory(),
            telemetry: Telemetry(sinks: []),
            errorReporter: NoopErrorReporter()
        )
    }
}
