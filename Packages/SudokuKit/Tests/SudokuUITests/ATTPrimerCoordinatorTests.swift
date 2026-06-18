// ATTPrimerCoordinatorTests — #371 / #195 ATT pre-prompt timing + idempotency.
//
// Proves the APPROVED contract WITHOUT touching the system ATT dialog:
//   - ATT is requested only AFTER the ad-context trigger fires (never at boot —
//     boot ordering is covered separately in BootOrderTests).
//   - "Not now" dismisses and NEVER requests.
//   - The trigger is idempotent: re-firing presents at most once per launch.
//   - When ATT is already determined, the trigger never presents and never
//     requests.

import Foundation
import Testing
import os
// #556: `ATTPrimerCoordinator` moved from SudokuUI to MonetizationUI.
import MonetizationUI
@testable import SudokuUI

@MainActor
@Suite("ATTPrimerCoordinator — pre-prompt timing + idempotency")
struct ATTPrimerCoordinatorTests {

    /// Records how many times the system-prompt closure fired. Sendable via the
    /// same unfair-lock pattern used across the suite.
    private final class Counter: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock<Int>(initialState: 0)
        func increment() { state.withLock { $0 += 1 } }
        var count: Int { state.withLock { $0 } }
    }

    private func makeCoordinator(
        notDetermined: Bool,
        requestCounter: Counter
    ) -> ATTPrimerCoordinator {
        ATTPrimerCoordinator(
            isNotDetermined: { notDetermined },
            requestSystemPrompt: { requestCounter.increment() }
        )
    }

    // MARK: - No request at construction (i.e. not at boot)

    @Test func construction_doesNotRequestATT() async {
        let counter = Counter()
        _ = makeCoordinator(notDetermined: true, requestCounter: counter)
        #expect(counter.count == 0)
    }

    // MARK: - Ad-context trigger presents (does not yet request)

    @Test func adContext_whenNotDetermined_presentsButDoesNotRequestYet() async {
        let counter = Counter()
        let sut = makeCoordinator(notDetermined: true, requestCounter: counter)

        await sut.maybePresentOnAdContext()

        #expect(sut.isPrimerPresented == true)
        // Presenting the priming sheet must NOT fire the system dialog — that
        // only happens on "Continue".
        #expect(counter.count == 0)
    }

    // MARK: - Continue → system prompt fires once, sheet dismisses

    @Test func continue_requestsSystemPromptAndDismisses() async {
        let counter = Counter()
        let sut = makeCoordinator(notDetermined: true, requestCounter: counter)
        await sut.maybePresentOnAdContext()

        await sut.continueToSystemPrompt()

        #expect(counter.count == 1)
        #expect(sut.isPrimerPresented == false)
    }

    // MARK: - "Not now" → dismiss, NEVER request

    @Test func notNow_dismissesAndNeverRequests() async {
        let counter = Counter()
        let sut = makeCoordinator(notDetermined: true, requestCounter: counter)
        await sut.maybePresentOnAdContext()

        sut.declinePrimer()

        #expect(sut.isPrimerPresented == false)
        #expect(counter.count == 0)
    }

    // MARK: - Idempotent: re-firing the trigger presents at most once

    @Test func adContext_isIdempotent_acrossRepeatedFires() async {
        let counter = Counter()
        let sut = makeCoordinator(notDetermined: true, requestCounter: counter)

        await sut.maybePresentOnAdContext()
        // User declines.
        sut.declinePrimer()
        #expect(sut.isPrimerPresented == false)

        // Banner re-polls (foreground return, .task re-fire) → trigger again.
        await sut.maybePresentOnAdContext()
        // The latch prevents a second presentation in this session.
        #expect(sut.isPrimerPresented == false)
        #expect(counter.count == 0)
    }

    // MARK: - Already determined → never present, never request

    @Test func adContext_whenAlreadyDetermined_neverPresentsOrRequests() async {
        let counter = Counter()
        let sut = makeCoordinator(notDetermined: false, requestCounter: counter)

        await sut.maybePresentOnAdContext()

        #expect(sut.isPrimerPresented == false)
        #expect(counter.count == 0)
    }
}
