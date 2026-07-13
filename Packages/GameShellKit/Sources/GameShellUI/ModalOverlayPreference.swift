// ModalOverlayPreference — lets a pushed board view signal upward that a
// full-cover modal (pause / completion) is currently presented, so
// `NavigationStackHost` can mask its macOS sidebar for the overlay's
// duration.
//
// #763 (owner adjudication 2026-07-13, overturning the #667/SDD-003 2B
// "board-scoped overlay is the ONE completion presentation on every
// platform" framing as justification for the gap): on macOS the board is
// pushed into the `NavigationSplitView`'s detail pane, NOT presented as a
// `fullScreenCover` — that presentation is iOS/iPadOS-only (`#if os(iOS)`,
// see `BoardView.swift`'s `path` doc + the `SudokuNearWin*` modifiers). A
// push only covers the detail column, so the sidebar list stayed visible
// AND tappable underneath a "modal" pause/completion overlay — a real
// modality break, not a deliberate design choice. iOS/iPadOS never had this
// bug: their board is a `fullScreenCover`, which already covers the whole
// window, sidebar included.
//
// `PreferenceKey` is the right tool here because the overlay is mounted deep
// inside a `.navigationDestination(for:)` push, several views below the
// `NavigationSplitView` that owns the sidebar. SwiftUI propagates preference
// values set on pushed destination content up through the hosting
// `NavigationStack` to any ancestor `.onPreferenceChange` reader — the same
// mechanism `.navigationTitle` relies on to update chrome owned by an
// ancestor `NavigationStack`, so a custom key reaches `NavigationStackHost`
// the same way.

public import SwiftUI

/// `true` while a full-cover modal overlay (pause menu / completion screen)
/// is presented somewhere in the subtree. `reduce` ORs so any one active
/// overlay anywhere in the pushed content wins.
public struct ModalOverlayActiveKey: PreferenceKey {
    public static let defaultValue = false

    public static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    /// Reports whether this view is currently showing a full-cover modal
    /// overlay (pause / completion), so an ancestor `NavigationStackHost`
    /// can mask its macOS sidebar for as long as the flag is up (#763).
    public func modalOverlayActive(_ isActive: Bool) -> some View {
        preference(key: ModalOverlayActiveKey.self, value: isActive)
    }
}
