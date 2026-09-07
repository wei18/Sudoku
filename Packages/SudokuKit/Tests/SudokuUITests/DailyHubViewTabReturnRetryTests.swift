// DailyHubViewTabReturnRetryTests — #1021 CR3b: proves the PM's binding
// condition on `DailyHubView`'s `.onChange(of: gameSelectedTab)` wiring.
//
// The read-item-6 trap this exists to rule out: `.onAppear` does NOT re-fire
// when a `fullScreenCover` dismisses (#761, `DailyHubView`'s own doc), so the
// analogous "does a lifecycle signal fire on tab return" question could NOT
// be assumed for the sidebarAdaptable TabView either — it had to be checked.
//
// `MemoizedTabRootsTests` (GameAppKitTests) already pins that `makeTabRoot`
// builds each tab's content exactly ONCE, however many times the shell
// re-renders — so `DailyHubView` is never destroyed/remounted by a tab
// switch. This file pins the other half: that reading an `@Observable`
// property change (`gameSelectedTab`) through `.onChange`, rather than
// relying on `.onAppear`'s mount detection, reliably reaches a view that
// stays mounted but goes on- and off-screen as the TabView's selection
// changes — mirroring `BoardModalOverlayHoistTests`'s
// `inPlaceBranchChangeReRegistersViaOnChange`, the established pattern in
// this repo for proving exactly this class of claim with a real
// `NSHostingView`, not just by calling view-model methods directly.

import Foundation
import SwiftUI
import Testing
@testable import SudokuUI

import GameAppKit
import GameShellUI
import Persistence
import SudokuEngine
import SudokuPersistence
import SudokuKitTesting

#if canImport(AppKit)
import AppKit

/// Mutated in place to drive `.environment(\.gameSelectedTab, probe.tab)`
/// through an already-mounted hosting view, exactly the way `GameRoot`
/// re-injects `viewModel.selectedTab` into its environment on every body
/// re-evaluation. Declared at file scope (not nested in the test function)
/// because `@Observable`'s synthesized conformance is an extension, and
/// extensions cannot attach to a type local to a function body.
@Observable
@MainActor
private final class SelectedTabProbe {
    var tab: AppTab
    init(tab: AppTab) { self.tab = tab }
}

/// Reads `probe.tab` in ITS OWN body (not the test's) so SwiftUI's
/// Observation tracking is registered against a live view in the hierarchy —
/// the same shape `BoardModalPresentationProbeHost` uses in
/// `BoardModalOverlayHoistTests`.
private struct DailyHubEnvironmentHost: View {
    let probe: SelectedTabProbe
    let daily: DailyHubView<EmptyView>

    var body: some View {
        daily.environment(\.gameSelectedTab, probe.tab)
    }
}

@MainActor
@Suite("DailyHubView — tab-return retry wiring (#1021 CR3b)")
struct DailyHubViewTabReturnRetryTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    /// One `NSHostingView` stays mounted for the WHOLE test — no second cold
    /// start — so this can only pass via the `.onChange` branch, never a
    /// fresh `.onAppear`/`.task` firing on a remount.
    @Test func onChangeOfGameSelectedTabRetriesAFailedLoadOnReturnToToday() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.malformedPuzzleId("uitest")))
        let persistence = FakePersistence()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()
        guard case .failed = viewModel.state else {
            Issue.record("expected .failed, got \(viewModel.state)")
            return
        }

        // Whatever made phase-1 fail the first time (offline, a transient CK
        // hiccup) has since cleared — the exact scenario the retry exists to
        // recover from.
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))

        let probe = SelectedTabProbe(tab: .practice)
        let host = hostingView(
            DailyHubEnvironmentHost(probe: probe, daily: DailyHubView(viewModel: viewModel)),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        host.layoutSubtreeIfNeeded()

        // Mounting alone (with Today not even the probe's current tab) must
        // not have triggered a retry.
        guard case .failed = viewModel.state else {
            Issue.record("expected .failed to survive the initial mount, got \(viewModel.state)")
            return
        }

        // The player switches back to Today — the SAME view stays mounted,
        // nothing remounts.
        probe.tab = .today
        host.layoutSubtreeIfNeeded()

        // `.onChange`'s action spawns an unstructured `Task`; give it room to run.
        for _ in 0..<200 {
            await Task.yield()
        }

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("expected .loaded after returning to Today, got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3)
    }

    /// Switching to a DIFFERENT non-Today tab must not fire a retry — the
    /// signal is scoped to a return to Today specifically.
    @Test func onChangeOfGameSelectedTabIgnoresASwitchToAnotherTab() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(.failure(.malformedPuzzleId("uitest")))
        let persistence = FakePersistence()
        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        await viewModel.bootstrap()
        await provider.setDailyTrioResult(.success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate)))

        let probe = SelectedTabProbe(tab: .today)
        let host = hostingView(
            DailyHubEnvironmentHost(probe: probe, daily: DailyHubView(viewModel: viewModel)),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        host.layoutSubtreeIfNeeded()

        probe.tab = .progress
        host.layoutSubtreeIfNeeded()
        for _ in 0..<200 {
            await Task.yield()
        }

        guard case .failed = viewModel.state else {
            Issue.record("expected .failed to persist across a switch to a non-Today tab, got \(viewModel.state)")
            return
        }
    }
}
#endif
