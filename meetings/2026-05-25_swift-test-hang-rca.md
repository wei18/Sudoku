# RCA — Recurring `swift test` Hang + lefthook Deadlock

> **Note**: This file is a Leader reconstruction (2026-05-25 16:55 GMT+8) after the original 261-line RCA doc — produced by a Senior Developer subagent and written to the main checkout — was accidentally removed via `git clean -fd` during a working-tree cleanup. The reconstruction captures the subagent's reported TL;DR, hypotheses, and recommended fix verbatim from the return message; the supporting evidence-index and prevention sections are summarized from the subagent's reply, not the original prose. The original investigation transcript is preserved in the subagent's JSONL output.

## TL;DR

`swift test` from `Packages/SudokuKit/` with no `--filter` hangs the toolchain for 18–68+ min, requiring `kill -9` of `swift-test` + `swiftpm-testing-helper`. Concurrent `mise exec swiftlint` / `gitleaks` invoked by lefthook pre-commit then deadlock as collateral damage.

**Primary root cause**: `MonetizationStateController.bootstrap()` unconditionally spawns a `Task { for await event in iapClient.purchaseUpdates() }` that only exits on the controller's `deinit`. swift-testing keeps suite instances alive for the full run, and `FakeIAPClient.finishUpdates()` is called by zero tests. Under swift-testing 6.2's default parallelism (Apple Silicon, Xcode 16+, swift-tools 6.2, strict concurrency), 19 leaked long-lived `@MainActor` tasks accumulate and deadlock against 17 `@MainActor`-isolated snapshot suites all contending for the same global actor.

## Hypotheses (ranked by evidence weight)

### H1 [PRIMARY, very strong] — Leaked `for await` on `FakeIAPClient.purchaseUpdates()`
- `MonetizationStateController.bootstrap()` spawns a never-terminating Task subscribed to `iapClient.purchaseUpdates()`
- Task lifetime tied to controller `deinit`; swift-testing holds suite instance for entire run
- `FakeIAPClient.finishUpdates()` exists but is called by **zero tests**
- 19 tests × 1 leaked main-actor task each → main-actor saturation
- Cross-references same pattern documented at `PracticeHubViewTests.swift:35-45`

### H2 [SECONDARY, supporting] — `LiveGameCenterClient` retain-cycle pattern
- Similar long-lived listener pattern in GameCenterClient; not the trigger here but a latent risk for next hang
- Out of scope for this RCA's immediate fix

### H3 [WEAK, ruled out] — Real CloudKit / GameCenter network in tests
- Test setup uses fakes; no real network calls in the hung path

### H4 [WEAK] — `mise` process cache contention
- Lefthook deadlock is downstream symptom, not root cause; resolved automatically once H1 is fixed
- May still warrant a lefthook ordering improvement (run swiftlint OR gitleaks, not both concurrently under mise)

### H5 [RULED OUT] — Toolchain version mismatch
- swift-tools 6.2 in Package.swift vs Xcode 16 bundled toolchain → no incompatibility found

## Evidence Index (file:line)
- `Packages/SudokuKit/Sources/SudokuUI/Components/MonetizationStateController.swift` — `bootstrap()` spawns the leaking Task
- `Packages/SudokuKit/Sources/AppComposition/Live.swift` — sole production caller of `bootstrap()`
- `Packages/SudokuKit/Tests/SudokuUITests/MonetizationStateControllerUpdatesTests.swift` — 4 tests exercising `purchaseUpdates()` without explicit teardown
- `Packages/AppMonetizationKit/Sources/MonetizationTesting/FakeIAPClient.swift` — `finishUpdates()` exists but never invoked
- `Packages/SudokuKit/Tests/SudokuUITests/PracticeHubViewTests.swift:35-45` — prior documentation of same main-actor contention mode

## Fix (smallest viable diff)

### Fix A (minimum — unblocks `swift test`)
Add `defer { await iap.finishUpdates() }` (or equivalent) to every test that constructs a `MonetizationStateController`. Suppresses symptom, doesn't fix root cause. Not recommended as sole fix.

### Fix B [RECOMMENDED — surgical, single concern]
Split `MonetizationStateController.bootstrap()` into two methods:
- `bootstrap()` keeps only the one-shot reads (no `Task { for await }` spawned)
- New `startListeningForLifetimeOfApp()` contains the `purchaseUpdates()` subscription

Update production caller in `AppComposition.live` to call `bootstrap()` then `startListeningForLifetimeOfApp()` back-to-back at app boot.

Update the 4 `purchaseUpdates`-specific tests in `MonetizationStateControllerUpdatesTests.swift` to call `startListeningForLifetimeOfApp()` explicitly AND include `defer { await iap.finishUpdates() }` so the suite instance doesn't leak the for-await.

Total touched files: **3** (controller + AppComposition.live + one test file). No overlap with #67 (Telemetry/error funnel) or #64 (Persistence/GameCenter dead-code triage).

### Fix C [BELT-AND-SUSPENDERS — also recommended]
After Fix B lands, add a swift-testing `.serialized` trait to any remaining `@MainActor` suite that touches monetization state, so future leaks degrade gracefully instead of deadlocking.

## Prevention
- **CI guard**: add a test target health check that asserts each `@MainActor` suite either uses `.serialized` or proves no Task leaks
- **Lefthook ordering**: pipe swiftlint → gitleaks sequentially (not parallel) to avoid mise cache contention
- **Default test command**: README + subagent dispatch contract should default to `swift test --filter <TestName>` until full-suite hang is fixed; once Fix B lands, the no-filter default can return
- **Pattern lint**: any `Task { for await }` spawned in `bootstrap()`-style init methods is a yellow flag — should be in a named `startListening...` method with explicit lifecycle

## Workaround for now (until fix lands)
Until Fix B is merged, subagent dispatch contracts must:
- Run targeted tests only: `swift test --filter <TestName>`
- If full suite needed, wrap with `timeout 600` and treat timeout as expected
- Never use `--no-verify` to bypass lefthook deadlock — kill the stuck swift-test instead, then retry commit

## Open Questions for Leader / User
- After Fix B lands, do we run the full suite once to confirm + then update plan §Backlog with Fix C?
- Should Fix C ship in same PR as Fix B, or follow-up?
- Lefthook ordering change — separate PR or bundle with Fix B?

## Out of scope (NOT changed by this RCA)
- H2 LiveGameCenterClient retain-cycle pattern (separate investigation)
- AppMonetizationKit package internals
- Any code under `Packages/SudokuKit/Sources/Persistence/` (#64 territory)
- Any code under `Packages/SudokuKit/Sources/Telemetry/` or `UserFacingError`/`ErrorReporter` paths (#67 territory)
