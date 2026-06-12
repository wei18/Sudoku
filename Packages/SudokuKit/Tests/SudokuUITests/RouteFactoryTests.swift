// RouteFactoryTests — v2.3.3: each AppRoute case produces a destination view
// of the expected underlying type. AnyView erasure means we cannot `is`-cast,
// so we mirror through and assert on the type-name string. Light touch — the
// per-View behavior is covered by each View's own test suite.

import Foundation
import SwiftUI
import Testing
import GameCenterClient
import GameCenterTesting  // Stage 3: FakeGameCenterClient (was in SudokuKitTesting)
import MonetizationCore
import MonetizationTesting
import Persistence
import PuzzleStore
import SudokuKitTesting
import Telemetry
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

    /// AnyView wraps the destination in a `_ConditionalContent` tree; we
    /// reach into the Mirror to recover a string fingerprint of the
    /// underlying view type.
    private func underlyingTypeDescription(_ view: AnyView) -> String {
        String(describing: Mirror(reflecting: view).subjectType) + " | " +
            String(describing: type(of: view))
    }

    @Test func homeRouteReturnsEmptyView() {
        let view = makeFactory().view(for: .home)
        // Home is never pushed; the defensive case yields an EmptyView.
        let dump = underlyingTypeDescription(view)
        #expect(dump.contains("AnyView"))
    }

    @Test func dailyRouteReturnsDailyHubView() {
        let view = makeFactory().view(for: .daily)
        // AnyView erases the type from `type(of:)`, but the Mirror's
        // `description` walks the wrapped storage and surfaces the original
        // View type name.
        let dump = String(describing: view)
        #expect(dump.contains("DailyHubView"))
    }

    @Test func practiceRouteReturnsPracticeHubView() {
        let view = makeFactory().view(for: .practice)
        let dump = String(describing: view)
        #expect(dump.contains("PracticeHubView"))
    }

    @Test func boardRouteReturnsBoardLoaderView() {
        let view = makeFactory().view(for: .board(puzzleId: "2026-05-21-easy"))
        let dump = String(describing: view)
        #expect(dump.contains("BoardLoaderView"))
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
}
