// BootDoesNotRequestATTTests — #371 / #195 F1+F4: boot must NOT prompt ATT.
//
// APPROVED decisions:
//   F1 — ATT fires after Home is seen + at the first ad-relevant moment, NOT at
//        cold launch.
//   F4 — UMP (GDPR consent) stays at cold launch; only ATT defers.
//
// `MonetizationBootCoordinator.boot()` still runs the UMP → ATT → AdMob shape
// (ordering tests depend on it), but `MonetizationBootBridges.live` now wires
// the ATT step to a NO-OP — the real `ATTPresenter.requestIfNeeded()` is driven
// later by the SudokuUI `ATTPrimerCoordinator`.
//
// This test drives the LIVE bridges through the coordinator and proves:
//   1. AdMob initialize() DID fire (boot still does its job — F4 keeps the rest).
//   2. The ATT step completes without moving ATT determination (no system
//      prompt was presented at boot). We read ATT status before and after boot
//      via `ATTPresenter.currentStatus()`; an un-prompted status is stable.

import Testing
import Foundation
@testable import AdsAdMob
import MonetizationCore
import MonetizationTesting

@Suite("AdsAdMob — boot does not request ATT (#371 / #195)")
struct BootDoesNotRequestATTTests {

    @Test func liveBoot_initializesAdMob_butDoesNotMoveATTDetermination() async {
        let provider = FakeAdProvider()
        let bridges = MonetizationBootBridges.live(adProvider: provider)

        let before = await ATTPresenter.currentStatus()

        let coordinator = MonetizationBootCoordinator(bridges: bridges)
        let outcomes = await coordinator.boot()

        let after = await ATTPresenter.currentStatus()

        // AdMob init ran (F4: boot still UMP + AdMob).
        let inits = await provider.initializeCallCount
        #expect(inits == 1)
        #expect(outcomes.map(\.step) == [.ump, .att, .adMob])
        #expect(outcomes.allSatisfy { $0.succeeded })

        // ATT determination is unchanged by boot — no prompt was presented.
        // (A real prompt would move `.notDetermined` → `.authorized`/`.denied`.)
        #expect(before == after)
    }
}
