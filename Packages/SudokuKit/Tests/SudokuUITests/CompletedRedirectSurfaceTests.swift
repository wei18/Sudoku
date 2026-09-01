// CompletedRedirectSurfaceTests — proves the non-live completion paths
// construct the `.review` variant, never `.liveSolve` (#1023).
//
// Both Sudoku review paths — the pushed `.completion` route
// (`LiveRouteFactory`) and `BoardLoaderView`'s `.completedRedirect` state —
// route through the SAME `CompletedRedirectSurface` (GameShellUI's
// `CompletionOverlayScaffold` wrapper), which hardcodes `variant: .review`
// with no way to override it. Mirror-reflecting the constructed view tree
// (mirrors the repo's established pattern, e.g.
// `MinesweeperFreshBoardLoaderViewIdentityTests`' `.id()` assertion) proves
// the ACTUAL value passed to the scaffold, not just that the doc comment
// claims it.

import Testing
import SwiftUI
import GameShellUI
import GameAudio
@testable import SudokuUI

@MainActor
@Suite("CompletedRedirectSurface — review variant (#1023)")
struct CompletedRedirectSurfaceTests {

    private func makeSurface() -> CompletedRedirectSurface {
        CompletedRedirectSurface(
            completionViewModel: CompletionViewModel(
                puzzleId: "2026-01-01-easy",
                elapsedSeconds: 61,
                mistakeCount: 0,
                leaderboardId: nil
            ),
            reminderPrimer: nil,
            fetchDailyProgress: nil,
            onDailyNext: nil,
            onClose: {}
        )
    }

    /// `surface.body` is `CompletionOverlayScaffold(...).task { … }`, i.e.
    /// `ModifiedContent<CompletionOverlayScaffold<Card>, _TaskModifier>` —
    /// drill into `.content` to reach the scaffold itself before reading its
    /// `variant` stored property.
    private func reflectedVariant(_ surface: CompletedRedirectSurface) throws -> CompletionVariant {
        let modifiedMirror = Mirror(reflecting: surface.body)
        let scaffold = try #require(modifiedMirror.children.first(where: { $0.label == "content" })?.value)
        let scaffoldMirror = Mirror(reflecting: scaffold)
        let value = try #require(scaffoldMirror.children.first(where: { $0.label == "variant" })?.value)
        return try #require(value as? CompletionVariant)
    }

    // Path 3: BoardLoaderView's `.completedRedirect` state builds exactly this
    // surface (BoardLoaderView.swift's `content` switch).
    @Test("completedRedirect_constructsReviewVariant")
    func completedRedirect_constructsReviewVariant() throws {
        #expect(try reflectedVariant(makeSurface()) == .review)
    }

    // Path 2: LiveRouteFactory's pushed `.completion` route builds this SAME
    // surface (LiveRouteFactory.swift's `.completion` case) — same type,
    // same guarantee; named separately per the dispatch's "one test per path"
    // so a future refactor that splits the two paths' implementations still
    // has a specifically-named regression guard for each.
    @Test("pushedReviewRoute_constructsReviewVariant")
    func pushedReviewRoute_constructsReviewVariant() throws {
        #expect(try reflectedVariant(makeSurface()) == .review)
    }

    // MARK: - review-variant surfaces fire zero haptic events (R1)

    /// `CompletedRedirectSurface` — and `CompletionOverlayScaffold` it wraps —
    /// takes NO `SoundPlaying`/`HapticPlaying` parameter at all (nor reads one
    /// from `@Environment`): haptic authority stays exclusively at the VM's
    /// terminal-transition edge (`GameViewModel.swift`, asserted by
    /// `GameViewModelAudioTests`). Mirror-reflecting every stored property on
    /// the surface AND the scaffold it constructs proves neither type holds
    /// a player a future change could wire a haptic call onto — the
    /// mechanism this test locks is "there is no player to call", not just
    /// "the current code path doesn't call one".
    @Test("reviewVariantSurfaceHoldsNoAudioOrHapticPlayer")
    func reviewVariantSurfaceHoldsNoAudioOrHapticPlayer() throws {
        let surface = makeSurface()
        for child in Mirror(reflecting: surface).children {
            #expect(!(child.value is any SoundPlaying), "CompletedRedirectSurface must not hold a SoundPlaying instance")
            #expect(!(child.value is any HapticPlaying), "CompletedRedirectSurface must not hold a HapticPlaying instance")
        }
        let modifiedMirror = Mirror(reflecting: surface.body)
        let scaffold = try #require(modifiedMirror.children.first(where: { $0.label == "content" })?.value)
        for child in Mirror(reflecting: scaffold).children {
            #expect(!(child.value is any SoundPlaying), "CompletionOverlayScaffold must not hold a SoundPlaying instance")
            #expect(!(child.value is any HapticPlaying), "CompletionOverlayScaffold must not hold a HapticPlaying instance")
        }
    }
}
