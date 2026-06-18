// DailyBootstrap — shared two-phase daily-hub orchestration skeleton.
//
// Captures the bug-prone pattern (#536 / #526 / #530): idempotency latch
// (hasBootstrapped, owned by the caller) + two-phase load:
//   Phase 1: fetch the trio → render cards immediately (no CloudKit dependency).
//   Phase 2: best-effort async overlay fill (completion / failure ids) that
//             NEVER blocks the initial render and degrades silently on hang/error.
//
// GameShellUI is zero-dependency: the skeleton is pure control flow over injected
// closures. ErrorReporter, PersistenceProtocol, and per-game state types stay in
// the calling VM — the skeleton is intentionally unaware of them.
//
// The phase-1 result (e.g. the fetched trio) is threaded through to the phase-2
// closure via a generic type parameter `Trio`, avoiding a transient stored property
// on the VM and keeping the two phases visibly coupled in the call site.
//
// Usage (each calling VM):
//   guard !hasBootstrapped else { return }
//   hasBootstrapped = true
//   await performDailyBootstrap(
//       setLoading:    { state = .loading },
//       fetchPhase1:   { /* async throws provider call; return trio */ },
//       onPhase1:      { trio in state = .loaded(makeCards(trio)) },
//       onPhase1Error: { error in /* error funnel + state = .failed / .empty */ },
//       fetchPhase2:   { trio in /* async overlay fetch + re-apply state */ }
//   )

// MARK: - Two-phase daily bootstrap

/// Executes the two-phase daily-hub load sequence.
///
/// - Parameters:
///   - setLoading:    Called synchronously first; sets the VM state to `.loading`.
///   - fetchPhase1:   Async-throws closure: fetches the daily trio and returns it.
///   - onPhase1:      Called synchronously (on MainActor) with the fetched trio to
///                    set the VM state to `.loaded` with un-marked cards. The
///                    initial render is complete before phase 2 runs.
///   - onPhase1Error: Called when `fetchPhase1` throws. Responsible for error
///                    reporting and setting a terminal state (`.failed` / `.empty`).
///                    Phase 2 is skipped after a phase-1 error.
///   - fetchPhase2:   Best-effort async closure receiving the fetched trio: fetches
///                    overlay data (completed / failed ids) and re-merges cards into
///                    state. Errors must be swallowed inside this closure; the
///                    skeleton never sees them. Called only after phase 1 succeeds.
@MainActor
public func performDailyBootstrap<Trio: Sendable>(
    setLoading: () -> Void,
    fetchPhase1: () async throws -> Trio,
    onPhase1: (Trio) -> Void,
    onPhase1Error: (any Error) async -> Void,
    fetchPhase2: (Trio) async -> Void
) async {
    setLoading()
    let trio: Trio
    do {
        trio = try await fetchPhase1()
    } catch {
        await onPhase1Error(error)
        return
    }
    onPhase1(trio)
    await fetchPhase2(trio)
}
