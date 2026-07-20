// MinesweeperFreshBoardLoaderViewIdentityTests — issue #910.
//
// Bug: MS Practice → hit a mine (loss) → "Play Again" left the board frozen
// on the exploded state. Root cause: `MinesweeperBoardView`'s
// `difficulty:seed:mode:` init built its `MinesweeperGameViewModel` once via
// `@State`'s `initialValue`, which SwiftUI only honors the FIRST time a view
// is created at a given tree position — Play Again's same-tick
// dismiss+represent could reuse that same position, so the fresh seed (and
// its NEW `MinesweeperGameViewModel`) was silently discarded and the old,
// already-lost view model kept driving the board.
//
// Fix: `MinesweeperFreshBoardLoaderView` rebuilds the view model from a
// `.task(id:)` keyed on (difficulty, seed) instead of `@State`'s
// `initialValue` — see that file's header doc. This test pins the exact
// construction seam the `.task(id:)` reload calls
// (`MinesweeperFreshBoardLoaderView.makeViewModel`): two calls — the first
// driven into a real mine-hit loss, the second at a different seed (mirrors
// Play Again's fresh `UInt64.random` seed) — must return two INDEPENDENT
// view model instances, with the second landing back at `.idle`, never
// inheriting the first's `.lost`/exploded state. A regression that goes back
// to reusing a single captured instance (e.g. reverting to `@State`'s
// `initialValue`) would fail the `!==` identity check here even before any
// live SwiftUI render is involved.
//
// Mirrors `MinesweeperGameViewModelTests.revealingMineSetsTerminalStatus`'s
// deterministic mine-hit recipe (seed 13: reveal (4,4) to open the board,
// scan for a mine, reveal it) for driving the FIRST view model to `.lost`.

import Foundation
import SwiftUI
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import MinesweeperGameState

@MainActor
@Suite("MinesweeperFreshBoardLoaderView — Play Again identity reset (#910)")
struct MinesweeperFreshBoardLoaderViewIdentityTests {

    @Test func rebuildAfterLossProducesFreshIndependentViewModel() async throws {
        // First "board": drive it to a real mine-hit loss, exactly like a
        // Practice player who just exploded.
        let lostSeed: UInt64 = 13
        let firstViewModel = MinesweeperFreshBoardLoaderView.makeViewModel(
            difficulty: .beginner,
            seed: lostSeed,
            mode: .practice
        )
        await firstViewModel.reveal(row: 4, col: 4)
        var minePos: (Int, Int)?
        for row in 0..<firstViewModel.rows {
            for col in 0..<firstViewModel.columns where firstViewModel.cell(row: row, col: col).isMine {
                minePos = (row, col); break
            }
            if minePos != nil { break }
        }
        let (mineRow, mineCol) = try #require(minePos)
        await firstViewModel.reveal(row: mineRow, col: mineCol)
        #expect(firstViewModel.status == .lost)
        #expect(firstViewModel.isTerminal == true)

        // Play Again: a fresh seed (mirrors `LiveRouteFactory+DailyBoardOpen`'s
        // `UInt64.random(in: .min ... .max)`), same difficulty — the exact
        // reload the loader's `.task(id:)` performs on a (difficulty, seed) key
        // change.
        let replaySeed: UInt64 = 4242
        let secondViewModel = MinesweeperFreshBoardLoaderView.makeViewModel(
            difficulty: .beginner,
            seed: replaySeed,
            mode: .practice
        )

        // The regression this guards: a rebuild that silently kept the SAME
        // (already-lost) instance instead of constructing a new one.
        #expect(firstViewModel !== secondViewModel)
        #expect(secondViewModel.status == .idle)
        #expect(secondViewModel.isTerminal == false)
        // The exploded board's revealed mines must not bleed into the fresh
        // one — every cell starts hidden again.
        #expect(secondViewModel.cells.allSatisfy { $0.state == .hidden })
    }

    // MARK: - Difficulty forwarding (#910)

    // The loader's `.task(id:)` key is `BoardKey(difficulty:seed:)` — BOTH
    // fields, not seed alone — so a future difficulty-only Play Again variant
    // still forces a rebuild. This pins that `makeViewModel` actually
    // forwards `difficulty` into the constructed session (not just `seed`),
    // which is what makes keying on it meaningful.
    @Test func makeViewModelForwardsDifficultyIntoTheSession() {
        let beginner = MinesweeperFreshBoardLoaderView.makeViewModel(
            difficulty: .beginner, seed: 1, mode: .practice
        )
        let intermediate = MinesweeperFreshBoardLoaderView.makeViewModel(
            difficulty: .intermediate, seed: 1, mode: .practice
        )
        #expect(beginner !== intermediate)
        #expect(beginner.rows != intermediate.rows || beginner.columns != intermediate.columns)
    }

    // MARK: - `.id()` wiring — the ACTUAL round-2 fix (#910)

    // The two tests above only prove the CONSTRUCTION seam (`makeViewModel`)
    // produces independent instances — they never touch `body`/`content`, so
    // they would have passed even with round 1's bug (reassigning `state`
    // from `.loaded(vm1)` to `.loaded(vm2)` without forcing SwiftUI to treat
    // the nested `MinesweeperBoardView` as a new identity). That is exactly
    // how round 1 shipped broken: code review + a sim repro caught it, not
    // this test file.
    //
    // This test instead inspects the REAL value `content`'s `.loaded` branch
    // renders in production (`boardContent(viewModel:)`, called directly —
    // no need to drive `.task`/`state`, since `.id()` is attached
    // unconditionally inside that function). `Mirror`-reflecting the
    // returned `some View` exposes SwiftUI's own `IDView<Content, ID>`
    // wrapper with its stored `id`, confirmed empirically:
    //   dump(SomeView().id(key)) → "SwiftUI.IDView<...>" with a stored
    //   `id: <key>` child — see this test's `boardIDKey` helper.
    // A regression that drops the `.id()` call (reverting to a bare
    // `MinesweeperBoardView`) makes `boardIDKey` return `nil` and fails
    // `boardContentIsWrappedInAnIdentityKeyedView` below; a regression that
    // computes the WRONG key (e.g. seed only, ignoring difficulty) fails
    // `boardContentIDKeyMatchesDifficultyAndSeed`.

    @Test func boardContentIsWrappedInAnIdentityKeyedView() {
        let loader = MinesweeperFreshBoardLoaderView(difficulty: .beginner, seed: 1, mode: .practice)
        let viewModel = MinesweeperFreshBoardLoaderView.makeViewModel(
            difficulty: .beginner, seed: 1, mode: .practice
        )
        let rendered = loader.boardContent(viewModel: viewModel)
        #expect(Self.boardIDKey(of: rendered) != nil, "Expected an .id()-keyed IDView wrapping the board")
    }

    @Test func boardContentIDKeyMatchesDifficultyAndSeed() throws {
        let loaderA = MinesweeperFreshBoardLoaderView(difficulty: .beginner, seed: 1, mode: .practice)
        let loaderB = MinesweeperFreshBoardLoaderView(difficulty: .beginner, seed: 2, mode: .practice)
        let loaderC = MinesweeperFreshBoardLoaderView(difficulty: .intermediate, seed: 1, mode: .practice)
        let boardVM = MinesweeperFreshBoardLoaderView.makeViewModel(difficulty: .beginner, seed: 1, mode: .practice)

        let keyA = try #require(Self.boardIDKey(of: loaderA.boardContent(viewModel: boardVM)))
        let keyB = try #require(Self.boardIDKey(of: loaderB.boardContent(viewModel: boardVM)))
        let keyC = try #require(Self.boardIDKey(of: loaderC.boardContent(viewModel: boardVM)))
        let keyASame = try #require(Self.boardIDKey(of: loaderA.boardContent(viewModel: boardVM)))

        // Same (difficulty, seed) → equal key (stable, no spurious remounts).
        #expect(keyA == keyASame)
        // Different seed alone → different key.
        #expect(keyA != keyB)
        // Different difficulty alone → different key.
        #expect(keyA != keyC)
    }

    /// Extracts the `id` payload SwiftUI's `.id(_:)` modifier stores, via
    /// `Mirror` reflection on the concrete `SwiftUI.IDView<Content, ID>`
    /// runtime type `.id()` produces (confirmed empirically — this is the
    /// SAME technique `LiveRouteFactoryTests` uses to introspect an `AnyView`
    /// via `String(describing:)`, one level more precise). Returns `nil` if
    /// the rendered value is NOT an `.id()`-keyed view (the round-1
    /// regression this file guards against).
    private static func boardIDKey(of view: some View) -> MinesweeperFreshBoardLoaderView.BoardKey? {
        let mirror = Mirror(reflecting: view)
        guard String(describing: mirror.subjectType).hasPrefix("IDView<") else { return nil }
        for child in mirror.children where child.label == "id" {
            return child.value as? MinesweeperFreshBoardLoaderView.BoardKey
        }
        return nil
    }
}
