// BannerAccessoryViewTests — #1024: the ATT primer anchor (C-33) now lives on
// `BannerAccessoryView`'s banner slot (design.md §2.4), moved here from the
// retired `TodayTabHost` bannerSlot (`TodayTabHostTests`, pre-#1024).
//
// iOS-only: `BannerAccessoryView` / `bannerAccessoryFireOnAdContext` only
// compile `#if os(iOS)` (macOS has no `tabViewBottomAccessory` at all — this
// whole file is structurally excluded from a macOS `swift test` run, not
// skipped at runtime).
//
// Same harness limitation `TodayTabHostTests` diagnosed (four rounds):
// rendering `BannerAccessoryView` in an offscreen `NSWindow` and pumping the
// run loop until its `.task` resolves across `AdGate`'s actor boundary never
// resumes under `swift test`'s headless executor. `bannerAccessoryFireOnAdContext`
// is the free function `BannerSlotView`'s `onAdContext` hook calls — invoking
// it directly proves the exact call the real banner slot makes without
// depending on that broken pump.
//
// Ordering (PM condition, 2026-09-08): the primer must fire BEFORE any
// ad-context / ad-load event. That ordering is enforced by
// `BannerSlotView.resolveGateAndLoad` (AppMonetizationKit, UNCHANGED by this
// move): `await onAdContext?()` always precedes
// `reloadCoordinator.reloadIfGateOpen(...)` (the actual ad load) — see that
// function's source. This suite pins the coordinator-side half of the
// contract (offer semantics); the before/after trigger set is: BEFORE —
// nothing ad-related has loaded yet; AFTER — the reload coordinator's load
// attempt, if the gate is open. No test here re-verifies the untouched
// `BannerSlotView` ordering itself (same scope boundary `TodayTabHostTests`
// drew for the pre-#1024 host).

#if os(iOS)

import Foundation
import SwiftUI
import Testing
import MonetizationCore
import MonetizationTesting
import MonetizationUI
@testable import GameAppKit

// MARK: - Suite

@MainActor
@Suite("BannerAccessoryView — C-33 ATT anchor wiring")
struct BannerAccessoryViewTests {

    private func makeView(attPrimer: ATTPrimerCoordinator) -> BannerAccessoryView {
        BannerAccessoryView(
            adProvider: FakeAdProvider(),
            adGate: AdGate(store: FakeAdGateStateStore(
                initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
            )),
            attPrimer: attPrimer
        )
    }

    @Test("first ad context, ATT notDetermined: presents the primer")
    func firstAdContextPresentsWhenNotDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        _ = makeView(attPrimer: attPrimer) // proves BannerAccessoryView constructs with this attPrimer

        await bannerAccessoryFireOnAdContext(attPrimer: attPrimer)

        #expect(attPrimer.isPrimerPresented == true, "the accessory's banner slot must reach the ATT primer coordinator")
    }

    @Test("first ad context, ATT already determined: never presents")
    func firstAdContextNeverPresentsWhenDetermined() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { false }, requestSystemPrompt: {})
        _ = makeView(attPrimer: attPrimer)

        await bannerAccessoryFireOnAdContext(attPrimer: attPrimer)

        #expect(attPrimer.isPrimerPresented == false)
    }

    @Test("hasOffered latch: exactly one offer across two ad-context hooks sharing the coordinator")
    func offersExactlyOnceAcrossTwoAdContexts() async {
        let attPrimer = ATTPrimerCoordinator(isNotDetermined: { true }, requestSystemPrompt: {})
        // Two SEPARATE `BannerAccessoryView` mounts (e.g. the accessory being
        // rebuilt across a launch) sharing the SAME `attPrimer` instance,
        // exactly like production: `attPrimer` is built once in `makeGameApp`
        // and handed to the single `bottomAccessory` closure.
        _ = makeView(attPrimer: attPrimer)
        _ = makeView(attPrimer: attPrimer)

        await bannerAccessoryFireOnAdContext(attPrimer: attPrimer)
        #expect(attPrimer.isPrimerPresented == true, "first ad context should offer the primer")

        attPrimer.declinePrimer() // "Not now" — mirrors ATTPrimerCoordinatorTests.notNow_…
        #expect(attPrimer.isPrimerPresented == false)

        await bannerAccessoryFireOnAdContext(attPrimer: attPrimer)
        #expect(attPrimer.isPrimerPresented == false, "hasOffered latch must prevent a second offer this session")
    }
}

#endif
