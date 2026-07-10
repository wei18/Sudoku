// BootOrderTests — v2.3.7.
//
// Drives `MonetizationBootCoordinator` directly through `MonetizationBootBridges`
// closures that record the order in which they fire. GameAppKit's shared
// `bootMonetization(adProvider:telemetry:)` free function re-uses the same
// coordinator with the live UMP / ATT / AdProvider wiring; the unit under
// test here is the *sequencing*, not the live integrations.

import Foundation
import Testing
import os

import AdsAdMob
import MonetizationCore

@Suite("MonetizationBootCoordinator — UMP → ATT → AdMob ordering")
struct BootOrderTests {

    private struct ScriptedError: Error, Equatable {
        let label: String
    }

    /// Recorder shared across the three boot closures. Strict-concurrency safe
    /// via `OSAllocatedUnfairLock` (the same lock pattern used by
    /// `LiveAdMobBridge`).
    private final class Recorder: @unchecked Sendable {
        private let state = OSAllocatedUnfairLock<[BootStep]>(initialState: [])

        func record(_ step: BootStep) {
            state.withLock { $0.append(step) }
        }

        var sequence: [BootStep] {
            state.withLock { $0 }
        }
    }

    private func makeBridges(
        recorder: Recorder,
        umpThrows: (any Error)? = nil,
        attThrows: (any Error)? = nil,
        adMobThrows: (any Error)? = nil
    ) -> MonetizationBootBridges {
        MonetizationBootBridges(
            requestUMPConsent: {
                recorder.record(.ump)
                if let umpThrows { throw umpThrows }
            },
            requestATT: {
                recorder.record(.att)
                if let attThrows { throw attThrows }
            },
            initializeAdMob: {
                recorder.record(.adMob)
                if let adMobThrows { throw adMobThrows }
            }
        )
    }

    // MARK: - Happy path: UMP → ATT → AdMob

    @Test func boot_runsStepsInOrder() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(recorder: recorder)
        )

        let outcomes = await coordinator.boot()

        #expect(recorder.sequence == [.ump, .att, .adMob])
        #expect(outcomes.map(\.step) == [.ump, .att, .adMob])
        #expect(outcomes.allSatisfy { $0.succeeded })
    }

    // MARK: - UMP throws → ATT + AdMob still run

    @Test func umpFailure_doesNotBlockSubsequentSteps() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(
                recorder: recorder,
                umpThrows: ScriptedError(label: "ump")
            )
        )

        let outcomes = await coordinator.boot()

        #expect(recorder.sequence == [.ump, .att, .adMob])
        #expect(outcomes[0].step == .ump && outcomes[0].succeeded == false)
        #expect(outcomes[1].step == .att && outcomes[1].succeeded == true)
        #expect(outcomes[2].step == .adMob && outcomes[2].succeeded == true)
    }

    // MARK: - ATT throws → AdMob still runs

    @Test func attFailure_doesNotBlockAdMobInit() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(
                recorder: recorder,
                attThrows: ScriptedError(label: "att")
            )
        )

        let outcomes = await coordinator.boot()

        #expect(recorder.sequence == [.ump, .att, .adMob])
        #expect(outcomes[0].succeeded == true)
        #expect(outcomes[1].succeeded == false)
        #expect(outcomes[2].succeeded == true)
    }

    // MARK: - AdMob throws → outcome surfaced, sequence still complete

    @Test func adMobFailure_surfacesFailedOutcome() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(
                recorder: recorder,
                adMobThrows: ScriptedError(label: "admob")
            )
        )

        let outcomes = await coordinator.boot()

        #expect(recorder.sequence == [.ump, .att, .adMob])
        #expect(outcomes[2].succeeded == false)
        #expect(outcomes[2].errorDescription?.contains("admob") == true)
    }

    // MARK: - Net: boot is non-blocking — every failure is logged + recovered

    @Test func allStepsFail_bootStillCompletesWithThreeOutcomes() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(
                recorder: recorder,
                umpThrows: ScriptedError(label: "ump"),
                attThrows: ScriptedError(label: "att"),
                adMobThrows: ScriptedError(label: "admob")
            )
        )

        let outcomes = await coordinator.boot()

        #expect(recorder.sequence == [.ump, .att, .adMob])
        #expect(outcomes.count == 3)
        #expect(outcomes.allSatisfy { !$0.succeeded })
    }

    // MARK: - Idempotency

    @Test func repeatedBootCalls_areIdempotent() async {
        let recorder = Recorder()
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(recorder: recorder)
        )

        _ = await coordinator.boot()
        _ = await coordinator.boot()

        // Second call is a no-op: only one set of three records.
        #expect(recorder.sequence == [.ump, .att, .adMob])
    }

    // MARK: - Log closure receives every outcome

    @Test func logClosure_receivesAllOutcomes() async {
        let recorder = Recorder()
        let loggedOutcomes = OSAllocatedUnfairLock<[BootOutcome]>(initialState: [])
        let coordinator = MonetizationBootCoordinator(
            bridges: makeBridges(
                recorder: recorder,
                umpThrows: ScriptedError(label: "ump")
            ),
            log: { outcome in
                loggedOutcomes.withLock { $0.append(outcome) }
            }
        )

        _ = await coordinator.boot()

        let logged = loggedOutcomes.withLock { $0 }
        #expect(logged.count == 3)
        #expect(logged[0].step == .ump && logged[0].succeeded == false)
        #expect(logged[1].step == .att && logged[1].succeeded == true)
        #expect(logged[2].step == .adMob && logged[2].succeeded == true)
    }
}
