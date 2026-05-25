# Impl Notes — issue #64 dead-code triage (2026-05-25)

Status: IN_PROGRESS (Phase 2)
Owner: Senior Developer (subagent)
Dispatched by: Leader
Started: 2026-05-25
Phase: 2 of 2 — execution (Leader chose CONSERVATIVE scope)

## Scope

Issue #64 lists 5 types with allegedly zero production consumers. Verify reality vs. spec, propose per-file verdict (Wire vs Delete-and-defer).

## Verification method

For each type:

1. `rg -l <TypeName> Packages/SudokuKit/Sources` to confirm production-side reference count
2. Inspect candidate wiring sites (`LivePersistence.swift`, `AppComposition/Live.swift`, `LiveGameCenterClient.swift`)
3. Cross-check against `docs/v1/design.md` section the type implements

## Verdict table

| File | Verdict | Wiring touchpoint OR design.md section to defer | Effort (LOC) | Risk |
|---|---|---|---|---|
| `Persistence/Live/ConflictResolver.swift` | **Wire** | `SavedGameStore.save(...)` + `PersonalRecordStore.upsert(...)` wrap their `CKModifyRecordsOperation` in `RetryHarness.run` and call `ConflictResolver.resolve(local:server:)` on `serverRecordChanged` | ~60 (two save paths × ~25 LOC each + tests already exist) | Medium — touches live CloudKit save paths; requires careful integration test against `LivePrivateCKGateway` mock |
| `Persistence/Live/AccountMonitor.swift` | **Wire** | `AppComposition.live()` constructs an `AccountMonitor` with a Live `ICloudAccountProvider` (wrap `CKContainer`) + Keychain impl; root view's `.task` calls `handleAccountChange()` on launch and on `CKAccountChanged` Notification. Outcome routes to Alert + LocalCache wipe in composition root | ~120 (LiveAccountProvider + LiveUserHashKeychain + NotificationCenter wiring + root view glue) | High — depends on real CKContainer + Keychain entitlements; partner with LocalCache wiring (Case B/C wipe) |
| `Persistence/Live/LocalCache.swift` | **Wire** (paired with AccountMonitor) | Inject into `SavedGameStore` as offline-flush sink (Case B: flush snapshot on `iCloudSignedOutDuringSession`); `AccountMonitor.switched` outcome triggers `wipe()` (Case C) | ~80 (constructor injection through `LivePersistence` → `SavedGameStore`; flush hook in save path) | High — changes SavedGameStore's failure semantics; must not regress online happy-path |
| `Persistence/Live/SubscriptionInstaller.swift` | **Delete** | Redundant. `LivePersistence.bootstrap()` already calls `gateway.installSubscriptionIfNeeded()` directly (LivePersistence.swift:73). The installer is a 22-LOC pass-through with no caller. Spec §How.2 is already satisfied by `bootstrap()` | ~22 LOC removed + test file (~31 LOC) — net negative diff | Low — pure deletion, behavior identical |
| `GameCenterClient/Leaderboard/Slice.swift` (contains `LeaderboardLoader` + `LeaderboardSliceService`) | **Wire** | `LiveGameCenterClient.fetchLeaderboardSlice` currently throws `.notAuthenticated` (line 174). Replace stub body with `LeaderboardSliceService.fetch(loader: GKLeaderboardLoader(), friendsStatus: { self.friendsAuthorizationStatus() }, requestFriendsAuthorization: { try await self.requestFriendsAuthorization() }, ...)`. Construct `LiveGameCenterClient` with an injected `LeaderboardLoader` (default = new `GKLeaderboardLoader` wrapping `GKLeaderboard.loadEntries`) | ~80 (LoadEntries-based `GKLeaderboardLoader` + constructor param + stub replacement) | Medium — touches CompletionView's only data source; existing fake-based tests in `LeaderboardSliceTests` cover the friends-auth gating |

## Per-file justification

### 1. ConflictResolver.swift — Wire

The type's responsibility is the canonical LWW merge defined by §How.6.7. Both record types in v1 (`SavedGame`, `PersonalRecord`) have save paths in `SavedGameStore`/`PersonalRecordStore` and neither currently performs the documented 2-retry merge — `rg ConflictResolver|RetryHarness` against the sibling Store files returned zero hits. The unit tests (146 LOC in `ConflictResolverTests`) already cover the pure-function correctness, so wiring is purely an integration concern: have the stores fetch `serverRecord` on `CKError.serverRecordChanged`, project into `SavedGameSnapshot`, call `resolve`, and re-submit. Spec is explicit ("最多 retry 2 次，第 3 次仍衝突 → throw `CloudKitOpError.syncConflict`") and matches `ConflictResolver.maxRetries = 2` exactly — deletion would be a regression against documented behavior.

### 2. AccountMonitor.swift — Wire

Implements §How.6.5 Cases A/B/C verbatim (the file header lines 1–14 quote the spec). The `AccountChangeOutcome` enum is exactly the contract the root composition needs to drive Alert + LocalCache wipe. Currently `AppComposition.live()` constructs `LivePersistence` and `LiveGameCenterClient` but never instantiates `AccountMonitor` — meaning the spec's Case C cross-account isolation guarantee is **silently violated in v1**, which is a correctness risk if a user signs into a second iCloud account on the same device. This is the highest-risk gap in the issue; wiring is mandatory unless we explicitly defer Case A/B/C handling to v2 in design.md.

### 3. LocalCache.swift — Wire (paired)

§How.6.5 Case A ("本機 SavedGame cache 保留") and Case B ("立即 flush GameViewModel 至本機") both rely on a writable local cache surviving CloudKit unavailability. Currently `SavedGameStore` writes directly through `LivePrivateCKGateway` with no offline fallback — `AccountFlowTests` only exercises the type in isolation. Without LocalCache, Case B's "進度已保留在本機" promise is undeliverable. Effort and risk are tightly coupled to AccountMonitor (both share the Case A/B/C event flow), so they should be wired in the same PR or sequenced consecutively.

### 4. SubscriptionInstaller.swift — Delete

`LivePersistence.bootstrap()` (line 73) already calls `gateway.installSubscriptionIfNeeded()` directly. `SubscriptionInstaller` is a 22-LOC named-handle wrapper around exactly that one call, with zero production callers. The file header justifies it as "so the App composition root has a named handle to call at launch" — but `AppComposition.live()` does not call it, and `LivePersistence.bootstrap()` already owns that responsibility. This is genuine duplication; deletion is non-breaking and the (small) `SubscriptionTests.swift` can be deleted alongside since the actual subscription install is covered by `LivePrivateCKGatewayTests` (or should be — out of scope for Phase 2).

### 5. Slice.swift (`LeaderboardSliceService`) — Wire

`LiveGameCenterClient.fetchLeaderboardSlice` is a `throw .notAuthenticated` stub (line 167–175), so `CompletionView`'s mini-slice is currently always-failing on a real device. `LeaderboardSliceService.fetch` is precisely the friends-auth-gated forwarder the spec §How.3.5 describes, and `LeaderboardSliceTests` (133 LOC) already covers the gating logic via fake loader. The missing piece is a tiny `GKLeaderboardLoader` adapter (wraps `GKLeaderboard.loadEntries` from §How.3.5) plus replacing the stub body. Note §How.3.5 changed in issue #49 (2026-05-20) — friends scope is now Apple's native dashboard, but `globalAllTime` mini-slice (the CompletionView use case) remains in scope.

## Open questions for Leader

- **Q1 — Pairing of AccountMonitor + LocalCache**: Should Phase 2 ship these as a single PR (atomic Case A/B/C wiring) or split into two sequenced PRs (monitor first, cache second)? Recommendation: single PR — the outcome enum has no value without the wipe sink.
- **Q2 — SubscriptionInstaller deletion scope**: Delete the test file `SubscriptionTests.swift` too, or repurpose its assertions against `LivePrivateCKGateway.installSubscriptionIfNeeded()` directly? Recommendation: delete both — test coverage of the gateway method belongs in `LivePrivateCKGatewayTests`.
- **Q3 — Phase 2 sequencing**: Recommended order by risk/dependency — (a) SubscriptionInstaller delete [Low, isolated], (b) ConflictResolver wire [Medium, save-path integration], (c) Slice/LeaderboardSliceService wire [Medium, GameCenter stub replacement], (d) AccountMonitor + LocalCache combined [High, root composition + LiveAccountProvider + Keychain]. Confirm or re-order.
- **Q4 — Live dependencies for AccountMonitor**: The `ICloudAccountProvider` and `UserHashKeychain` Live impls do not yet exist anywhere in the codebase. Phase 2 must include them; flag if there's a preferred Keychain wrapper already used elsewhere (`rg -l KeychainAccess|SecItemAdd Packages/` returned nothing — net-new code).

## Notes

- Issue title says "LeaderboardSliceService.swift" but the actual file is `Slice.swift` (contains both `LeaderboardLoader` protocol and `LeaderboardSliceService` enum). Not a bug, just naming drift.
- All 5 files have working test coverage; Phase 2 wiring should not need new unit tests for the types themselves — only integration tests at the wiring seam.
- No file in the list has a hidden production consumer. Issue's "zero production consumers" claim is verified accurate.

---

## Phase 2 — Leader-approved execution (CONSERVATIVE)

Leader diverged from Phase 1 proposal: AccountMonitor + LocalCache deferred (require net-new `ICloudAccountProvider`/`UserHashKeychain` Live impls — net-new feature scope inappropriate before App Store submission). Only ConflictResolver + LeaderboardSliceService are wired.

### 偏離 (Deviations from Phase 1 verdict)

- **AccountMonitor → Delete (was Wire)** — Leader: net-new Live `ICloudAccountProvider` (CKContainer wrap) + `UserHashKeychain` (Keychain Services wrap) is feature-scope work; ship as a proper post-v2.5 issue. design.md §How.6.5 keeps the spec; "deferred post-v2.5" note added.
- **LocalCache → Delete (was Wire-paired)** — Same rationale; useless without AccountMonitor's outcome routing to drive `wipe()`.
- **SubscriptionInstaller → Delete (unchanged from Phase 1)** — Duplicates `LivePersistence.bootstrap()`'s direct call to `gateway.installSubscriptionIfNeeded()`.

### 設計決定 (Wiring)

- **ConflictResolver wiring** — `SavedGameStore.save(...)` and `PersonalRecordStore.upsert(...)` wrap their `gateway.save` calls in `RetryHarness.run`. On `PersistenceError.syncConflict(recordName:)` from the gateway, the body re-fetches via `gateway.fetch(recordName:)`, projects local + server into snapshots, runs `ConflictResolver.resolve(local:server:)`, and returns `.conflict` to drive the next retry. Since `FakePrivateCKGateway` doesn't yet model "throw conflict once then succeed", I add a small failure-mode extension `.conflictThenSuccess(count:)` to support the new wiring test.
- **LeaderboardSliceService wiring** — `LiveGameCenterClient` gains an injected `LeaderboardLoader` (default: `GKLeaderboardLoader()` adapter). `fetchLeaderboardSlice` body becomes a single `LeaderboardSliceService.fetch(...)` call with closures referencing `self.friendsAuthorizationStatus()` / `self.requestFriendsAuthorization()`.
- **GKLeaderboardLoader adapter** — new file `Packages/SudokuKit/Sources/GameCenterClient/Live/GKLeaderboardLoader.swift`, internal struct conforming to `LeaderboardLoader`, wraps `GKLeaderboard.loadLeaderboards(IDs:)` + `loadEntries(for:timeScope:range:)`. Compile-only in Phase 2 (live behavior validated in plan.md Phase 10 manual device).

### 折衷 (Tradeoffs)

- **PersonalRecord conflict path** — The `upsert` taken alone only writes (no fetch/merge round-trip in non-conflict path), so wiring `ConflictResolver.resolve(local:server:)` only fires on the retry leg. This matches §How.6.7 ("fetch `serverRecord` → 合成新 record → 重發 modify"). The `recordCompletion` callers go through `upsert` so they inherit the same protection.
- **Test seam: extend FakePrivateCKGateway vs new SpyGateway** — Extending the existing fake with `.conflictThenSuccess(count:)` keeps the test surface flat. New gateway would require duplicating ~100 LOC of fake state.
- **GKLeaderboardLoader range/timeScope** — `LeaderboardSliceService` doesn't pass timeScope; the adapter maps `LeaderboardScope` → `GKLeaderboard.PlayerScope` and uses `.allTime` time scope for `.globalAllTime` / `.friendsAllTime`, `.today` for `.globalToday`. Mirrors §How.3.5 v1 wiring.

### Sequencing log

1. Delete SubscriptionInstaller + SubscriptionTests + LivePersistence comment fix + design.md note → commit 1
2. Delete AccountMonitor + FakeAccountProvider + AccountFlowTests (whole file: it tests only deleted types) + LivePersistence comment fix + design.md note → commit 2
3. Delete LocalCache + design.md note → commit 3
4. Wire ConflictResolver into SavedGameStore + PersonalRecordStore + extend FakePrivateCKGateway with conflict failure mode + new ConflictWiringTests → commit 4
5. Wire LeaderboardSliceService into LiveGameCenterClient + new GKLeaderboardLoader adapter + LiveGameCenterClient wiring test → commit 5

### 未決 (Open questions)

None blocking; Leader's scope decision resolved Q1/Q2/Q3/Q4 from Phase 1.

---

## Phase 2 — Execution log (2026-05-25, 4th attempt — landed)

Branch: `worktree-agent-a7a1b56b1d52b424c` (on top of `wip/issue-64-phase1` @ 4e3019d).

Commits landed (4 new on top of inherited):

1. `4e80c7e` — refactor(persistence): delete AccountMonitor + AccountFlowTests + FakeAccountProvider; design.md §How.6.5 deferred-status banner.
2. `e0aa24b` — refactor(persistence): delete LocalCache.
3. `6a764f8` — feat(persistence): wire ConflictResolver/RetryHarness into SavedGameStore.save + PersonalRecordStore.upsert; FakePrivateCKGateway gains `setConflictOnSaveTimes(_:recordName:)`; ConflictWiringTests (4); design.md §How.6.7 status callout.
4. `3c95e29` — feat(game-center): wire LeaderboardSliceService into LiveGameCenterClient.fetchLeaderboardSlice; new GKLeaderboardLoader adapter; LiveGameCenterClientLeaderboardSliceTests (3); SavedGameStore line-length tidy carryover.

### 偏離 (Deviations from Phase 2 plan)

- **Step 1 (SubscriptionInstaller delete) inherited from `4e3019d`** — not redone; already committed by prior attempt.
- **Conflict merge done at the payload layer, not snapshot layer** — original plan was to project both sides to `GameSessionSnapshot`, merge, then re-encode via `SavedGameMapper`. Doing this required reconstructing a `Board` via the private `Board(encoded:against:)` extension on `SavedGameMapper`, plus duplicating `NotesEnvelope` / `UndoEnvelope` Codable shapes. Cleaner: project payloads into `ConflictResolver.SavedGameSnapshot`, run resolver, write resolved fields back into the local payload's `fields` dict — preserves non-LWW fields (`puzzleId` / `mode` / `difficulty` / `startedAt`) implicitly and avoids re-encoding round-trips. Same observable behavior; fewer moving parts.
- **MutableRef actor** — Swift 6 strict concurrency forbids mutating captured vars from `@Sendable` closures. Introduced a small file-scope `internal actor MutableRef<Value: Sendable>` (in `SavedGameStore.swift`) to hold the per-attempt working payload / record. Reused by both stores. Considered alternative: make `RetryHarness.run`'s body inout — rejected because it would push concurrency semantics across an existing API surface that has clean tests (`ConflictResolverTests`).
- **GKLeaderboardLoader marked `public struct`, not `internal`** — `LiveGameCenterClient.init` exposes `leaderboardLoader:` as a public default param, so the type must be public to be the default value. Compile-only `#if canImport(GameKit)` body; non-Apple fallback throws `.notAuthenticated`.
- **`around: player` not yet plumbed into GKLeaderboard** — the live adapter takes the param but currently ignores it (loadEntries range starts at rank 1). Spec §How.3.5 doesn't require around-player for v1 mini-slice; flagged as Phase 10 follow-up via inline comment.

### 折衷 (Tradeoffs)

- **`FakePrivateCKGateway.setConflictOnSaveTimes` semantics** — chose "throw N times then succeed" instead of "always conflict / never conflict" modes. The 3-arg form (`(times, recordName)`) keeps the test surface narrow but means budget-exhaustion tests script exactly `maxRetries + 1` conflicts. Considered: a callback `(RecordPayload) -> Decision` — rejected as overkill for the 4 wiring tests.
- **Sendable closure capture of `gateway` / `clock`** — copied to local lets `gatewayRef` / `clockRef` before the RetryHarness call to avoid re-capturing `self` and to keep the closure body's `await` chain readable. Closure body never touches `self` directly.

### 驗證 (Verification)

- `swift build` clean between each step.
- `swift test --filter ConflictWiring` — 4/4 passed (0.001s).
- `swift test --filter LeaderboardSlice` — 9/9 passed (3 new + 6 existing; 0.001s).
- `swift test --filter Persistence` — 48/48 passed.
- Full suite: running in background.
- `grep -r "AccountMonitor\|LocalCache\|SubscriptionInstaller" Packages/SudokuKit/Sources/` → 0 hits.

### Discipline notes

- Commit-after-every-step discipline held (4 separate commits, hooks ran <1s sequentially each, no `--no-verify`).
- Two lefthook warnings observed but non-blocking: SavedGameStore line-length (fixed in commit 4); GKLeaderboardLoader function_body_length (acceptable — 53 lines for a CloudKit-style adapter is within reason); test type-name length (acceptable — descriptive integration-test class name).
