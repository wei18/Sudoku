// MinesweeperAppComposition — DI composition root for the Minesweeper app.
//
// Standard tier (2026-06-02) wires:
//   - `RouteFactory<AppRoute>` — destination construction.
//   - `Telemetry` — fan-out facade (OSLog + NoOp tracking in `.live()`).
//   - `ErrorReporter` — unified swallowed-error funnel.
//
// MS monetization wire Phase 3 (2026-06-03) adds:
//   - `persistence` — `LivePersistence(ckConfig: .minesweeper, ...)`
//   - `iapClient` — `LiveStoreKit2IAPClient(knownProductIds: [...remove_ads])`
//   - `adProvider` — `LiveAdMobAdProvider` on iOS / `NoopAdProvider` on
//     macOS (wired in U15 2026-06-03)
//   - `adGate` + `monetizationStateStore` — same shape as Sudoku
//   - `monetizationController` — MS productId via parameterized init
//   - `toastController` — shared toast surface (wired to MinesweeperRoot
//     via `.toastOverlay` since U15 / PR #263)
//
// GameCenter remains unwired — no MS Game Center surface designed yet.
//
// Public surface:
//
//   - `MinesweeperAppComposition.live()`    — production bag (Live.swift).
//   - `MinesweeperAppComposition.preview()` — Preview / test fakes (Live.swift).
//
// The App target reads `bag.rootView` and hands it to `WindowGroup`.

public import SwiftUI
public import GameShellUI
public import MinesweeperUI
public import Telemetry
public import Persistence
public import MonetizationCore
public import MonetizationUI

/// ASC product ID for Minesweeper's "Remove Ads" non-consumable. Mirrors
/// `removeAdsProductId` (Sudoku) — distinct here so the two apps' ASC
/// catalogs never collide. Held as a `public let` so future MS tests can
/// import the same symbol the way Sudoku tests import `removeAdsProductId`.
public let minesweeperRemoveAdsProductId: String = "com.wei18.minesweeper.iap.remove_ads"

@MainActor
public struct MinesweeperAppComposition {
    public let routeFactory: any RouteFactory<AppRoute>
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter
    // MS monetization wire Phase 3 (2026-06-03). Order matches Sudoku's
    // `AppComposition` for grep parity.
    public let persistence: any PersistenceProtocol
    public let adProvider: any AdProvider
    public let iapClient: any IAPClient
    public let adGate: AdGate
    public let monetizationStateStore: any AdGateStateStore
    public let monetizationController: MonetizationStateController
    public let toastController: ToastController

    public init(
        routeFactory: any RouteFactory<AppRoute>,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter,
        persistence: any PersistenceProtocol,
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationStateStore: any AdGateStateStore,
        monetizationController: MonetizationStateController,
        toastController: ToastController
    ) {
        self.routeFactory = routeFactory
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.persistence = persistence
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationStateStore = monetizationStateStore
        self.monetizationController = monetizationController
        self.toastController = toastController
    }

    /// Convenience accessor — constructs the top-level `MinesweeperRoot` view
    /// bound to this composition's `routeFactory`. The App target just calls
    /// `composition.rootView` inside its `WindowGroup`.
    public var rootView: some View {
        MinesweeperRoot(
            routeFactory: routeFactory,
            toastController: toastController
        )
        // #278 Tier-1 Phase 2b: inject Minesweeper's concrete palette at the
        // composition root. GameShellUI's `\.theme` default is a palette-neutral
        // fallback (NOT any app's brand), so every mounted MS view resolves the
        // slate-blue / blueprint-paper tokens here. Mirrors Sudoku's
        // `AppComposition.rootView` (`.environment(\.theme, DefaultTheme())`).
        .environment(\.theme, MinesweeperTheme())
        // Board-cell tokens are MS-shaped, so they ride their own `\.minesweeperCell`
        // env key (out of the generic `Theme`, same split as `\.sudokuCell`).
        .environment(\.minesweeperCell, MinesweeperTheme().cell)
    }
}
