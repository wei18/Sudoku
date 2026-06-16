// DailyHubViewOwnershipTests — #536 VM ownership regression.
//
// Root cause: `DailyHubView` stored the injected VM via `@Bindable` (a direct
// property assignment). When SwiftUI's `.navigationDestination` closure
// re-invoked `view(for:)` during an AdMob banner WebView load, the factory
// minted a FRESH `.idle` VM and passed it to the view. Because `@Bindable`
// is a plain stored property (not @State), the view swapped in the new idle
// instance. Since SwiftUI kept the same view identity, `.task { bootstrap() }`
// did NOT re-fire — so the new VM stayed `.idle` forever (infinite spinner).
//
// Fix: `DailyHubView.init` stores the VM via `@State(wrappedValue:)`. SwiftUI's
// @State first-value-wins semantics mean the FIRST bootstrapped VM is retained
// for the navigation entry's lifetime; subsequent factory calls that mint new
// idle VMs are ignored by SwiftUI.
//
// Tests here live at the model seam — no ViewInspector, no SwiftUI hosting.
// They assert the invariants that make the @State fix correct:
//
// 1. A bootstrapped VM retains `.loaded` state — identity and state are stable.
// 2. A freshly-minted VM (what the factory produces on re-render) starts `.idle`.
// 3. The two are DISTINCT objects (ObjectIdentifier differs).
//    The view's @State keeps VM₁; VM₂ is the "would-have-replaced-it" object
//    that @State now ignores.
// 4. The `hasBootstrapped` latch guards against double-bootstrap on the same
//    instance (belt-and-suspenders with @State).

import Foundation
import Testing
@testable import SudokuUI

import Persistence
import PuzzleStore
import SudokuKitTesting

@MainActor
@Suite("DailyHubView — VM ownership / @State retention (#536)")
struct DailyHubViewOwnershipTests {

    nonisolated(unsafe) private static let fixedDate = Date(timeIntervalSince1970: 1_715_000_000)

    // MARK: - Core regression invariant

    /// Core regression test for #536.
    ///
    /// Pre-fix scenario (the bug):
    ///   1. Factory mints VM₁ → view renders, .task fires, VM₁ bootstraps to .loaded.
    ///   2. Re-render → factory mints VM₂ (fresh, .idle). View's @Bindable var is
    ///      reassigned to VM₂. SwiftUI keeps the same view identity, so .task does
    ///      NOT re-fire. VM₂ stays .idle → infinite spinner.
    ///
    /// Post-fix invariant (asserted here):
    ///   • VM₁ (bootstrapped) retains `.loaded` — its identity and state are stable.
    ///   • VM₂ (factory re-mint) starts `.idle` — this is the replaced-and-orphaned
    ///     object that @State must prevent the view from binding to.
    ///   • The two are DISTINCT objects (ObjectIdentifier differs).
    ///
    /// Note: this test will PASS both before AND after the fix (the model-level
    /// behavior is unchanged — a newly-constructed VM always starts .idle and the
    /// bootstrapped VM always stays .loaded). Its purpose is to document and
    /// permanently pin the invariants the @State change relies on. A regression
    /// that caused a bootstrapped VM to reset on unrelated construction of another
    /// VM would fail here.
    @Test func bootstrappedVMRetainsLoadedWhileFreshMintStartsIdle() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(
            .success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate))
        )
        let persistence = FakePersistence()

        // VM₁: bootstrapped — what the view holds after the first render cycle.
        let vm1 = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
        await vm1.bootstrap()
        guard case .loaded(let cards) = vm1.state else {
            Issue.record("expected .loaded after bootstrap, got \(vm1.state)")
            return
        }
        #expect(cards.count == 3)

        // VM₂: fresh re-mint — what the factory produces on a re-render.
        // In the pre-fix world this replaced VM₁ via @Bindable reassignment.
        let vm2 = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )

        // VM₂ must start .idle — the state that caused the bug when @Bindable
        // swapped VM₁ out for VM₂ without re-firing .task.
        #expect(vm2.state == .idle,
                "factory-minted VM must start .idle; @State must prevent its use")

        // The two objects are distinct — @State must keep VM₁, not VM₂.
        #expect(
            ObjectIdentifier(vm1) != ObjectIdentifier(vm2),
            "bootstrapped and re-minted VMs are distinct objects"
        )

        // VM₁ must still report .loaded — construction of VM₂ must not affect it.
        // This is the invariant that makes @State first-value-wins the correct fix.
        #expect(
            vm1.state == .loaded(cards),
            "bootstrapped VM retains .loaded after factory mints a second idle VM"
        )
    }

    // MARK: - hasBootstrapped latch: belt-and-suspenders with @State

    /// If @State correctly retains the first VM, SwiftUI keeps that instance alive
    /// across re-renders. The `hasBootstrapped` latch then guards against double-
    /// bootstrap if `.task` fires again for any reason (e.g. view re-attachment).
    @Test func bootstrappedVMIgnoresSecondBootstrapCall() async {
        let provider = FakePuzzleProvider()
        await provider.setDailyTrioResult(
            .success(FakePuzzleProvider.defaultDailyTrio(date: Self.fixedDate))
        )
        let persistence = FakePersistence()

        let viewModel = DailyHubViewModel(
            provider: provider,
            persistence: persistence,
            dateProvider: { Self.fixedDate }
        )
        await viewModel.bootstrap()
        guard case .loaded = viewModel.state else {
            Issue.record("expected .loaded after bootstrap, got \(viewModel.state)")
            return
        }

        // Second bootstrap call — simulates .task re-firing.
        // The hasBootstrapped latch must preserve .loaded, not reset to .idle.
        await viewModel.bootstrap()

        guard case .loaded(let cards) = viewModel.state else {
            Issue.record("second bootstrap must not reset state; got \(viewModel.state)")
            return
        }
        #expect(cards.count == 3, "second bootstrap must be a no-op on a loaded VM")

        let providerOps = await provider.operations
        #expect(providerOps.count == 1, "fetchDailyTrio must be called exactly once")
    }
}
