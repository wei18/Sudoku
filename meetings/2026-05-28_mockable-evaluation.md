# Mockable Evaluation (issue #173)

**Date**: 2026-05-28
**Library**: [`Kolos65/Mockable`](https://github.com/Kolos65/Mockable) — Swift macro-based mock framework (`@Mockable` decorator generates protocol mocks + `given`/`when`/`verify` DSL)
**Latest release**: v0.6.2 (2026-03-18)
**License**: MIT

---

## Verdict: **DEFER**

Re-evaluate when **any of**:
1. Hand-written fakes ≥ 200 lines individually OR aggregate count > 15 fakes (current: 11 fakes / 1015 lines; ceiling 5 above the 100-line mark)
2. ≥ 3 distinct CR feedback iterations on fake boilerplate (current: 1 found in `meetings/`)
3. Swift 6 strict concurrency support is formally documented in Mockable (current: silent on the topic in README — concerning)
4. Mockable ships v1.0 (current: v0.6.2 = pre-1.0, API stability not promised)
5. Adopting another framework that pulls Mockable transitively (e.g., TCA dependency tree) — adoption becomes consolidation, not addition

---

## Evidence

### Current fakes inventory (1015 LOC across 11 files)

```
find Packages -name "Fake*.swift" -not -path "*/.build/*"
```

| Fake | LOC | Protocol |
|------|-----|----------|
| `FakeGameCenterClient` | 156 | `GameCenterClient` |
| `FakePrivateCKGateway` | 133 | `PrivateCKGateway` |
| `FakePersistence` | 125 | `Persistence` |
| `FakeIAPClient` | 121 | `IAPClient` |
| `FakeGenerator` | 119 | `PuzzleGenerator` |
| `FakePuzzleProvider` | ~80 | `PuzzleProvider` |
| `FakeAdProvider` | ~70 | `AdProvider` |
| `FakeAdGateStateStore` | ~60 | `AdGateStateStore` |
| `FakeAuthDriver` | ~50 | `AuthDriver` |
| `FakeLeaderboardLoader` | ~50 | `LeaderboardLoader` |
| `FakeLogger` | ~50 | `LoggerProtocol` |

### Trigger-condition assessment (from issue #173)

| Trigger | Status | Evidence |
|---------|--------|----------|
| (a) hand-written fakes > 5 large protocols | **Borderline** | 5 fakes ≥ 100 LOC — at threshold, not over |
| (b) repeated fake boilerplate CR feedback > 3 times | **Not met** | Single match in `meetings/`: `2026-05-20_route-destination-wireup` |
| (c) want unified preview/test/canary mock mode | **Not wanted** | No active demand surfaced in session logs |

### Side-by-side: `FakeGameCenterClient` (the largest fake, 156 LOC)

**Hand-rolled** (current):
```swift
public actor FakeGameCenterClient: GameCenterClient {
    public var authResult: Result<PlayerSummary, GameCenterError>?
    public var leaderboardSlice: LeaderboardSlice?
    public private(set) var operations: [Operation] = []
    public func setAuthResult(_ r: Result<…>?) { … }
    public func setLeaderboardSlice(_ s: LeaderboardSlice) { … }
    public func authenticate() async throws -> PlayerSummary {
        operations.append(.authenticate)
        switch authResult { … }
    }
    // ~150 more lines of similar pattern
}
```

**Mockable-generated** (hypothetical):
```swift
@Mockable
public protocol GameCenterClient {
    func authenticate() async throws -> PlayerSummary
    func fetchLeaderboardSlice(…) async throws -> LeaderboardSlice
    // …
}

// Test usage:
let mock = MockGameCenterClient()
given(mock).authenticate().willReturn(player)
let result = try await mock.authenticate()
verify(mock).authenticate().called(1)
```

**Trade-off**:
- ✅ ~150 LOC of boilerplate removed per large fake (potentially 750+ LOC across the 5 large ones)
- ✅ DSL is uniform; no per-fake API to memorize
- ❌ Compile-time cost: SwiftSyntax + macro expansion adds notable build time (not measured in our codebase but well-documented elsewhere)
- ❌ Pre-v1.0; API may shift before stable
- ❌ Loss of explicit `actor` isolation control on the fake itself (Mockable's actor story under Swift 6 is undocumented)

### §9 break-glass checklist

| Item | Status |
|------|--------|
| License | ✓ MIT |
| Privacy manifest impact | ✓ Zero (test-only) |
| Binary size | ✓ Zero (test-only, not in App binary) |
| Isolation strategy | ✓ Test-target only, no production reach |
| Swift 6 strict concurrency | **? Unconfirmed** — README + CHANGELOG silent |
| API stability | **? Unconfirmed** — v0.6.2 = pre-1.0 |
| Build-time cost | **? Unconfirmed** — SwiftSyntax macro tax not measured |

Per `docs/foundations.md §9`, an "Unconfirmed" item blocks adoption. **3 items Unconfirmed → adoption blocked until verified or triggers warrant the spike.**

### Why DEFER (not REJECT)

The framework is sound and the boilerplate reduction is real. We're not against it; the triggers haven't fired. Once we add (say) 4 more large protocols to the project (likely with v3 features), trigger (a) clears comfortably and the Swift 6 question can be revisited against a then-current Mockable release.

### Why DEFER (not ADOPT now)

Replacing 11 working fakes is meaningful churn (file moves, test rewrites, snapshot-baseline re-recording for any tests where fake construction is captured). The benefit ledger is conditional on triggers we haven't hit. Adopt-then-discover-Swift-6-issue is the worst path.

---

## Open questions parked

- Does Mockable's generated mock retain `actor` isolation correctly for `actor`-typed protocols under Swift 6 strict mode? (READ ME-silent)
- What's the measured build-time hit on this codebase? (would need to spike a single migration to know)

These are answerable in a < 1-day spike when triggers warrant it.

---

## 2026-05-28 Addendum — implementation attempted, DEFER reaffirmed

User overrode the initial DEFER verdict and asked for implementation. **4 dispatch attempts followed; none reached a commit.** Cumulative evidence reinforces — does NOT contradict — the original DEFER verdict.

### Dispatch attempts + outcomes

| # | Scope | Outcome |
|---|-------|---------|
| 1 | Full-scope WebFetch eval | Blocked on WebFetch permission (later worked around by using `gh api`) |
| 2 | Stage 1 spike | **Useful findings**: Swift 6 strict concurrency Verified ✓ on Sendable protocol; build-time cost Measured ✓ (~30s one-time SwiftSyntax + 30% test-cycle overhead). **New blocker**: 6 of 11 fakes record `operations:[Op]` arrays + tests pattern-match captured args — Mockable's `verify(...).called(n)` can't expose captured arg values |
| 3 | Full Path B re-dispatch | Paused before any commit — surfaced 3 more architectural blockers: `Preview.swift` (Release-build production) uses `FakeAdProvider` + `FakeAdGateStateStore`, but Mockable's `MOCKING` flag is `.debug`-only → Release wouldn't compile. `CompositionTests` has `type(of:).contains("FakeAdProvider")` string-identity check. `FakeShapesTests` tests fake-internal scripting that becomes degenerate under Mockable |
| 4 | Scoped Path B + Preview refactor | Watchdog killed — stalled 600s+ no progress. Recoverable but signals task complexity exceeded subagent execution budget |

### Leader inline re-inspection of FakeLeaderboardLoader (the previously-flagged "clean simple fake")

Tests assert `let calls = await loader.calls; #expect(calls[0].around == "P50")`. **Same DSL gap**. The `operations`/`calls`-array pattern is not isolated to the "stateful 6" — it's the canonical pattern across most fakes in this codebase.

### What "ADOPT" would look like, accurately

Migrating fakes uniformly would require, per fake:
- Mockable `@Mockable` on the protocol (adds Mockable + MOCKING gate to production target)
- Sidecar `actor Captured { var calls: [Call]; ... }` to replace the deleted Fake's `calls` accumulator
- Rewrite each test assertion site from `await fake.calls[0].around` to `await captured.calls[0].around`
- For `Preview.swift` consumers: new hand-rolled `PreviewX` stub types (because MOCKING is debug-only)

Net delta vs current state: **the hand-rolled fakes are simpler than the sidecar+mock combo would be**. Mockable's value proposition is "reduce boilerplate" — but the boilerplate here is the `calls` accumulator + helpers, which Mockable doesn't replace (you just rebuild it as a sidecar actor).

### Final verdict: **DEFER reaffirmed** (stronger evidence than initial eval)

Re-trigger conditions (revised):
1. Mockable ships v1.0+ AND README documents Swift 6 `actor` isolation guarantee
2. ≥ 3 hand-written fakes ADDED to the codebase where the protocol does NOT have an `operations`/`calls` recording pattern (i.e., pure request-response protocols Mockable's DSL fits cleanly)
3. The codebase adopts another library that pulls Mockable transitively (consolidation, not addition)

### Artifacts from this attempt
- 4 worktree branches, all reverted clean: `feat/mockable-full-adoption`, `feat/mockable-stage-b`, etc.
- Worktree `/Users/zw/GitHub/Wei18/Sudoku-mockable` will be removed at session close
- Eval PR #193 stays as the source-of-truth doc
- No production code touched on `main`
