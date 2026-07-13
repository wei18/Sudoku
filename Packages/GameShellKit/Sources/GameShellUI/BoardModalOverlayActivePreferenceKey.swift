// BoardModalOverlayActivePreferenceKey — signals a full-screen-intent overlay
// (Pause / Completion) is currently masking a board mounted in the shell's
// detail column.
//
// #763: on macOS, board routes are pushed into the detail column of
// `NavigationStackHost`'s `NavigationSplitView`, not presented as a
// `fullScreenCover` (iOS-only — see `GameAppKit.GameRoot`'s `#if os(iOS)`
// split). The Pause menu and post-game Completion surface are mounted
// directly on `BoardView` / `MinesweeperBoardView` via
// `.frame(maxWidth: .infinity, maxHeight: .infinity)` + `.overlay {}`, which
// fills only the view they're attached to — on macOS that's the detail
// column, so `.ignoresSafeArea()` never reaches the sidebar. The sidebar
// stays visible and clickable underneath the "modal".
//
// A board publishes this preference with the SAME condition that drives its
// own overlay visibility. `RootShellView` observes it via
// `.onPreferenceChange` and, on macOS only, masks + disables the sidebar
// column while it's true — restoring the "a modal blocks the rest of the
// app" contract that iOS already gets for free from `fullScreenCover`.
//
// Convention: any FUTURE full-screen-intent overlay mounted on a
// detail-column-hosted view (e.g. a coach-mark / first-run overlay) must
// publish this same preference, or it will reintroduce the #763 sidebar leak
// on macOS.

public import SwiftUI

public struct BoardModalOverlayActivePreferenceKey: PreferenceKey {
    public static var defaultValue: Bool { false }

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}
