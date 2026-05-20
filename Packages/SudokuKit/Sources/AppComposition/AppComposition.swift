// AppComposition — DI composition root (design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog production wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// the bag's properties and hands them to `RootView`.
//
// Stored fields beyond `rootViewModel` exist so `RootView.destination`
// (issue #45) can construct downstream VMs inline. They mirror the
// dependencies `RootViewModel` already holds internally — re-exposing
// them here keeps the App layer free of any direct CloudKit/GameKit
// references.

internal import Foundation
public import GameCenterClient
public import Persistence
public import PuzzleStore
public import SudokuUI
public import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let puzzleProvider: any PuzzleProviderProtocol
    public let persistence: any PersistenceProtocol
    public let gameCenter: any GameCenterClient
    public let telemetry: Telemetry

    public init(
        rootViewModel: RootViewModel,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry
    ) {
        self.rootViewModel = rootViewModel
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
    }
}
