// MinesweeperCompletedRedirectSurfaceTests — proves the non-live completion
// path constructs the `.review` variant, never `.liveSolve` (#1023).
//
// `MinesweeperDailyOpenGuardView`'s `.resolved(.completed)` state AND
// `MinesweeperAppComposition.LiveRouteFactory`'s pushed `.completion` route
// both build `MinesweeperCompletedRedirectSurface`, which hardcodes
// `variant: .review` with no way to override it. Mirror-reflecting the
// constructed view tree (mirrors the repo's established pattern, e.g.
// `MinesweeperFreshBoardLoaderViewIdentityTests`' `.id()` assertion) proves
// the ACTUAL value passed to the scaffold.

import Testing
import SwiftUI
import GameShellUI
import GameAudio
@testable import MinesweeperUI

@MainActor
@Suite("MinesweeperCompletedRedirectSurface — review variant (#1023)")
struct MinesweeperCompletedRedirectSurfaceTests {

    private func makeSurface() -> MinesweeperCompletedRedirectSurface {
        MinesweeperCompletedRedirectSurface(
            completionViewModel: MinesweeperCompletionViewModel(
                didWin: true,
                elapsedSeconds: 0,
                leaderboardId: "daily-beginner"
            ),
            reminderPrimer: nil,
            fetchDailyProgress: nil,
            onDailyNext: nil,
            onClose: {},
            showsElapsedTime: false
        )
    }

    // Path 4: MinesweeperDailyOpenGuardView's `.resolved(.completed)` state
    // builds exactly this surface.
    //
    // `surface.body` is `CompletionOverlayScaffold(...).task { … }`, i.e.
    // `ModifiedContent<CompletionOverlayScaffold<Card>, _TaskModifier>` —
    // drill into `.content` to reach the scaffold itself.
    @Test("msResolvedCompleted_constructsReviewVariant")
    func msResolvedCompleted_constructsReviewVariant() throws {
        let modifiedMirror = Mirror(reflecting: makeSurface().body)
        let scaffold = try #require(modifiedMirror.children.first(where: { $0.label == "content" })?.value)
        let scaffoldMirror = Mirror(reflecting: scaffold)
        let value = try #require(scaffoldMirror.children.first(where: { $0.label == "variant" })?.value)
        let variant = try #require(value as? CompletionVariant)
        #expect(variant == .review)
    }

    // MARK: - review-variant surfaces fire zero haptic events (R1)

    /// `MinesweeperCompletedRedirectSurface` — and the `CompletionOverlayScaffold`
    /// it wraps — takes NO `SoundPlaying`/`HapticPlaying` parameter at all
    /// (nor reads one from `@Environment`): haptic authority stays exclusively
    /// at the VM's terminal-transition edge (`MinesweeperGameViewModel.swift`,
    /// asserted by `MinesweeperGameAudioTests`). Mirror-reflecting every
    /// stored property proves neither type holds a player a future change
    /// could wire a haptic call onto.
    @Test("reviewVariantSurfaceHoldsNoAudioOrHapticPlayer")
    func reviewVariantSurfaceHoldsNoAudioOrHapticPlayer() throws {
        let surface = makeSurface()
        for child in Mirror(reflecting: surface).children {
            #expect(!(child.value is any SoundPlaying), "MinesweeperCompletedRedirectSurface must not hold a SoundPlaying instance")
            #expect(!(child.value is any HapticPlaying), "MinesweeperCompletedRedirectSurface must not hold a HapticPlaying instance")
        }
        let modifiedMirror = Mirror(reflecting: surface.body)
        let scaffold = try #require(modifiedMirror.children.first(where: { $0.label == "content" })?.value)
        for child in Mirror(reflecting: scaffold).children {
            #expect(!(child.value is any SoundPlaying), "CompletionOverlayScaffold must not hold a SoundPlaying instance")
            #expect(!(child.value is any HapticPlaying), "CompletionOverlayScaffold must not hold a HapticPlaying instance")
        }
    }
}
