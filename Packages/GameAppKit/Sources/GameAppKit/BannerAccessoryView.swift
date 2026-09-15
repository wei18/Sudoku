// BannerAccessoryView — the `tabViewBottomAccessory` content (#1024,
// design.md §2.4). iOS/iPadOS only: `tabViewBottomAccessory` doesn't exist on
// macOS (§2.4.1 option A — no banner on macOS at all), so this whole file is
// gated `#if os(iOS)` and never compiles into the macOS binary. That is the
// structural exclusion the acceptance grep checks for, not a runtime check.
//
// Retired: the old per-Today-tab inline banner slot (`TodayTabHost`'s
// `bannerSlot`) and the Practice/Settings `banner:` closures that built their
// own `BannerSlotView`. The accessory now covers the WHOLE tab shell — Today,
// Practice, Settings (pushed onto a tab's stack, so it stays inside the
// TabView and keeps the accessory) — with ONE shared banner instead of N
// per-screen ones. Board screens are untouched (`fullScreenCover`, outside
// the TabView — #1022 owns their bottom chrome).
//
// Session model (#1062): this is just another `BannerSlotView`. It reads the
// session's `BannerSessionModel` through `\.bannerSession` (injected once on
// the `GameRoot` value by `MakeGameApp`) and registers itself like every other
// slot — no provider / gate / primer parameters flow through here. The ATT
// anchor (C-33) lives on the session's `onAdContext` hook, wired in
// `makeBannerSession`, so the primer fires before the first ad load no matter
// which slot triggers it.
//
// Visibility: `RootShellView` drives `tabViewBottomAccessory(isEnabled:)`
// from `bannerSession.isVisible` (#1079 option 1, iOS 26.1 floor), so when
// the gate denies the whole capsule is gone — not an empty capsule. Inside
// the enabled capsule `BannerSlotView` still collapses on its own for the
// same `isVisible` read, so both layers agree by construction.
//
// Cosmetic (B-6 bonus finding, #1029): a fixed-size 320×50 test creative can
// leave the accessory's rounded capsule ends uncovered. `backgroundColor`
// below letterboxes that gap with the theme surface color instead of the
// SDK's own opaque fill.

#if os(iOS)

public import SwiftUI
public import MonetizationUI

@MainActor
struct BannerAccessoryView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        BannerSlotView(
            isSuppressed: false,
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.text.secondary.resolved
        )
        .padding(.horizontal, 12)
    }
}

#endif
