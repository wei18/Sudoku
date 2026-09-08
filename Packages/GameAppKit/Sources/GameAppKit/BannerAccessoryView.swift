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
// Visibility: `BannerSlotView` already collapses to `EmptyView()` when the
// gate denies / the user dismissed / the provider reports `.suppressed` —
// unchanged by this move. `RootShellView` attaches `.tabViewBottomAccessory`
// UNCONDITIONALLY (never a conditional attach — PM ruling, see
// meetings/2026-09-07_1024-banner-accessory.impl-notes.md); suppression lives
// entirely inside this content, exactly as `BannerSlotView` already behaves.
//
// C-33 (ATT anchor) moves here from `TodayTabHost`: `onAdContext` still fires
// on the SAME event it always has — the gate opening, the first moment a
// personalized ad is about to load — just from the accessory's shared banner
// instead of the old per-Today-tab one. Ordering is unchanged and enforced by
// `BannerSlotView.resolveGateAndLoad` (untouched by this move): `await
// onAdContext?()` always runs BEFORE the reload coordinator's actual ad load,
// so the primer is guaranteed to offer before any ad-context/ad-load event.
//
// Cosmetic (B-6 bonus finding, #1029): a fixed-size 320×50 test creative can
// leave the accessory's rounded capsule ends uncovered. `backgroundColor`
// below letterboxes that gap with the theme surface color instead of the
// SDK's own opaque fill.

#if os(iOS)

public import SwiftUI
public import MonetizationCore
public import MonetizationUI

/// The free function `BannerSlotView`'s `onAdContext` hook calls — a plain
/// function (not a method on `BannerAccessoryView`) so it takes `attPrimer`
/// without capturing `self` in a `@Sendable` closure, and so tests can invoke
/// this EXACT call without rendering (mirrors the retired
/// `todayTabHostFireOnAdContext`, moved here with C-33).
@MainActor
func bannerAccessoryFireOnAdContext(attPrimer: ATTPrimerCoordinator) async {
    await attPrimer.maybePresentOnAdContext()
}

@MainActor
struct BannerAccessoryView: View {
    let adProvider: any AdProvider
    let adGate: AdGate
    let attPrimer: ATTPrimerCoordinator

    @Environment(\.theme) private var theme

    var body: some View {
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            onAdContext: { [attPrimer] in
                await bannerAccessoryFireOnAdContext(attPrimer: attPrimer)
            },
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
        .padding(.horizontal, 12)
    }
}

#endif
