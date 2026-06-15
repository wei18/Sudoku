// Game2048AppComposition — DI composition root for the Tiles2048 app.
//
// SDD-004 Milestone 2: skeleton only. Wires the minimal surface needed to
// boot the stub Home shell. Full wiring (monetization, persistence, Game
// Center, audio) mirrors MinesweeperAppComposition and lands in Milestone 3.
//
// Milestone 3 will add:
//   - `persistence`: LivePersistence(ckConfig: .tiles2048, ...)
//   - `iapClient`: LiveStoreKit2IAPClient(knownProductIds: [...remove_ads])
//   - `adProvider`: LiveAdMobAdProvider (iOS) / NoopAdProvider (macOS)
//   - `adGate` + `monetizationStateStore` + `monetizationController`
//   - `toastController`: shared toast surface (mirroring MS §U15)
//   - `gameCenter`: LiveGameCenterClient(authDriver: GKAuthDriver())
//   - `routeFactory`: LiveRouteFactory<AppRoute> wired into Game2048Root
//   - `rootViewModel`: GameRootViewModel<AppRoute> (GameAppKit typealias)
//   - Theme: Game2048Theme injected at `.environment(\.theme, ...)`
//
// Public surface:
//   - `Game2048AppComposition.live()` — production bag (mirrors MS Live.swift)
//   - `Game2048AppComposition.preview()` — Preview/test fakes (M3)

public import SwiftUI
public import Telemetry
internal import Game2048UI
internal import GameShellUI

/// ASC product ID for Tiles2048's "Remove Ads" non-consumable.
/// Mirrors `minesweeperRemoveAdsProductId` — distinct so the two apps'
/// ASC catalogs never collide. Held as `public let` so future tests can
/// import the same symbol (same precedent as SudokuKit / MinesweeperKit).
/// M3: wire into LiveStoreKit2IAPClient(knownProductIds: [tiles2048RemoveAdsProductId]).
public let tiles2048RemoveAdsProductId: String = "com.wei18.tiles2048.iap.remove_ads"

@MainActor
public struct Game2048AppComposition {
    // M3: add routeFactory, gameCenter, persistence, adProvider, iapClient,
    // adGate, monetizationStateStore, monetizationController, toastController
    // mirroring MinesweeperAppComposition field-for-field.
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter

    public init(
        telemetry: Telemetry,
        errorReporter: any ErrorReporter
    ) {
        self.telemetry = telemetry
        self.errorReporter = errorReporter
    }

    /// Convenience accessor — constructs the top-level `Game2048Root` view.
    /// The App target calls `composition.rootView` inside its `WindowGroup`.
    /// M3: will inject routeFactory + toastController + adProvider + adGate
    /// + monetizationController, matching `MinesweeperAppComposition.rootView`.
    public var rootView: some View {
        Game2048Root()
        // M3: .environment(\.theme, Game2048Theme())
    }
}

// MARK: - Factory methods

public extension Game2048AppComposition {
    /// Production composition bag. M3 will construct all Live seams here.
    static func live() -> Game2048AppComposition {
        let telemetry = Telemetry(sinks: [
            OSLogSink(subsystem: "com.wei18.tiles2048", category: "Telemetry"),
            NoOpTrackingSink(),
        ])
        let errorReporter: any ErrorReporter = LiveErrorReporter(telemetry: telemetry)
        return Game2048AppComposition(
            telemetry: telemetry,
            errorReporter: errorReporter
        )
    }

    /// Preview / test fakes bag. M3 will wire all Noop/Fake seams here.
    static func preview() -> Game2048AppComposition {
        let telemetry = Telemetry(sinks: [NoOpTrackingSink()])
        let errorReporter: any ErrorReporter = NoopErrorReporter()
        return Game2048AppComposition(
            telemetry: telemetry,
            errorReporter: errorReporter
        )
    }
}
