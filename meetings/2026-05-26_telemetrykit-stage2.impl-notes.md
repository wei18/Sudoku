# 2026-05-26 — TelemetryKit Stage 2 carve-out impl notes

## Scope
Resumed Stage 2 from a clean base off `origin/feat/telemetrykit-extraction @ f87a35e` (prior WIP `wip/telemetrykit-testing-extract` had over-broad sed pollution and was abandoned by direction). Mission: get TelemetryTests compiling without introducing a reverse dep from TelemetryKit → SudokuKit.

## Decisions

### D1 — TelemetryTesting deps trimmed to just `Telemetry`
Brief said test target previously listed `SudokuEngine` + `GameState`. Per-file inspection of the 3 carved files showed:
- `FakeLogger.swift` — `public import Telemetry` only
- `RecordingSink.swift` — `public import Telemetry` only
- `MetricPayloadFixtures.swift` — no imports (pure string constants)

So the new `TelemetryTesting` target only declares `dependencies: ["Telemetry"]`. SudokuCoreKit products are NOT needed at the target level — TelemetryTests separately depends on them since its test cases use `GameState` / `SudokuEngine` types directly. Cleaner dep arrow.

### D2 — AppComposition test target NOT given TelemetryTesting dep
Brief expected "Persistence + AppComposition + maybe PuzzleStore" test targets to need TelemetryTesting. Inspection of `Packages/SudokuKit/Tests/AppCompositionTests/BootOrderTests.swift` showed it defines its own `private final class RecordingSink: TelemetrySink` at line 209 — no `import SudokuKitTesting` exists in that file. So no edge added to AppComposition test target. Keeps the dep arrow minimal; AppComposition stays free of TelemetryTesting.

Only PuzzleStore + Persistence test targets received the new `telemetryTestingDep` shorthand.

### D3 — Per-file import strategy
Two distinct patterns, applied per file (no blanket sed):
- **5 TelemetryTests files** (MetricKitSink/GameStateTelemetryAdapter/ErrorReporter/TelemetryFanOut/OSLogSink): pure swap `import SudokuKitTesting` → `import TelemetryTesting` — confirmed via grep these files use ONLY Telemetry-shaped fixtures (no FakePrivateCKGateway/PuzzleFixtures/FakeGenerator).
- **4 SudokuKit test files** (PuzzleStoreTests/SaltLogging + 3 PersistenceTests): ADD `import TelemetryTesting` as a new line; KEEP `import SudokuKitTesting` (still need FakeGenerator / FakePrivateCKGateway / PuzzleFixtures).

### D4 — Skipped local `swift build` / `swift test`
Per brief Step 6, Leader handles verification per `verification-before-completion` skill — same pattern that worked for SudokuCoreKit Stage 1. No-verify run by subagent. All 5 commits passed lefthook (gitleaks + hygiene + swiftformat + swiftlint; pre-existing blanket_disable + line_length + large_tuple warnings unrelated to this diff).

## Commits
1. `chore(modules): carve out TelemetryTesting subdir from SudokuKitTesting/Telemetry/` — git mv only
2. `chore(modules): add TelemetryTesting library product to TelemetryKit`
3. `chore(modules): wire TelemetryTesting product into PuzzleStore + Persistence test targets`
4. `refactor(tests): rewrite SudokuKitTesting -> TelemetryTesting imports per-file`
5. `docs(foundations): note TelemetryTesting library carve-out in Stage 2`

## Open questions for Leader
- None. Verification (`swift build` + full test suite) deferred to Leader. If build fails on dep resolution, Leader can dispatch a follow-up with the exact compiler error.

## Deviations from plan
- **D1 (smaller dep set than spec'd)**: Brief showed `TelemetryTesting` target depending on `Telemetry` + `GameState`. File-level evidence showed only `Telemetry` is referenced. Took the smaller surface — easier to add a dep later than to retract one.
- **D2 (AppComposition not touched)**: Brief expected it might need TelemetryTesting; BootOrderTests has its own private fake, so no change needed there. Surgical change principle (karpathy §3).
