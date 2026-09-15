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
// the `GameRoot` value by `MakeGameApp`) — no provider / gate / primer
// parameters flow through here. The ATT anchor (C-33) lives on the session's
// `onAdContext` hook, wired in `makeBannerSession`, so the primer fires
// before the first ad load no matter which slot triggers it.
//
// Lease ownership (#1080): unlike every other slot, this one does NOT hold
// its own `@StateObject` lease — `tabViewBottomAccessory` re-hosts this
// view's SwiftUI content natively (no re-render of `GameRoot`, no `.id`
// change), which would reset a self-owned lease and re-request the ad on
// every re-host (measured: 8 requests vs 2 on `main`'s never-re-hosted
// slots). `GameRoot` owns the lease instead (`@State`, scene lifetime) and
// injects it via `\.bannerAccessoryLease`; see
// `tabview-bottom-accessory-rehosts-content`.
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
    // #1080: `GameRoot`-owned lease, see the file header. `nil` only for a
    // lost injection — see `onMissingAccessoryLease` below.
    @Environment(\.bannerAccessoryLease) private var accessoryLease

    var body: some View {
        content
            .padding(.horizontal, 12)
    }

    @ViewBuilder
    private var content: some View {
        if let accessoryLease {
            BannerSlotView(
                lease: accessoryLease,
                isSuppressed: false,
                backgroundColor: theme.surface.background.resolved,
                progressTint: theme.accent.primary.resolved,
                captionColor: theme.text.secondary.resolved,
                dismissTint: theme.text.secondary.resolved
            )
        } else {
            // #1080: no silent fallback (mirrors `BannerSessionModel
            // .onMissingSession`, #1058) — a missing lease means `GameRoot`
            // stopped injecting it, which must fail loudly, not quietly
            // regress to a self-owned lease that re-registers on every
            // re-host. `let _ =` is the standard `@ViewBuilder` side-effect
            // idiom — a bare call statement doesn't type-check as `View`.
            // swiftlint:disable:next redundant_discardable_let
            let _ = Self.onMissingAccessoryLease()
            EmptyView()
        }
    }

    /// Called when `BannerAccessoryView` renders with no `\.bannerAccessoryLease`
    /// in its environment — a lost injection. Asserts in DEBUG; the accessory
    /// renders nothing either way. Tests swap it to observe the call.
    static var onMissingAccessoryLease: @MainActor () -> Void = {
        assertionFailure("BannerAccessoryView mounted without a \\.bannerAccessoryLease (#1080)")
    }
}

#endif
