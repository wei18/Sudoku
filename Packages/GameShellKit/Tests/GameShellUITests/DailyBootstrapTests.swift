import Testing
@testable import GameShellUI

// MARK: - performDailyBootstrap two-phase contract (#558)
//
// `performDailyBootstrap` is the shared skeleton both DailyHub VMs delegate to;
// it encodes the bug-prone #536/#526/#530 sequence. These tests pin the contract
// machine-checkably so a future signature/sequencing drift fails CI:
//   - happy path: setLoading → fetchPhase1 → onPhase1 → fetchPhase2 (in order)
//   - phase-1 error: setLoading → fetchPhase1(throws) → onPhase1Error, and
//     onPhase1 + fetchPhase2 are SKIPPED (never render/overlay on a failed fetch).

@Suite("GameShellUI — performDailyBootstrap two-phase contract")
@MainActor
struct DailyBootstrapTests {

    private struct SentinelError: Error {}

    @Test func happyPathRendersPhase1BeforePhase2() async {
        var order: [String] = []
        await performDailyBootstrap(
            setLoading: { order.append("loading") },
            fetchPhase1: { order.append("fetch1"); return 42 },
            onPhase1: { trio in order.append("render1(\(trio))") },
            onPhase1Error: { _ in order.append("error") },
            fetchPhase2: { trio in order.append("fill2(\(trio))") }
        )
        // Phase 1 render MUST complete before phase 2; no error path taken.
        #expect(order == ["loading", "fetch1", "render1(42)", "fill2(42)"])
    }

    @Test func phase1ErrorSkipsRenderAndOverlay() async {
        var order: [String] = []
        await performDailyBootstrap(
            setLoading: { order.append("loading") },
            fetchPhase1: { () async throws -> Int in
                order.append("fetch1")
                throw SentinelError()
            },
            onPhase1: { _ in order.append("render1") },
            onPhase1Error: { _ in order.append("error") },
            fetchPhase2: { _ in order.append("fill2") }
        )
        // On a phase-1 throw: error funnel runs; render + overlay are skipped.
        #expect(order == ["loading", "fetch1", "error"])
    }
}
