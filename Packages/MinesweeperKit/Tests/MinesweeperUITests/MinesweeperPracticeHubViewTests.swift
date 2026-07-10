// MinesweeperPracticeHubViewTests — compile + smoke coverage for the
// U12 Practice hub stub. Verifies the view instantiates with a binding +
// initial difficulty. Snapshot rendering deferred per X1-X4 precedent for
// MS UI; the wrapped `PracticeHubShellView` is independently pinned by
// `PracticeHubShellViewGenericityTests` in GameShellUITests.
//
// #720 G2: `difficultyBinding` is exposed `internal` (not `private`) so the
// last-selected-difficulty persistence round trip is testable directly — this
// repo's test infra has no SwiftUI render-tree introspection (`AnyView`'s
// payload isn't introspectable per `LiveRouteFactoryTests`), so driving the
// Binding is the only way to exercise the seed/persist seam without a live
// host. The composition root's concrete `LastSelectionStore` wiring is
// exercised separately in `GameAppKitTests.LastSelectionStoreTests`.

import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine

@MainActor
@Suite struct MinesweeperPracticeHubViewTests {

    @Test func instantiatesWithBinding() {
        var path: [AppRoute] = []
        let binding = Binding<[AppRoute]>(
            get: { path },
            set: { path = $0 }
        )
        let view = MinesweeperPracticeHubView(path: binding)
        _ = view
    }

    @Test func instantiatesWithEachDifficulty() {
        for difficulty in Difficulty.allCases {
            let view = MinesweeperPracticeHubView(
                path: .constant([]),
                initialDifficulty: difficulty
            )
            _ = view
        }
    }

    @Test("No initial difficulty given → defaults to Beginner (unchanged behavior)")
    func defaultsToBeginnerWhenNoInitialDifficultyGiven() {
        let view = MinesweeperPracticeHubView(path: .constant([]))
        #expect(view.difficultyBinding.wrappedValue == .beginner)
    }

    @Test("initialDifficulty seeds the difficulty binding")
    func initialDifficultySeedsBinding() {
        let view = MinesweeperPracticeHubView(path: .constant([]), initialDifficulty: .expert)
        #expect(view.difficultyBinding.wrappedValue == .expert)
    }

    @Test("changing the difficulty binding invokes the injected onDifficultyChanged callback")
    func changingBindingPersists() {
        // Note: this only asserts the callback fires — `@State` outside a
        // real SwiftUI host doesn't reliably persist across a SEPARATE
        // top-level re-read of `difficultyBinding` on the same instance (only
        // within the single closure invocation that wrote it), so a second
        // `view.difficultyBinding.wrappedValue` read here isn't a meaningful
        // assertion. `roundTripAcrossSimulatedRelaunch` below covers the real
        // production shape instead: a FRESH view instance reads the
        // persisted value back, exactly like `LiveRouteFactory` does.
        var seen: [Difficulty] = []
        let view = MinesweeperPracticeHubView(
            path: .constant([]),
            initialDifficulty: .beginner,
            onDifficultyChanged: { seen.append($0) }
        )

        view.difficultyBinding.wrappedValue = .intermediate

        #expect(seen == [.intermediate])
    }

    @Test("round trip: persisted value from one view instance seeds the next (simulated relaunch)")
    func roundTripAcrossSimulatedRelaunch() {
        /// Stands in for the composition root's `LastSelectionStore` —
        /// backed by a plain in-memory box rather than real UserDefaults so
        /// this test stays a pure view seam test.
        final class Box {
            var value: Difficulty = .beginner
        }
        let box = Box()

        let firstLaunch = MinesweeperPracticeHubView(
            path: .constant([]),
            initialDifficulty: box.value,
            onDifficultyChanged: { box.value = $0 }
        )
        firstLaunch.difficultyBinding.wrappedValue = .expert

        // A brand-new view instance reading the SAME box simulates relaunch:
        // no in-memory state survives except what was persisted.
        let secondLaunch = MinesweeperPracticeHubView(
            path: .constant([]),
            initialDifficulty: box.value
        )

        #expect(secondLaunch.difficultyBinding.wrappedValue == .expert)
    }
}
