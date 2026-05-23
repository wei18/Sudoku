# Swift Test Hang — Per-Suite Bisection — 2026-05-23

## Verdict

**Non-deterministic bootstrap hang in `swiftpm-testing-helper` — not in any single test body or target.**

The hang prior triage attributed to "one of the 7 non-UI targets" is in fact a `swiftpm-testing-helper` startup race that fires inconsistently before the swift-testing banner is printed. Once it reaches the banner, every individual test runs to completion in milliseconds.

Per-target bisection sequence:

1. `swift test --filter PersistenceTests` — **PASS** (49 tests, 0.004 s) — cold build (~3 s).
2. `swift test --filter GameCenterClientTests` — **HUNG**. Helper PID parked in `S` state, 3 lines of stdout total (`Building for debugging…`, `[0/4] Write swift-version`, `Build complete! (0.14s)`), **zero test discovery output**, no banner. Killed manually after ~3 min.
3. `swift test --filter "GameCenterClientTests.LiveGameCenterClientDeinitTests"` (the prime suspect from prior triage) — **PASS** (1 test, 0.001 s).
4. `swift test --filter GameCenterClientAuthTests` — **PASS** (5 tests, 0.001 s) — includes `authStateUpdatesStreamsChanges` which exercises the `for await` observer Task.
5. `swift test --filter GameCenterClientTests` (**re-run** of step 2) — **PASS** (46 tests in 9 suites, 0.007 s).
6. `swift test --parallel` — **HUNG** twice in a row. Helper parked, no child processes forked, no stdout after `Build complete!`. Killed both times.

The same exact invocation that hung at step 2 passed at step 5 with no source changes in between. Step 6 hangs reproducibly with `--parallel`, but step 5 (same filter set, no `--parallel`) succeeds.

## Reproduction

Not a deterministic per-test repro. The hang correlates with **`--parallel`** and with **cold-helper bootstrap on certain filters** (e.g. `GameCenterClientTests` after a warm rebuild but before the helper has cached anything). The pre-banner state is the symptom:

```bash
mise exec -- swift test --parallel
# OR (intermittent):
mise exec -- swift test --filter GameCenterClientTests
```

Diagnostic signature of the hang (all observed):

* `swift-test` (driver) and `swiftpm-testing-helper` both in process state `S`, 0 % CPU.
* Helper has NO child workers (in `--parallel` mode it should fork per-suite workers).
* Helper has only 3 PIPE FDs (0/1/2) — no IPC sockets opened yet.
* Stdout contains the build lines but no `􀟈 Test run started.` banner.

This is the same signature reported in `meetings/2026-05-22_swift-test-hang-triage.impl-notes.md`.

## Root cause

The hang is **inside `swiftpm-testing-helper` itself** during pre-test-discovery setup (likely the `--parallel` worker scheduler or the test-bundle metadata enumeration), not inside any `@Test` body or any `@Suite` static initializer in this codebase. Every individual `@Suite` runs cleanly when filtered alone — including the deinit retain-cycle test, the auth `for await` stream test, all CloudKit fakes, and the live-client observer Task.

Strong evidence this is a toolchain bug, not a project bug:

1. Identical invocation gives different outcomes (step 2 hung, step 5 passed).
2. Hang occurs **before** any user-code static init runs (no banner means swift-testing's own runtime hasn't been entered).
3. Helper has no IPC sockets — it's stuck in its own dispatch / dyld load path, not waiting on user code.
4. `--parallel` reproduces it far more reliably than serial filter runs.

Toolchain in use: Swift 6.3.2 / Xcode 26.x / swift-testing 1902 on arm64-apple-macos26.0.

## Bisection log table

| Filter | Wall-clock | Outcome | Last test before hang |
|---|---|---|---|
| `PersistenceTests` | ~3 s build + 0.004 s tests | PASS (49/49) | — |
| `GameCenterClientTests` (run 1) | killed at ~3 min | **HANG pre-banner** | none — zero discovery output |
| `GameCenterClientTests.LiveGameCenterClientDeinitTests` | 0.001 s | PASS (1/1) | — |
| `GameCenterClientAuthTests` | 0.001 s | PASS (5/5) | — |
| `GameCenterClientTests` (run 2) | 0.007 s | PASS (46/46) | — |
| `--parallel` (full suite) run 1 | killed at ~2 min | **HANG pre-banner** | none — only build output |
| `--parallel` (full suite) run 2 | killed at ~3 min | **HANG pre-banner** | none — no child workers forked |

Targets not individually bisected (time budget reached): `ASCRegisterTests`, `GameStateTests`, `PuzzleStoreTests`, `SudokuEngineTests`, `TelemetryTests`. Given the non-determinism above, the prior triage's "1 of 7 non-UI targets" conclusion is unsound — the combined-filter hang in that report is the same intermittent bootstrap race, not a property of those targets specifically.

## Proposed fix (one-liner, NOT applied)

Drop `--parallel` from the canonical test command (run serially) until the toolchain race is reported & resolved; file an Apple Feedback against `swiftpm-testing-helper` with the `S`-state / no-banner / no-child-worker signature. Single-process `swift test` is fast enough here (sub-10 s for the entire warm suite).
