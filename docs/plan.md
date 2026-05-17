# Sudoku v1 — Implementation Plan

Status: **DRAFT** — awaiting first execution.
Last updated: 2026-05-17
Total phases: **10**; total steps: **63**.

This plan operationalizes `docs/design.md §How.1`–`§How.7` and `docs/foundations.md §1`–`§8`. **Implementation lives in this same repo** (originally framed as a sibling `Sudoku/` repo; collapsed into the spec repo per 2026-05-17 decision). All file paths below are anchored at the repo root (where `.gitignore` / `docs/` / future `Packages/` sit).

---

## How to use this plan

1. **TDD-ordered**. Every step lists red tests first, then the production code that turns them green. Tests must be checked in *before* implementation in the same commit / PR pair, or earlier.
2. **One step = one PR** by default. Multi-file steps remain a single PR; do not split unless review feedback requests it.
3. **Sequential within a phase, optional parallelism across independent phases.** Phase 3 (GameState) and Phase 4 (Telemetry) are intentionally orderable in either direction once Phase 2 is green; Phase 5–7 fan out from Phase 2/3/4 and may be parallel-staffed.
4. **Phase gates**. Each phase has a verification checklist in Appendix C; do not start phase *N+1* until phase *N* checklist is fully green.
5. **No production code before Phase 0 gates are Resolved.** Phase 0 directly addresses the three Unconfirmed items in `design.md §How.4.9`; a failure there reshapes Phase 2.
6. **Skill invocation**. Every step names the skills the Developer subagent must invoke before touching code. The handoff prompt must include the 5 elements of `leader-developer-handoff-contract`.
7. **Phase 9/10 split**: the suggested "Phase 9" was split into Phase 9 (DI + Privacy + L10n) and Phase 10 (Release) to keep TestFlight / App Store work behind an explicit gate after all code lands.
8. **Acceptance is binary**. "All listed tests green + named build target compiles clean + named lint passes" — never "looks good".

**Phase-level skill preamble.** All Swift-coding steps invoke `swift6-concurrency`, `swift-testing-baseline`, `andrej-karpathy-skills:karpathy-guidelines` by default. Per-step `Skills` field lists EXTRAS only; omitted = defaults only.

---

## Phase 0 — Prerequisite gates (no production code yet)

Verifies `design.md §How.4.9` and unblocks Phase 2 algorithm choices.

### 0.1 SplitMix64 cross-architecture bit-identical reference vector

Tests:
- Standalone `scratch/SplitMix64Probe/` executable (`swift run splitmix64-probe`) printing 16 hex outputs for seeds `0x0` and `0x2A`.
- Hand-computed reference (commit message captures all 32 entries):
  - seed=0 first 4: `0xE220A8397B1DCDAF`, `0x6E789E6AA1B965F4`, `0x06C45D188009454F`, `0xF88BB8A8724C81EC`
  - seed=42 first 4: `0xBDD732262FEB6E95`, `0x28EFE333B266F103`, `0x47526757130F9F52`, `0x581CE1FF0E4AE394`
Implementation:
- `scratch/SplitMix64Probe/Package.swift`: executable, swift-tools 6.0, `[.macOS(.v26)]`.
- `scratch/SplitMix64Probe/Sources/main.swift`: inline `SplitMix64` per §How.4.2; prints two 16-line blocks.
Acceptance:
- `swift run splitmix64-probe` on macOS arm64 and `xcrun simctl spawn "iPhone 16 Pro" splitmix64-probe` produce byte-identical output matching the reference.
- Output captured in `meetings/2026-05-17_phase0-gates.md`.
Depends on: —
Notes: Scratch package is deleted at end of Phase 0; reference vectors migrate to `SudokuEngineTests/Fixtures/SplitMix64Reference.swift` in step 2.3.

### 0.2 Generator performance baseline (Hard p95)

Tests:
- `scratch/GeneratorProbe/Tests/PerfProbeTests.swift`: `test_hardGenerator_p95_under500ms` — 30 Hard runs, asserts `p95 < 500ms`.
Implementation:
- `scratch/GeneratorProbe/Sources/PrototypeGenerator.swift`: stripped §How.4.3 flow (SplitMix64 + randomized backtracking + clue mask + `nakedSingle`-only uniqueness — baseline, not final).
- `scratch/GeneratorProbe/Sources/Measure.swift`: `ContinuousClock` wall-clock.
Acceptance:
- 30-run Hard sample (median, p50, p95, p99, max) recorded in `meetings/2026-05-17_phase0-gates.md`.
- Pass: **p95 < 500ms** on Apple Silicon dev machine / Xcode 26.5 iPhone 16 Pro sim.
- If p95 ≥ 500ms: open §How.4.7 ADR amendment before Phase 2.
Depends on: 0.1.
Notes: Shadow-validated in step 2.7 against production `PuzzleGenerator`; Phase 2 must not regress.

### 0.3 App Store policy spot-check (deterministic puzzle + leaderboard)

Tests: N/A (documented evidence is the artifact).
Implementation:
- `meetings/2026-05-17_phase0-gates.md` § App Store policy spot-check, recording:
  1. App Review Guidelines retrieved 2026-05-17.
  2. Search keywords: `randomly generated`, `deterministic`, `leaderboard`, `Game Center`, `user-generated content`, `gambling`, `algorithm`.
  3. Sections reviewed in full: 1.1, 1.2, 4.0, 5.1.1, 5.3.
  4. Forum sample (Apple Dev Forums + WWDC labs notes, last 12 months) with retrieval dates.
  5. Conclusion paragraph.
Acceptance:
- Conclusion explicitly answers *"Does any App Store rule prohibit shipping a Game Center leaderboard whose puzzle content is generated locally by a deterministic algorithm with a shared seed?"* — required: **No.**
- Evidence committed to `meetings/`.
Skills: `apple-public-repo-security`.
Depends on: —
Notes: If 2026 has new AI/algorithm disclosure clauses, document; v1 is deterministic + algorithmic (not ML), but confirm not assume.

---

## Phase 1 — Implementation repo bootstrap + tooling

Adds implementation tooling baseline to this repo (Sudoku-spec).

### 1.1 Repo skeleton + `.gitignore` + LICENSE

Tests:
- `ci_scripts/test_repo_hygiene.sh`: asserts no `.env`/`*.p8`/`*.p12`/`*.pem` tracked; `.gitignore` contains every entry from `foundations.md §7.4`.
Implementation:
- `.gitignore`: verbatim §7.4.
- `LICENSE`: MIT.
- `README.md`: pointer to `Sudoku-spec/`.
- `.gitattributes`: `*.png binary`; snapshot baseline handling.
Acceptance: hygiene script exit 0; `git ls-files | grep -E '\.(p8|p12|pem|env)$'` empty.
Skills: `apple-public-repo-security`.
Depends on: Phase 0 green.

### 1.2 `.mise.toml` + lefthook + gitleaks

Tests:
- `ci_scripts/test_mise_resolves.sh`: asserts swiftlint, swiftformat, xcbeautify, gitleaks, lefthook pinned; `mise exec gitleaks -- version` ≥ v8.18.
Implementation:
- `.mise.toml`: per §7.5; try `aqua:` backend first, fall back to `ubi:` (verify with `mise plugin list --all`); pin every tool to a minor.
- `lefthook.yml`: verbatim §7.5.
- `.gitleaks.toml`: inherits default; adds CloudKit Key ID + ASC API Key ID rules (`[A-Z0-9]{10}` with context).
- `docs/setup.md`: `mise install` → `lefthook install` → Xcode Cloud env-var pointers.
Acceptance:
- `mise install` succeeds; `lefthook install` writes `.git/hooks/pre-commit`; a `-----BEGIN PRIVATE KEY-----` commit is blocked; mise script exit 0.
Skills: `mise-tool-management`, `apple-public-repo-security`.
Depends on: 1.1.
Notes: Resolves §7.11 lefthook-via-mise open item; document actual backend if aqua lacks lefthook.

### 1.3 SwiftPM package `SudokuKit` skeleton

Tests:
- `Packages/SudokuKit/Tests/SudokuKitSmokeTests/SmokeTests.swift`: `@Test func packageCompiles() {}`.
Implementation:
- `Packages/SudokuKit/Package.swift`: swift-tools 6.0; `[.iOS(.v26), .macOS(.v26)]`; 8 product targets (`SudokuEngine`, `GameState`, `PuzzleStore`, `Persistence`, `GameCenterClient`, `Telemetry`, `SudokuUI`, `SudokuKitTesting`) + 8 test targets; `swiftLanguageMode: .v6`; strict concurrency upcoming + experimental flags.
- Per-target `Sources/<Module>/<Module>.swift` placeholder with `public func _moduleAnchor() {}`.
- Snapshot dep: `pointfreeco/swift-snapshot-testing` from 1.17.0.
Acceptance: `swift build` clean (0 warnings) on Swift 6 strict; smoke test green.
Skills: `swiftpm-modularization`, `apple-platform-targets`.
Depends on: 1.2.

### 1.4 App target Xcode project + multiplatform scheme

Tests: N/A (functional tests in 1.3 / Phase 8).
Implementation:
- `App/Sudoku.xcodeproj`: multiplatform App, bundle ID `com.wei18.sudoku`, iOS 26 / macOS 26.
- `App/SudokuApp.swift`: minimal `@main` with `Text("placeholder")`.
- `App/Info.plist`: minimum (entitlements wired in Phase 9).
- `App/Assets.xcassets`: AppIcon placeholder, AccentColor `#5C7A4F`.
- Xcode project references `SudokuKit` via local package.
Acceptance: `xcodebuild` for iOS Sim iPhone 16 Pro + macOS arm64 both succeed, no new warnings.
Skills: `swiftpm-modularization`, `apple-platform-targets`.
Depends on: 1.3.

### 1.5 Xcode Cloud workflows (PR / Main / Release)

Tests: N/A.
Implementation:
- ASC Xcode Cloud, 3 workflows per §4: **PR CI** (build + test, branch base merge), **Main CI** (build + archive + TestFlight internal, no tests), **Release** (tag `v*` → archive + ASC upload, manual submit).
- `ci_scripts/ci_post_clone.sh`: `mise install` + `mise exec gitleaks -- git --pre-commit --staged --redact` (§7.6); fail build on non-zero.
- `ci_scripts/ci_pre_xcodebuild.sh`: header-only placeholder.
- Xcode 26.5 locked; no secrets needed yet.
Acceptance: no-op PR triggers PR CI; smoke test passes; Main CI on first merge produces TestFlight build; gitleaks blocks a fake-key test PR.
Skills: `xcode-cloud-single-track-ci`, `mise-tool-management`, `apple-public-repo-security`.
Depends on: 1.4.

### 1.6 GitHub repo public + Secret Scanning Alerts

Tests: N/A.
Implementation:
- Create public `Wei18/Sudoku`.
- Enable Secret scanning alerts + Push protection.
- Branch protection on `main`: require PR review + Xcode Cloud PR CI status check.
Acceptance: sample Apple-secret push to side branch blocked; `main` direct push blocked.
Skills: `apple-public-repo-security`.
Depends on: 1.1.

### 1.7 ASC bundle ID + entitlements stubs

Tests: N/A.
Implementation:
- ASC: reserve `com.wei18.sudoku`; create iOS + macOS app records (Game Center on).
- `App/Sudoku.entitlements`: iCloud-services `[CloudKit]`, container `iCloud.com.wei18.sudoku`; `game-center = true`.
- CloudKit Dashboard: create container with Public + Private DB scopes (Public reserved, unused in v1).
Acceptance: auto provisioning profile builds clean via Xcode Cloud; CloudKit container present, no record types.
Skills: `xcode-cloud-single-track-ci`, `apple-public-repo-security`.
Depends on: 1.5, 1.6.

---

## Phase 2 — `SudokuEngine` (pure core)

Implements `design.md §How.4` end-to-end. Pure Swift, no Apple framework imports.

### 2.1 `Board` model + encoding

Tests:
- @Suite `BoardEncoding`: `roundtripEmptyBoard`, `roundtripFullBoard` (random valid grid), `rejectMalformedLength` (80-char throws `Board.DecodeError.length`).
Implementation:
- `Sources/SudokuEngine/Board.swift`: `public struct Board: Sendable, Equatable, Hashable` with `cells: [UInt8]` (81); `init(encoded:) throws`, `encoded() -> String`, `subscript(row:col:)`.
- `public enum CellValue: UInt8, Sendable { case empty = 0, one = 1, ..., nine = 9 }`.
Acceptance: 3/3 green.
Depends on: Phase 1.

### 2.2 `Board.validate` rules

Tests:
- @Suite `BoardValidation` (≥ 6): row/col/box conflict each → `.conflict(.row(i)/.col(i)/.box(i))`; `clueImmutable(digit:)` parameterized [1,5,9]; `validBoardReturnsOK` on `BoardFixtures.solvedKnown`.
Implementation:
- `Sources/SudokuEngine/BoardValidation.swift`: `public enum ValidationOutcome: Sendable, Equatable { case ok; case conflict(Constraint) }`; `Board.validate() -> ValidationOutcome`.
- `Sources/SudokuEngine/Fixtures/` internal `BoardFixtures`.
Acceptance: ≥ 6 green; coverage ≥ 95%.
Depends on: 2.1.

### 2.3 `DeterministicRNG` + `SplitMix64`

Tests:
- @Suite `SplitMix64`: `seedZeroFirst16` / `seed42First16` against Phase 0 reference; `independentInstancesIdentical`.
Implementation:
- `Sources/SudokuEngine/RNG/DeterministicRNG.swift`: `public protocol DeterministicRNG: Sendable { mutating func next() -> UInt64 }`.
- `Sources/SudokuEngine/RNG/SplitMix64.swift`: verbatim §How.4.2.
- `Sources/SudokuKitTesting/RNG/ScriptedRNG.swift`: public test helper (canned sequence).
- `Tests/SudokuEngineTests/Fixtures/SplitMix64Reference.swift`: frozen vectors from Phase 0.
Acceptance: 3 green; Phase 0.1 scratch deleted; vectors live only here.
Depends on: 2.1, Phase 0 closed.

### 2.4 `Move` + `UndoStack(20)`

Tests:
- @Suite `MoveAndUndo`: `applyUnapplySymmetric`; `stackCapsAt20` (push 25 → oldest 5 dropped, `count == 20`); `redoAfterUndo`; `pushClearsRedo`.
Implementation:
- `Sources/SudokuEngine/Move.swift`: `public struct Move: Sendable, Equatable, Codable` with `place(row,col,digit)` and `note(row,col,mask)` variants.
- `Sources/SudokuEngine/UndoStack.swift`: fixed cap 20 ring buffer.
Acceptance: 4 green; coverage ≥ 95%.
Depends on: 2.1.

### 2.5 `UniquenessValidator` (DFS + short-circuit)

Tests:
- @Suite `UniquenessValidator`: `uniqueSolutionFound` on `BoardFixtures.knownUnique`; `multipleSolutionsShortCircuit` (exactly 2 solutions → `.multiple(count:2, samples:…)`, asserts step counter < threshold via injected probe); `unsolvable`.
Implementation:
- `Sources/SudokuEngine/UniquenessValidator.swift`: DFS w/ second-solution short-circuit; `public enum ValidationResult: Sendable, Equatable { case unique(Board); case multiple(count: Int, samples: [Board]); case unsolvable }`.
Acceptance: 3 green; probe verifies short-circuit.
Depends on: 2.2.

### 2.6 `PuzzleCalibrator` (3-layer propagation)

Tests:
- @Suite `Calibrator`: `nakedSingleSolvable`; `hiddenSinglePromoted`; `nakedPairAppliedExactlyOnce` (counter); `easyRejectsNonPropagationOnly` (DFS-guess fixture rejected); `easyClueCountBoundary` (31 reject / 32 accept / 50 accept / 51 reject); `branchingFactorCounted`.
Implementation:
- `Sources/SudokuEngine/Calibrator/PropagationSolver.swift`: three rules with `applied: Int` counters.
- `Sources/SudokuEngine/Calibrator/PuzzleCalibrator.swift`: `public func calibrate(board:target:) -> CalibrationResult`.
Acceptance: 6 green; coverage ≥ 95%.
Depends on: 2.5.

### 2.7 `PuzzleGenerator` + `Puzzle` + retry budget

Critical: **single retry loop** (§How.4.7); generator owns the loop, no nested retries.
Tests:
- @Suite `Generator`:
  - Frozen `(clues, solution)` snapshots for first 5 daily-seeds × 3 difficulties = **15 frozen** (§How.4.6, exact string match).
  - `retryBudgetFindsValidPuzzle` (ScriptedRNG: 31 rejects then accept).
  - `exhaustedAfterN32` (32 rejects → `GeneratorError.exhausted`).
  - `bitIdenticalRepeatedCalls`.
Implementation:
- `Sources/SudokuEngine/Generator/GeneratorVersion.swift`: `public enum GeneratorVersion: Int, Sendable, Equatable, Codable, CaseIterable { case v1 = 1 }`.
- `Sources/SudokuEngine/Generator/Puzzle.swift`: `public struct Puzzle: Sendable, Equatable, Codable` (§How.4.3).
- `Sources/SudokuEngine/Generator/PuzzleGenerator.swift`: `public protocol PuzzleGenerator: Sendable { func generate(seed:difficulty:version:) throws -> Puzzle }` + `LivePuzzleGenerator`.
- `Sources/SudokuEngine/Generator/GeneratorError.swift`: `case exhausted(reason:)`, `case cancelled`.
- Re-run Phase 0.2 measurement against `LivePuzzleGenerator`; record updated p95 in `meetings/`; must not regress.
Acceptance: 18 tests green (15 frozen + 3 behavior); `SudokuEngineTests` coverage ≥ 95%; p95 re-measure < 500ms.
Depends on: 2.3, 2.5, 2.6.
Notes: Frozen snapshots are the cross-arch determinism gate; any Xcode major upgrade re-runs all 15.

---

## Phase 3 — `GameState`

Implements `design.md §How.5.3` state machine + `§How.5.4` snapshot. No CloudKit / GC imports.

### 3.1 `GameSession.Status` state machine

Tests:
- `Tests/GameStateTests/SessionStatusTests.swift`: 5 valid transitions parameterized; 4 illegal transitions throw `IllegalTransition`.
Implementation:
- `Sources/GameState/GameSession.swift`: `public struct GameSession: Sendable` with `public enum Status: Sendable, Equatable { case idle, playing, paused, completed, abandoned }`.
- `Sources/GameState/SessionTransitions.swift`: mutating `start`, `pause`, `resume`, `complete`, `abandon`.
Acceptance: green; coverage ≥ 95%.
Depends on: Phase 2.

### 3.2 `placeDigit` / `note` / `undo` / `redo`

Tests:
- `MoveAPITests.swift`: `placeDigitUpdatesBoard` (happy + over-clue throws); `noteTogglesCandidate`; `undoReversesPlace`; `redoReplaysPlace`; `cannotMoveWhenPaused` throws.
Implementation:
- `Sources/GameState/MoveAPI.swift`: extends `GameSession`; routes through `SudokuEngine.UndoStack`.
Acceptance: 5 green; coverage ≥ 90%.
Depends on: 3.1, Phase 2.

### 3.3 Clock-injected `elapsedSeconds`

Tests:
- `ElapsedTests.swift`: `pauseFreezesClock` (§How.7.2); `resumeContinuesAccumulation`; `completedFreezes`.
Implementation:
- `Sources/SudokuKitTesting/Clock/FakeClock.swift`: `public actor FakeClock { advance(by:) }`.
- `Sources/GameState/Clock+Inject.swift`: `GameSession` holds `any Clock` (stdlib).
Acceptance: 3 green; `FakeClock` reused in Phase 4–8.
Depends on: 3.1.

### 3.4 `GameSessionSnapshot` value type

Tests:
- `SnapshotTests.swift`: `snapshotMirrorsSession` (round-trip); `codableRoundtrip` (JSON); `mapToSavedGameFields` (table-driven mapping per §How.2).
Implementation:
- `Sources/GameState/GameSessionSnapshot.swift`: `public struct ... : Sendable, Equatable, Codable`.
- Public `toSavedGameFields()` helper.
Acceptance: 3 green.
Depends on: 3.2, 3.3.

### 3.5 Telemetry emission on transitions

Tests:
- `TelemetryEmissionTests.swift`: `completionEventFiresExactlyOnce` (§How.7.2); `pauseEmitsSessionPaused`; `abandonEmitsSessionAbandoned`; `placeDigitEmitsDigitPlaced`.
Implementation:
- `Sources/GameState/TelemetryBridge.swift`: `GameSession` holds `Telemetry`, emits on place/pause/complete/abandon; depends only on forward-declared `Telemetry` protocol surface.
Acceptance: 4 green using `SpyTelemetry` from `SudokuKitTesting`.
Skills: `telemetry-facade-pattern`.
Depends on: 3.4; soft 4.1 (parallel-safe after 4.1 lands).

---

## Phase 4 — `Telemetry`

Implements `design.md §How.1` fan-out + `foundations.md §5 §6`. Parallel-able with Phase 3 after 4.1.

### 4.1 `TelemetryEvent` enum + `TelemetrySink` protocol

Tests:
- `EventSendableTests.swift`: `allCasesAreSendable` (compile-time generic constraint); `equatablePerCase`.
Implementation:
- `Sources/Telemetry/TelemetryEvent.swift`: `public enum TelemetryEvent: Sendable, Equatable { case digitPlaced(...); case puzzleCompleted(puzzleId:String, mode:GameMode, difficulty:Difficulty, elapsedSeconds:Int); case sessionPaused; case sessionAbandoned; case errorOccurred(source:String, code:String); case metricKitReport(MetricReport) }`.
- `Sources/Telemetry/TelemetrySink.swift`: `public protocol TelemetrySink: Sendable { func receive(_ event: TelemetryEvent) async }`.
- `Sources/Telemetry/GameMode.swift`, `Difficulty.swift`: `Sendable, Equatable, Codable`.
Acceptance: 2 green; strict-concurrency clean.
Skills: `telemetry-facade-pattern`.
Depends on: Phase 1.

### 4.2 `Telemetry` actor (fan-out)

Tests:
- `FanOutTests.swift`: `allSinksReceiveEvent`; `throwingSinkDoesNotBlockOthers`; `eventOrderingPreserved` (FIFO per sink).
Implementation:
- `Sources/Telemetry/Telemetry.swift`: `public actor Telemetry { public init(sinks: [any TelemetrySink]); public func observe(_:) async }`.
Acceptance: 3 green.
Skills: `telemetry-facade-pattern`.
Depends on: 4.1.

### 4.3 `OSLogSink` + `LoggerProtocol` seam

Tests:
- `OSLogSinkTests.swift`: `categoryEqualsModuleName`; `privacyDefaultsPrivate`; `publicFlagRespected`.
Implementation:
- `Sources/Telemetry/LoggerProtocol.swift`: minimal seam wrapping `os.Logger`.
- `Sources/Telemetry/OSLogSink.swift`: `public struct OSLogSink: TelemetrySink`.
- `Sources/SudokuKitTesting/Telemetry/FakeLogger.swift`: captures invocations.
Acceptance: 3 green.
Skills: `oslog-logger-defaults`, `telemetry-facade-pattern`.
Depends on: 4.2.

### 4.4 `NoOpTrackingSink`

Tests: `NoOpSinkTests.swift`: `receiveIsNoOp`.
Implementation: `Sources/Telemetry/NoOpTrackingSink.swift` verbatim from §6.
Acceptance: 1 green.
Skills: `telemetry-facade-pattern`, `apple-three-piece-analytics`.
Depends on: 4.1.

### 4.5 `MetricKitSink`

Tests:
- `MetricKitSinkTests.swift`: `payloadBecomesMetricKitReportEvent`; `crashDiagnosticIsForwarded`.
Implementation:
- `Sources/Telemetry/MetricKitSink.swift`: `public final class MetricKitSink: NSObject, MXMetricManagerSubscriber, TelemetrySink` (actor-isolated state + nonisolated delegate).
- `Sources/Telemetry/MetricReport.swift`: `public struct ... : Sendable, Equatable, Codable` (decoupled from MetricKit types).
- `Sources/SudokuKitTesting/Telemetry/MetricPayloadFixtures.swift`: canned `MXMetricPayload`-like fixtures.
Acceptance: 2 green.
Skills: `apple-three-piece-analytics`, `telemetry-facade-pattern`.
Depends on: 4.2.

---

## Phase 5 — `Persistence` (CloudKit Private DB)

Implements `design.md §How.2` schema + `§How.6.5 §How.6.7` conflict/account flows. Tests via `FakePrivateCKGateway`; live validated in Phase 10.

### 5.1 `PersistenceProtocol` + value types

Tests:
- `ProtocolShapeTests.swift`: compile-time — all methods `async throws`, protocol `Sendable`; value types (`SavedGameSummary`, `PersonalRecord`) `Sendable + Equatable + Codable`.
Implementation:
- `Sources/Persistence/PersistenceProtocol.swift`: verbatim §How.5.4.
- `Sources/Persistence/SavedGameSummary.swift`, `PersonalRecord.swift`.
Acceptance: strict-concurrency clean.
Depends on: Phase 3, Phase 4.

### 5.2 Custom zone provisioning

Tests:
- `ZoneProvisioningTests.swift`: `provisionCreatesUserZoneOnce` (1 `CKModifyRecordZonesOperation`); `idempotentOnExistingZone`.
Implementation:
- `Sources/Persistence/Live/PrivateCKGateway.swift`: internal actor wrapping `CKDatabase`; `zoneID = CKRecordZone.ID(zoneName: "com.wei18.sudoku.userZone", ownerName: CKCurrentUserDefaultName)`.
- `Sources/SudokuKitTesting/Persistence/FakePrivateCKGateway.swift`: actor mirroring live surface.
Acceptance: 2 green.
Depends on: 5.1.

### 5.3 `CKDatabaseSubscription` setup

Tests: `SubscriptionTests.swift`: `subscriptionCreatedOnFirstLaunch`; `idempotentOnRelaunch`.
Implementation: `Sources/Persistence/Live/SubscriptionInstaller.swift`: single `CKDatabaseSubscription` per §How.2.
Acceptance: 2 green.
Depends on: 5.2.

### 5.4 `SavedGame` CRUD + `generatorVersion` field

Tests:
- `SavedGameCRUDTests.swift`: `loadOrCreateNewPuzzleSeedsFromGameState`; `saveRoundtrips`; `markCompletedSetsStatus`; `deleteAbandonedRemovesRecord`; `generatorVersionPersisted`.
Implementation:
- `Sources/Persistence/Live/SavedGameStore.swift`: maps `GameSessionSnapshot` ↔ `CKRecord` (12 fields per §How.2).
Acceptance: 5 green; coverage ≥ 85%.
Depends on: 5.2.

### 5.5 `PersonalRecord` CRUD + dedup

Tests:
- `PersonalRecordTests.swift`: `recordNameIsModeDifficulty` (deterministic key); `reCompletingSamePuzzleIdDoesNotBump` (§How.2 末段 rule); `fetchAllReturnsAtMostSix`.
Implementation: `Sources/Persistence/Live/PersonalRecordStore.swift`.
Acceptance: 3 green.
Depends on: 5.2.

### 5.6 Per-field LWW conflict resolver

Tests:
- `ConflictResolverTests.swift`: `boardNotesUndoSwitchedAsGroup` (newer lastModifiedAt wins all three); `elapsedSecondsTakesMax`; `statusCompletedWinsOverInProgress`; `personalRecordBestTimeTakesMin`; `personalRecordCountsTakeMax`; `threeConflictsThrowSyncConflict`.
Implementation: `Sources/Persistence/Live/ConflictResolver.swift`: per §How.6.7 table; retry budget 2 + final throw.
Acceptance: 6 green; coverage ≥ 90%.
Depends on: 5.4, 5.5.

### 5.7 `CKAccountChanged` flow (Case A / B / C)

Tests:
- `AccountFlowTests.swift`: `caseANeverSignedIn` (`iCloudNotSignedIn` thrown, local cache reads still succeed); `caseBSignedOutDuringSession` (flush, cache retained, CK ops throw `iCloudSignedOutDuringSession`); `caseCAccountChanged` (hash mismatch → wipe-on-confirm).
Implementation:
- `Sources/Persistence/Live/AccountMonitor.swift`: observes `CKAccountChanged`; tracks `fetchUserRecordID` hash in Keychain.
- Local cache (file-system in App container).
Acceptance: 3 green.
Skills: `apple-public-repo-security`.
Depends on: 5.4, 5.5.

---

## Phase 6 — `PuzzleStore`

Implements `design.md §How.4.3` identity + `§How.5.1` `PuzzleProviderProtocol`.

### 6.1 `PuzzleProviderProtocol` + identity value types

Tests:
- `IdentityTests.swift`: `dailyIdentityFormat` (`YYYY-MM-DD-{easy|medium|hard}`); `practiceIdentityBase32`; value types Sendable/Equatable.
Implementation:
- `Sources/PuzzleStore/PuzzleProviderProtocol.swift`: `public protocol ... : Sendable`.
- `Sources/PuzzleStore/PuzzleIdentity.swift`, `PuzzleEnvelope.swift`, `PuzzleKind.swift`: verbatim §How.4.3.
Acceptance: 3 green.
Depends on: Phase 2.

### 6.2 Live `PuzzleStore` wrapping `PuzzleGenerator`

Tests:
- `StoreLiveTests.swift`: `dailyTrioDeterministicAcrossCalls` (§How.7.3); `practiceDrawsDistinctPuzzles` (different salt → different puzzleId); `generatorExhaustionPropagates`.
Implementation:
- `Sources/PuzzleStore/PuzzleStore.swift`: `public actor PuzzleStore: PuzzleProviderProtocol`; derives seeds per §How.4.1; assembles `PuzzleEnvelope`.
- `Sources/SudokuKitTesting/PuzzleStore/FakeGenerator.swift`: actor.
Acceptance: 3 green; coverage ≥ 85%.
Depends on: 6.1.

### 6.3 In-memory daily trio cache

Tests:
- `CacheTests.swift`: `dailyTrioCachedForSameDate` (counter probe); `cacheInvalidatedOnDateChange`.
Implementation: internal cache keyed by `(date, generatorVersion)`.
Acceptance: 2 green.
Depends on: 6.2.

### 6.4 Practice salt + OSLog `.public` logging

Tests: `SaltLoggingTests.swift`: `practiceSaltLoggedPublic` (FakeLogger sees `.public` interpolation containing salt).
Implementation:
- `Sources/PuzzleStore/PracticeSalt.swift`: wraps `RandomNumberGenerator` injection (live = `SystemRandomNumberGenerator`).
- Logs salt via `OSLogSink` `.public`.
Acceptance: 1 green; salt source injectable.
Skills: `oslog-logger-defaults`, `telemetry-facade-pattern`.
Depends on: 6.2.

---

## Phase 7 — `GameCenterClient`

Implements `design.md §How.3` end-to-end.

### 7.1 Protocol + value types

Tests:
- `ProtocolShapeTests.swift`: all methods `async throws`; protocol `: Sendable`; value types `Sendable + Equatable`.
Implementation:
- `Sources/GameCenterClient/GameCenterClient.swift`: verbatim §How.3.3 (protocol + value types + `GameCenterError`).
- `Sources/SudokuKitTesting/GameCenter/FakeGameCenterClient.swift`: actor; scripted state.
Acceptance: strict-concurrency clean.
Depends on: Phase 4.

### 7.2 Live `GKLocalPlayer` authentication

Tests:
- `AuthTests.swift`: `authenticatedStateSurfaced`; `cancelledMapsToError`; `restrictedMapsToRestricted`; `authStateUpdatesStreamsChanges`.
Implementation:
- `Sources/GameCenterClient/Live/LiveGameCenterClient.swift`: wraps `GKLocalPlayer` (only `GameKit` importer).
- `Sources/GameCenterClient/Live/AuthDriver.swift`: testable seam over GKLocalPlayer.
Acceptance: 4 green.
Depends on: 7.1.

### 7.3 `submitScore` with Daily-only + first-time + same-UTC-day + `.v1` leaderboard ID

Tests:
- `SubmitScoreTests.swift`: `practiceModeNeverSubmits` (§How.7.5); `dailyFirstTimeSubmits`; `dailySecondTimeSkipped`; `crossDayCompletionSkipped`; `leaderboardIDSuffixedV1`.
Implementation:
- `Sources/GameCenterClient/SubmitGuards.swift`: `completedDailyPuzzleIds: Set<String>` + UTC-day comparator.
- `Sources/GameCenterClient/LeaderboardIDs.swift`: `com.wei18.sudoku.leaderboard.{difficulty}.daily.v1`.
Acceptance: 5 green.
Depends on: 7.2, Phase 5 (for `completedDailyPuzzleIds` seed).

### 7.4 `reportAchievement` (mode-agnostic, Persistence-counted)

Tests:
- `AchievementTests.swift`: `firstPuzzleUnlocks`; `dailyStreak3DerivedFromPersistence`; `practiceComplete100PercentProgress`; `dailySweepRequiresAllThreeDifficulties`; `idempotentDoubleReport`.
Implementation: `Sources/GameCenterClient/AchievementEvaluator.swift`: reads `PersistenceProtocol` counts; computes 8 achievements per §How.3.2.
Acceptance: 5 green.
Depends on: 7.3, Phase 5.

### 7.5 `fetchLeaderboardSlice` (3 scopes) + friends auth precondition

Tests:
- `LeaderboardSliceTests.swift`: `globalTopReturnsTopN`; `aroundPlayerSplitsAroundSelf`; `friendsOnlyRequiresAuthorization` (`.denied` throws `.friendsAccessDenied`); `notDeterminedTriggersRequest`; `cacheStaleAfter5min`.
Implementation: `Sources/GameCenterClient/Leaderboard/Slice.swift`: wraps `GKLeaderboard.loadEntries`.
Acceptance: 5 green.
Depends on: 7.2.

### 7.6 `GameCenterSink` (Telemetry consumer)

Tests:
- `SinkTests.swift`: `puzzleCompletedFanOutFiresSubmitAndAchievements`; `unauthenticatedNoOp`; `restrictedNoOp`.
Implementation: `Sources/GameCenterClient/GameCenterSink.swift`: `: TelemetrySink`; consumes `.puzzleCompleted` per §How.3.3 fan-out.
Acceptance: 3 green.
Skills: `telemetry-facade-pattern`.
Depends on: 7.3, 7.4.

### 7.7 macOS region-restricted fallback

Tests: `RegionTests.swift`: `unavailableInRegionMappedFromGKError`; `restrictedHidesLeaderboardUI` (UI flag asserted).
Implementation: `Sources/GameCenterClient/Live/RegionMapper.swift`: heuristic combining `GKError.Code` + `Locale.current.region`; documented in code comment.
Acceptance: 2 green.
Depends on: 7.2.

---

## Phase 8 — `SudokuUI`

Implements `design.md §How.5.1`–`§How.5.8`. Views consume protocols only; no `CloudKit` / `GameKit` imports. Phase-extra skills: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max` apply to all View steps.

### 8.1 `Theme` protocol + `DefaultTheme`

Tests: `ThemeTests.swift`: `defaultThemeTokensMatchDesignSystem` (accent `#5C7A4F` etc. per `docs/designs/design-system.md`).
Implementation: `Sources/SudokuUI/Theme/Theme.swift` (protocol); `Sources/SudokuUI/Theme/DefaultTheme.swift` (tokens).
Acceptance: 1 green.
Depends on: Phase 1.

### 8.2 `AppRoute` enum + navigation

Tests: `RouteTests.swift`: all cases `Hashable + Sendable`; deep-link round-trip `CompletionView → LeaderboardView`.
Implementation: `Sources/SudokuUI/Navigation/AppRoute.swift` verbatim §How.5.2; compact/regular split in `RootView`.
Acceptance: 2 green.
Depends on: 8.1.

### 8.3 `RootView` + auth `.task`

Tests: snapshot — `RootView` empty (no resume), iPhone light + Mac light = 2; behavior — `authenticate()` invoked once on `.task` (Spy).
Implementation: `Sources/SudokuUI/Root/RootView.swift`, `RootViewModel.swift` (§How.5.4).
Acceptance: 2 snapshots + 1 behavior green.
Depends on: 8.2, Phase 7.1.

### 8.4 `HomeView` (4 mode cards, Liquid Glass)

Tests: snapshot iPhone light + Mac light = 2; behavior — tap mode card routes correctly.
Implementation: `Sources/SudokuUI/Home/HomeView.swift`, `HomeViewModel.swift`; uses `.glassEffect()`.
Acceptance: 2 snapshots green.
Depends on: 8.3.

### 8.5 `DailyHubView` (3 puzzle cards + completion checks + `.exhausted` alert)

Tests: 3 snapshots (unfinished / completed Easy / all completed) per §How.5.8; behavior — `GeneratorError.exhausted` → Alert per §How.6.3.
Implementation: `Sources/SudokuUI/Daily/DailyHubView.swift`, `DailyHubViewModel.swift`.
Acceptance: 3 snapshots + 1 behavior green.
Depends on: 8.4, Phase 6.

### 8.6 `PracticeHubView` (difficulty picker + draw + shimmer >100ms)

Tests: 3 snapshots (idle / drawing-shimmer / drawn) per §How.5.8; behavior — shimmer appears when fetch latency > 100ms (FakeClock).
Implementation: `Sources/SudokuUI/Practice/PracticeHubView.swift`, `PracticeHubViewModel.swift`.
Acceptance: 3 snapshots + 1 behavior green.
Skills: `swiftui-expert-skill` (omit pro-max for this step).
Depends on: 8.4, Phase 6.

### 8.7 `BoardView` (cells, digit pad, undo/redo, pencil, pause overlay, keyboard)

Tests:
- 12 snapshots per §How.5.8: iPhone/Mac × light/dark × {empty, in-progress with errors, just-before-complete}, including 1 ja + 1 ko + 1 zh-TW variant.
- Mac keyboard: `1`-`9` fills, `0`/`delete` clears, `p` toggles pencil, `⌘Z`/`⌘⇧Z` undo/redo, arrows move focus.
- A11y dump: VoiceOver label per §How.5.7.
Implementation:
- `Sources/SudokuUI/Board/BoardView.swift`, `GameViewModel.swift` (§How.5.4).
- `BoardCellView`, `DigitPadView`, `PauseOverlayView`.
- `.focusable() + .onKeyPress()` for keyboard; `.keyboardShortcut()` for undo/redo.
Acceptance: 12 snapshots + 2 keyboard + 1 A11y green; view inspection asserts `.glassEffect()` is **not** applied (§How.5.1).
Depends on: 8.4, Phase 3, Phase 5.

### 8.8 `CompletionView` (3 state variants)

Tests: 3 snapshots (authenticated w/ leaderboard / unauthenticated CTA / leaderboard fetch failed), 1 zh-TW hero variant; behavior — deep link to `LeaderboardView` on tap.
Implementation: `Sources/SudokuUI/Completion/CompletionView.swift`, `CompletionViewModel.swift`.
Acceptance: 3 snapshots + 1 behavior green.
Depends on: 8.7, Phase 7.5.

### 8.9 `LeaderboardView` (3 scopes + AX3+ vertical stack)

Tests: behavior — scope toggle changes data source; AX3+ Dynamic Type collapses to vertical stack.
Implementation: `Sources/SudokuUI/Leaderboard/LeaderboardView.swift`, `LeaderboardViewModel.swift`.
Acceptance: 2 behavior tests green.
Skills: `swiftui-expert-skill`.
Depends on: 8.4, Phase 7.5.

### 8.10 `SettingsView`

Tests: behavior — Generator v1 row displays current version; clear-cache invokes Persistence.
Implementation: `Sources/SudokuUI/Settings/SettingsView.swift`, `SettingsViewModel.swift`.
Acceptance: 2 behavior tests green.
Skills: `swiftui-expert-skill`.
Depends on: 8.4, Phase 5, Phase 7.

### 8.11 Snapshot baseline lock (21 images)

Tests: N/A (artifact is acceptance).
Implementation: verify `__Snapshots__/` contains exactly 21 PNGs per §How.5.8 matrix; commit images.
Acceptance: `git ls-files Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/ | wc -l` = 21; all `SudokuUITests` green on PR CI.
Skills: (defaults only).
Depends on: 8.3–8.10.

---

## Phase 9 — DI + Privacy + L10n

Wires the App target, ships PrivacyInfo, seeds the localization catalog.

### 9.1 `SudokuApp` entry + `AppComposition.live/preview/tests`

Tests:
- `CompositionTests.swift`: `liveCompositionWiresAllProtocols`; `previewCompositionUsesFakes`; `testsCompositionUsesFakes`.
Implementation:
- `App/SudokuApp.swift`: per §How.1.
- `App/AppComposition.swift`: three factory methods.
- `App/CompositionRoot/Live.swift`, `Preview.swift`, `Tests.swift`: wire concrete impls.
Acceptance: 3 green; App launches in iPhone + Mac sims.
Skills: `swiftpm-modularization`.
Depends on: Phase 8.

### 9.2 GameCenter + CloudKit entitlements wiring

Tests: N/A (build-time).
Implementation:
- `App/Sudoku.entitlements`: finalized from 1.7 stub.
- `Info.plist`: `NSGameKitFriendListUsageDescription` 7-locale placeholders.
Acceptance: App launches on sim; `GKLocalPlayer.local.isAuthenticated` returns a value (sandbox in Phase 10); CloudKit container query returns user zone in dev.
Skills: `apple-public-repo-security`.
Depends on: 9.1.

### 9.3 `PrivacyInfo.xcprivacy`

Tests:
- `PrivacyManifestTests.swift`: `manifestPresent`; `noThirdPartyTrackingDomains`; `requiredReasonsAPIsDeclared` (`UserDefaults` CA92.1 if used, file-timestamp APIs if used).
Implementation: `App/Resources/PrivacyInfo.xcprivacy` per `foundations.md §6` (no IDFA, no PII, no third-party SDKs).
Acceptance: 3 green; manifest parses as valid plist.
Skills: `apple-public-repo-security`, `apple-three-piece-analytics`.
Depends on: 9.1.

### 9.4 `Localizable.xcstrings` seed (en + zh-TW)

Tests: `L10nTests.swift`: `allUserFacingStringsHaveEnAndZhTW` (scans `SudokuUI/` for `String(localized:)`, asserts catalog hit).
Implementation:
- `App/Resources/Localizable.xcstrings`: seeded, source = en, zh-TW filled.
- Error vocabulary keys per §How.6.9 (`error.<source>.<case>.{title|body|action}`).
Acceptance: 1 green; catalog opens in Xcode 26.5 string-catalog editor without warnings.
Skills: `ai-translated-localization`.
Depends on: Phase 8.

### 9.5 AI-translated 5-locale pass (ja / zh-CN / es / th / ko)

Tests: `L10nCompletenessTests.swift`: `all7LocalesPresent`; `noUntranslatedMarkers` (no `<TRANSLATE>` literals).
Implementation:
- Run `ai-translated-localization` agent flow for 5 remaining locales.
- Manual review for SF Symbol placeholders + numeric format strings.
Acceptance: 2 green; each locale spot-checked via `xcrun simctl spawn` with locale override.
Skills: `ai-translated-localization`.
Depends on: 9.4.

### 9.6 GC achievement / leaderboard names localized via ASC API

Tests: N/A (ASC-side manual).
Implementation:
- `ci_scripts/upload_gc_metadata.sh`: uses ASC API key (Xcode Cloud secret); uploads 3 leaderboards × 7 locales = 21 + 8 achievements × 7 locales = 56 = 77 strings.
- Source from `Localizable.xcstrings` via a small Swift tool.
Acceptance: ASC Game Center page shows all 77 localized entries.
Skills: `ai-translated-localization`, `xcode-cloud-single-track-ci`.
Depends on: 9.5.

---

## Phase 10 — Release

TestFlight, manual validation, App Store submission.

### 10.1 Internal TestFlight via Main CI

Tests: N/A.
Implementation: merge RC branch to `main`; Main CI uploads to TestFlight; internal testers (dev + 1 secondary device w/ second iCloud account).
Acceptance: TestFlight installable on iPhone 16 Pro + Mac arm64; app completes a Practice puzzle, persists to iCloud, visible on second device.
Skills: `xcode-cloud-single-track-ci`.
Depends on: Phase 9 complete.

### 10.2 Game Center sandbox manual validation checklist

Tests: N/A.
Implementation: checklist in `meetings/2026-06-XX_release-rehearsal.md`:
- [ ] Sandbox `GKLocalPlayer` authenticates on iPhone.
- [ ] Same on Mac.
- [ ] Daily Easy first completion submits score.
- [ ] Second completion of same `puzzleId` does **not** resubmit.
- [ ] Cross-day completion does **not** submit (UTC manipulation via Settings).
- [ ] `daily.streak_3` triggers after 3 calendar-day completions.
- [ ] `daily.sweep` triggers when all 3 difficulties done same UTC day.
- [ ] Friends-only leaderboard requires authorization prompt.
- [ ] Unauthenticated state shows degraded UI per §How.3.4.
Acceptance: all 9 items green.
Skills: `apple-three-piece-analytics`.
Depends on: 10.1.

### 10.3 CloudKit development container validation checklist

Tests: N/A.
Implementation: same checklist file as 10.2:
- [ ] Custom zone `com.wei18.sudoku.userZone` provisioned on first launch.
- [ ] `CKDatabaseSubscription` registered, silent push delivered after second-device write.
- [ ] `SavedGame` round-trips iPhone ↔ Mac.
- [ ] `PersonalRecord` round-trips across devices.
- [ ] Per-field LWW resolves a hand-crafted conflict (force two simultaneous writes).
- [ ] iCloud sign-out: `iCloudSignedOutDuringSession` Alert triggered; cache retained.
- [ ] iCloud account change: wipe-on-confirm clears caches.
- [ ] Quota exceeded simulation (CloudKit Dashboard fill): banner shown, game still playable.
Acceptance: all 8 green; CloudKit dev container promoted to production via CloudKit Dashboard.
Skills: `apple-public-repo-security`.
Depends on: 10.1.

### 10.4 App Store metadata + screenshots

Tests: N/A.
Implementation:
- 7-locale ASC metadata (title, subtitle, description, keywords, promotional text, what's new).
- Screenshot sets: iPhone 6.7" + 6.1" + iPad 12.9" + Mac — captured via Phase 8 snapshot infra (re-use `BoardView` snapshots tweaked for ASC dimensions).
- Privacy policy URL: GitHub Pages from `Sudoku-spec/`.
Acceptance: ASC "Ready for Submission" checklist all green.
Skills: `ai-translated-localization`, `ui-ux-pro-max:ui-ux-pro-max`.
Depends on: 10.2, 10.3.

### 10.5 Production submission

Tests: N/A.
Implementation: tag `v1.0.0` on `main` → Xcode Cloud Release workflow uploads to ASC; manual submit for review.
Acceptance: Apple review approved; App live in 7 locale storefronts (US, TW, JP, CN, ES, TH, KR).
Skills: `xcode-cloud-single-track-ci`, `apple-public-repo-security`.
Depends on: 10.4.

---

## Appendix A — File path conventions

| Kind | Path |
|---|---|
| Production code | `Packages/SudokuKit/Sources/<Module>/` |
| Tests | `Packages/SudokuKit/Tests/<Module>Tests/` |
| Shared testing helpers | `Packages/SudokuKit/Sources/SudokuKitTesting/` |
| App target | `App/` (SudokuApp.swift, Assets.xcassets, Info.plist, Sudoku.entitlements, Resources/) |
| Localization | `App/Resources/Localizable.xcstrings` |
| Privacy manifest | `App/Resources/PrivacyInfo.xcprivacy` |
| CI scripts | `ci_scripts/` (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `upload_gc_metadata.sh`) |
| Tool versioning | `.mise.toml` |
| Pre-commit hooks | `lefthook.yml` |
| Gitleaks rules | `.gitleaks.toml` |
| Setup docs | `docs/setup.md` |
| Snapshot baselines | `Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/<TestSuite>/...` (committed) |
| Scratch (Phase 0 only) | `scratch/` (deleted at end of Phase 0) |
| Meeting logs | `Sudoku-spec/meetings/{YYYY-MM-DD}_{topic}.md` (spec repo, not impl repo) |

---

## Appendix B — Skill invocation cheatsheet

| Step kind | Required skills |
|---|---|
| Anything writing Swift production code | `swift6-concurrency`, `karpathy-guidelines`, `superpowers:test-driven-development` |
| `Package.swift` / target topology | `swiftpm-modularization`, `apple-platform-targets` |
| First test in a target | `swift-testing-baseline` |
| `.mise.toml` / `lefthook.yml` | `mise-tool-management`, `apple-public-repo-security` |
| Xcode Cloud workflow | `xcode-cloud-single-track-ci` |
| Anything touching `os.Logger` | `oslog-logger-defaults` |
| Telemetry sink / event | `telemetry-facade-pattern`, `apple-three-piece-analytics` |
| Privacy manifest / secrets | `apple-public-repo-security`, `apple-three-piece-analytics` |
| Any SwiftUI View | `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max` |
| Localizable strings | `ai-translated-localization` |
| Multi-round review on a PR | `subagent-review-cycles`, `superpowers:requesting-code-review` |
| Sub-agent dispatch | `leader-developer-handoff-contract` |
| Plan execution session | `superpowers:executing-plans`, `superpowers:subagent-driven-development` |
| Parallel independent tasks | `superpowers:dispatching-parallel-agents`, `superpowers:using-git-worktrees` |
| Before claiming a step done | `superpowers:verification-before-completion` |
| Bug / test failure | `superpowers:systematic-debugging` |
| Session wrap-up | `session-to-meeting-log`, `backlog-routing-by-topic` |

---

## Appendix C — Verification commands (phase gate)

Each phase is "done" only when every command below exits 0 / every checklist is fully green.

### Phase 0
- `swift run --package-path scratch/SplitMix64Probe splitmix64-probe` matches hand-computed reference.
- `swift test --package-path scratch/GeneratorProbe --filter test_hardGenerator_p95_under500ms` → green.
- `meetings/2026-05-17_phase0-gates.md` exists and contains the App Store policy conclusion paragraph.

### Phase 1
- `bash ci_scripts/test_repo_hygiene.sh` → exit 0.
- `bash ci_scripts/test_mise_resolves.sh` → exit 0.
- `swift build --package-path Packages/SudokuKit` → clean (0 warnings).
- `xcodebuild -scheme Sudoku -destination "platform=iOS Simulator,name=iPhone 16 Pro" build` → clean.
- `xcodebuild -scheme Sudoku -destination "platform=macOS,arch=arm64" build` → clean.
- Xcode Cloud PR CI passes on a no-op PR.

### Phase 2
- `swift test --package-path Packages/SudokuKit --filter SudokuEngineTests` → green.
- Coverage of `SudokuEngine` ≥ 95% (manual `xcrun llvm-cov`; not CI-enforced).
- 15 frozen `(seed, difficulty)` snapshots match exact strings.
- Re-measured Hard p95 < 500ms; recorded in `meetings/`.

### Phase 3
- `swift test --filter GameStateTests` → green.
- Coverage of `GameState` ≥ 90%.

### Phase 4
- `swift test --filter TelemetryTests` → green.
- Coverage of `Telemetry` ≥ 90%.

### Phase 5
- `swift test --filter PersistenceTests` → green.
- Coverage of `Persistence` ≥ 85%.
- No `import CloudKit` outside `Sources/Persistence/Live/`.

### Phase 6
- `swift test --filter PuzzleStoreTests` → green.
- Coverage of `PuzzleStore` ≥ 85%.

### Phase 7
- `swift test --filter GameCenterClientTests` → green.
- Coverage of `GameCenterClient` ≥ 80% (excluding `Live/`).
- No `import GameKit` outside `Sources/GameCenterClient/Live/`.

### Phase 8
- `swift test --filter SudokuUITests` → green.
- `git ls-files Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/ | wc -l` = 21.
- No `import CloudKit` / `import GameKit` anywhere in `Sources/SudokuUI/`.

### Phase 9
- `xcodebuild -scheme Sudoku -destination "generic/platform=iOS" archive` → green.
- `PrivacyInfo.xcprivacy` validates against Apple's privacy manifest checker.
- All 7 locales present in `Localizable.xcstrings`; 0 untranslated keys.
- ASC Game Center: 21 leaderboard strings + 56 achievement strings present.

### Phase 10
- TestFlight build installs and runs on iPhone 16 Pro + Mac arm64.
- All 9 Game Center sandbox checklist items green.
- All 8 CloudKit dev container checklist items green.
- ASC "Ready for Submission" green.
- `git tag v1.0.0` pushed; Xcode Cloud Release workflow succeeds.
- Apple review approved.
