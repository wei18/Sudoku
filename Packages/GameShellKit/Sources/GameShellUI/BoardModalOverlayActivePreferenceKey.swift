// BoardModalOverlayActivePreferenceKey — signals a full-screen-intent overlay
// (Pause / Completion) is currently masking a board hosted inside the shell.
//
// #763: a board reached by PUSH (macOS, iPad regular) is not a
// `fullScreenCover` — that path is iOS-only, see `GameAppKit.GameRoot`'s
// `#if os(iOS)` split. Its Pause menu and post-game Completion surface fill
// only the view they are attached to, so `.ignoresSafeArea()` never reaches the
// shell's own navigation chrome, which stayed visible and clickable underneath
// the "modal".
//
// A board publishes this preference with the SAME condition that drives its own
// overlay visibility — enforced by construction now that both come from the
// single `isActive` argument of `View.boardModalOverlay(isActive:content:)`.
// `RootShellView` observes it via `.onPreferenceChange` and disables the whole
// `TabView` while it is true, restoring the "a modal blocks the rest of the app"
// contract iOS gets for free from `fullScreenCover`.
//
// #1020 / #1019: disabling the TabView is only half of it. Because
// `sidebarAdaptable` generates its own sidebar / tab-bar chrome, `.disabled()`
// has to cover the entire TabView — including anything rendered inside it — so
// the overlay's rendering is HOISTED out to a sibling of that TabView. See
// `BoardModalOverlayHoist.swift`.
//
// Convention: any FUTURE full-screen-intent overlay mounted on a pushed view
// (e.g. a coach-mark / first-run overlay) must publish this same preference, or
// it will reintroduce the #763 leak.

public import SwiftUI

public struct BoardModalOverlayActivePreferenceKey: PreferenceKey {
    public static var defaultValue: Bool { false }

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
