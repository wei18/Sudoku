// MemoizedTabRootsTests — pins the #1020 "build each tab root once" contract.
//
// `RootShellView` calls its `tabRoot(_:)` closure on every body evaluation, and
// a game builds its hub view models inside `GameConfig.makeTabRoot`. If that
// builder ran per call, every render would mint fresh view models and wipe the
// player's in-progress hub state — the #918 bug shape (a per-render factory
// replacing the model the user had just interacted with).
//
// `makeGameAppCore` cannot be exercised directly from a unit test: it wires the
// full LIVE stack (CloudKit / GameKit / AdMob), and constructing that in an
// unentitled runner is the uncatchable-`CKException` trap the repo guide warns
// about. `memoizedTabRoots` is the minimal seam the composition root routes
// through, so the invariant is asserted here instead.

import SwiftUI
import Testing
import GameShellUI
@testable import GameAppKit

@Suite("GameAppKit — memoizedTabRoots (#1020)")
@MainActor
struct MemoizedTabRootsTests {

    /// The load-bearing assertion: three tabs, three builder calls, no matter
    /// how many times the shell re-evaluates.
    @Test("builds each tab exactly once, however often the shell asks")
    func buildsEachTabExactlyOnce() {
        var callsPerTab: [AppTab: Int] = [:]
        let tabRoot = memoizedTabRoots { tab in
            callsPerTab[tab, default: 0] += 1
            return AnyView(Text(tab.rawValue))
        }

        // One build per tab happened eagerly at construction...
        #expect(callsPerTab == [.today: 1, .practice: 1, .progress: 1])

        // ...and repeated evaluations for the SAME tab — what a body
        // re-evaluation looks like — add none.
        for _ in 0..<5 {
            for tab in AppTab.allCases {
                _ = tabRoot(tab)
            }
        }

        #expect(callsPerTab == [.today: 1, .practice: 1, .progress: 1])
        #expect(callsPerTab.values.reduce(0, +) == 3)
    }

    /// Stable identity is the whole point: the same tab must hand back the same
    /// stored value, not an equal-looking rebuild. Asserted through a reference
    /// type captured by the built view, since `AnyView` itself is not comparable.
    @Test("the same tab returns the same underlying instance")
    func returnsTheSameInstancePerTab() {
        final class Model { }
        var models: [AppTab: Model] = [:]
        let tabRoot = memoizedTabRoots { tab in
            let model = Model()
            models[tab] = model
            return AnyView(Text(tab.rawValue))
        }

        let firstTodayModel = models[.today]
        _ = tabRoot(.today)
        _ = tabRoot(.today)

        #expect(firstTodayModel != nil)
        #expect(models[.today] === firstTodayModel, "a rebuild would have replaced it")
    }

    /// Every tab must resolve — a missing entry would render an empty screen
    /// with no error, which is worse than a loud failure.
    @Test("covers every tab")
    func coversEveryTab() {
        var built: Set<AppTab> = []
        _ = memoizedTabRoots { tab in
            built.insert(tab)
            return AnyView(EmptyView())
        }

        #expect(built == Set(AppTab.allCases))
    }
}
