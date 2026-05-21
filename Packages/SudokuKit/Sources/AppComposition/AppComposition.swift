// AppComposition — DI composition root (design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog / AdMob / StoreKit2 wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// the bag's properties and hands them to `RootView`.
//
// Stored shape (v2.3.3):
//   - `rootViewModel` + `routeFactory` are what `RootView.init` reads.
//   - The remaining protocol deps (puzzleProvider / persistence / gameCenter
//     / telemetry / adProvider / iapClient / adGate) stay accessible on the
//     bag for callers that need direct references (e.g. App-level boot order
//     in v2.3.7, individual destination views that escape the RouteFactory
//     such as HomeView's Game Center modal callback in v2.3.4-6).

internal import Foundation
public import GameCenterClient
public import MonetizationCore
public import Persistence
public import PuzzleStore
public import SudokuUI
public import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let routeFactory: any RouteFactory
    public let puzzleProvider: any PuzzleProviderProtocol
    public let persistence: any PersistenceProtocol
    public let gameCenter: any GameCenterClient
    public let telemetry: Telemetry
    // v2 monetization deps. v2.3.4-6 read these directly from individual Views
    // (banner slot, IAP CTAs, restore button); v2.3.7 reads them to drive the
    // UMP → ATT → AdMob boot sequence.
    public let adProvider: any AdProvider
    public let iapClient: any IAPClient
    public let adGate: AdGate

    public init(
        rootViewModel: RootViewModel,
        routeFactory: any RouteFactory,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry,
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate
    ) {
        self.rootViewModel = rootViewModel
        self.routeFactory = routeFactory
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
    }
}
