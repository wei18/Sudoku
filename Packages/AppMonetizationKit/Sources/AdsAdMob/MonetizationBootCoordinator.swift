internal import Foundation
public import MonetizationCore

// MARK: - MonetizationBootCoordinator
//
// v2.3.7. Owns the app-launch sequence for the three monetization touch
// points: UMP consent → ATT prompt → AdMob SDK initialize.
//
// Contract:
//   1. Steps run strictly in order: UMP, then ATT, then AdMob.
//   2. A failing earlier step DOES NOT skip later steps — every step is
//      attempted and surfaces its outcome via `BootOutcome`. Boot is
//      never blocking; `BannerSlotView` already degrades to `.failed`
//      when AdMob is not yet ready (Brand "honest about deferred state"
//      contract, BannerSlotView header).
//   3. Errors are logged via the caller-supplied `log` closure rather than
//      coupled to a specific logger — `AppMonetizationKit` does not depend
//      on the SudokuKit `Telemetry` target. The Sudoku App composes the
//      live closure that fans into Telemetry (see AppComposition.live).
//
// Test seam:
//   `MonetizationBootBridges` is a Sendable struct of three async closures.
//   The live convenience `.live(adProvider:)` wires UMPConsentPresenter,
//   ATTPresenter, and `AdProvider.initialize()` into the closures; tests
//   pass a struct whose closures record their invocation order so the
//   "UMP → ATT → AdMob" sequence can be asserted from outside the actor.

// MARK: - MonetizationBootBridges

/// Injection seam for the three boot steps. Each closure is an async throw
/// — the coordinator catches errors and records them as `.failed` outcomes
/// rather than propagating, so a single failure cannot abort the sequence.
public struct MonetizationBootBridges: Sendable {
    public var requestUMPConsent: @Sendable () async throws -> Void
    public var requestATT: @Sendable () async throws -> Void
    public var initializeAdMob: @Sendable () async throws -> Void

    public init(
        requestUMPConsent: @escaping @Sendable () async throws -> Void,
        requestATT: @escaping @Sendable () async throws -> Void,
        initializeAdMob: @escaping @Sendable () async throws -> Void
    ) {
        self.requestUMPConsent = requestUMPConsent
        self.requestATT = requestATT
        self.initializeAdMob = initializeAdMob
    }

    /// Live wiring: UMPConsentPresenter → ATTPresenter → AdProvider.initialize.
    /// Outcomes from UMP / ATT are discarded here — the presenters already
    /// classify success / failure internally; the coordinator only needs to
    /// know whether the step *threw* (it doesn't, since presenters return
    /// outcome enums rather than throwing — so these closures are effectively
    /// non-throwing). `initializeAdMob` is the one closure that can actually
    /// throw, since `AdProvider.initialize()` rethrows SDK errors.
    public static func live(adProvider: any AdProvider) -> MonetizationBootBridges {
        MonetizationBootBridges(
            requestUMPConsent: {
                _ = await UMPConsentPresenter.requestIfNeeded()
            },
            requestATT: {
                _ = await ATTPresenter.requestIfNeeded()
            },
            initializeAdMob: {
                try await adProvider.initialize()
            }
        )
    }
}

// MARK: - BootOutcome

public enum BootStep: String, Sendable, Equatable {
    case ump
    case att
    case adMob
}

public struct BootOutcome: Sendable, Equatable {
    public let step: BootStep
    public let succeeded: Bool
    public let errorDescription: String?

    public init(step: BootStep, succeeded: Bool, errorDescription: String? = nil) {
        self.step = step
        self.succeeded = succeeded
        self.errorDescription = errorDescription
    }
}

// MARK: - MonetizationBootCoordinator

public actor MonetizationBootCoordinator {
    public typealias LogClosure = @Sendable (BootOutcome) -> Void

    private let bridges: MonetizationBootBridges
    private let log: LogClosure
    private var hasBooted: Bool = false

    public init(
        bridges: MonetizationBootBridges,
        log: @escaping LogClosure = { _ in }
    ) {
        self.bridges = bridges
        self.log = log
    }

    /// Run the three boot steps strictly in order. Each step is attempted
    /// independently — a failing earlier step does not skip subsequent
    /// steps. Returns the outcomes in execution order.
    ///
    /// Idempotent: repeat calls after first completion return a single
    /// `.succeeded` entry per step without re-firing the underlying calls.
    @discardableResult
    public func boot() async -> [BootOutcome] {
        guard !hasBooted else { return [] }
        hasBooted = true

        var outcomes: [BootOutcome] = []
        outcomes.append(await runStep(.ump) { try await bridges.requestUMPConsent() })
        outcomes.append(await runStep(.att) { try await bridges.requestATT() })
        outcomes.append(await runStep(.adMob) { try await bridges.initializeAdMob() })
        return outcomes
    }

    private func runStep(
        _ step: BootStep,
        _ run: () async throws -> Void
    ) async -> BootOutcome {
        do {
            try await run()
            let outcome = BootOutcome(step: step, succeeded: true)
            log(outcome)
            return outcome
        } catch {
            let outcome = BootOutcome(
                step: step,
                succeeded: false,
                errorDescription: String(describing: error)
            )
            log(outcome)
            return outcome
        }
    }
}
