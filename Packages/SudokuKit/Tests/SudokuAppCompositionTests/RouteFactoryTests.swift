// RouteFactoryTests — v2.3.3: each AppRoute case produces a destination view
// of the expected underlying type. AnyView erasure means we cannot `is`-cast,
// so we mirror through and assert on the type-name string. Light touch — the
// per-View behavior is covered by each View's own test suite.

import Foundation
import SwiftUI
import Testing
import GameAppKit
import GameCenterClient
import GameCenterTesting  // Stage 3: FakeGameCenterClient (was in SudokuKitTesting)
import GameShellUI
import MonetizationCore
import MonetizationTesting
import Persistence
import SudokuPersistence
import SudokuKitTesting
import Telemetry
// #639: LiveRouteFactory moved here from SudokuUI; these tests followed it.
@testable import SudokuAppComposition
@testable import SudokuUI

@MainActor
@Suite("RouteFactory — AppRoute → View mapping")
struct RouteFactoryTests {

    private func makeFactory() -> LiveRouteFactory {
        let adGateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        return LiveRouteFactory(
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: []),
            adProvider: FakeAdProvider(),
            iapClient: FakeIAPClient(),
            adGate: AdGate(store: adGateStore)
        )
    }

    @Test func boardRouteReturnsBoardLoaderView() {
        let view = makeFactory().view(for: .board(puzzleId: "2026-05-21-easy"))
        let dump = String(describing: view)
        #expect(dump.contains("BoardLoaderView"))
    }

    // MARK: - #491 modal vs push context

    /// #491: with `onPresentBoard` wired, calling `view(for:path:nil)` (the modal
    /// path used by GameRoot's fullScreenCover) must return the real board view,
    /// not the zero-content `GameBoardRedirect`.
    @Test func boardRouteWithOnPresentBoardAndNilPathReturnsBoardLoader() {
        var presented: AppRoute?
        let adGateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        let factory = LiveRouteFactory(
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: []),
            adProvider: FakeAdProvider(),
            iapClient: FakeIAPClient(),
            adGate: AdGate(store: adGateStore),
            onPresentBoard: { presented = $0 }
        )
        let view = factory.view(for: .board(puzzleId: "2026-05-21-easy"), path: nil)
        let dump = String(describing: view)
        // Modal context (path: nil) must render the real board, not the redirect.
        #expect(dump.contains("BoardLoaderView"), "Expected BoardLoaderView but got: \(dump)")
        // onPresentBoard must NOT have been invoked from this factory call.
        #expect(presented == nil)
    }

    /// #491: with `onPresentBoard` wired, calling `view(for:path:<non-nil>)` (the
    /// push context used by a tab's `.navigationDestination`) must still
    /// return the `GameBoardRedirect` so the stack→modal hand-off fires.
    @Test func boardRouteWithOnPresentBoardAndNonNilPathReturnsRedirect() {
        let adGateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        var path: [AppRoute] = [.board(puzzleId: "2026-05-21-easy")]
        let binding = Binding<[AppRoute]>(get: { path }, set: { path = $0 })
        let factory = LiveRouteFactory(
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: []),
            adProvider: FakeAdProvider(),
            iapClient: FakeIAPClient(),
            adGate: AdGate(store: adGateStore),
            onPresentBoard: { _ in }
        )
        let view = factory.view(for: .board(puzzleId: "2026-05-21-easy"), path: binding)
        let dump = String(describing: view)
        // Push context (path: non-nil) must get the redirect so the modal fires.
        #expect(dump.contains("GameBoardRedirect"), "Expected GameBoardRedirect but got: \(dump)")
    }

    @Test func completionRouteReturnsCompletionView() {
        let view = makeFactory().view(for: .completion(puzzleId: "p1", elapsedSeconds: 60, mistakeCount: 0))
        let dump = String(describing: view)
        #expect(dump.contains("CompletionView"))
    }

    @Test func settingsRouteReturnsSettingsView() {
        let view = makeFactory().view(for: .settings)
        let dump = String(describing: view)
        #expect(dump.contains("SettingsView"))
    }

    // MARK: - #1020: makeTabRoot (Today / Practice / Progress)

    /// #1020: `daily` / `practice` / `stats` stopped being ROUTES this factory
    /// resolves and became tab identities instead — `SudokuAppComposition
    /// .makeTabRoot` is what `GameConfig.makeTabRoot` calls for each of the
    /// three tabs. Pins that every tab yields a real (non-empty) view.
    @Test func makeTabRootYieldsViewForEachTab() {
        let adGateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        let rootViewModel = GameRootViewModel<AppRoute>(
            gameCenter: FakeGameCenterClient(),
            persistence: FakePersistence()
        )
        for tab in AppTab.allCases {
            let view = SudokuAppComposition.makeTabRoot(
                tab: tab,
                puzzleProvider: FakePuzzleProvider(),
                persistence: FakePersistence(),
                errorReporter: NoopErrorReporter(),
                telemetry: Telemetry(sinks: []),
                adProvider: FakeAdProvider(),
                adGate: AdGate(store: adGateStore),
                rootViewModel: rootViewModel
            )
            let dump = String(describing: view)
            #expect(!dump.isEmpty, "tab \(tab) should produce a non-empty view")
        }
    }
}
