# Sudoku v1 — Implementation Plan

Status: **DRAFT** — awaiting first execution.
Last updated: 2026-05-17
Total phases: **10**; total steps: **63**.

This plan operationalizes `docs/design.md §How.1`–`§How.7` and `docs/foundations.md §1`–`§8`. The implementation lives in a sibling repo `Sudoku/` (this repo `Sudoku-spec/` is spec-only); all file paths below are anchored at the `Sudoku/` repo root.

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

---

## Phase 0 — Prerequisite gates (no production code yet)

Verifies `design.md §How.4.9` and unblocks Phase 2 algorithm choices.

### 0.1 SplitMix64 cross-architecture bit-identical reference vector

Tests to write first (red):
- Standalone Swift package `Sudoku/scratch/SplitMix64Probe/` containing a single XCTest-free executable (`swift run splitmix64-probe`) printing 16 hex outputs for seeds `0x0000000000000000` and `0x000000000000002A`.
- Hand-computed reference (from the SplitMix64 paper; reproduce in this step's commit message):
  - seed=0 first 4: `0xE220A8397B1DCDAF`, `0x6E789E6AA1B965F4`, `0x06C45D188009454F`, `0xF88BB8A8724C81EC`
  - seed=42 first 4: `0xC3A6EB6F4C56B931`, `0x76A8D86C92E1A04C`, `0x57D4F12B8B7E83AC`, `0xDBA37AC8CE5C9D38`
  - (Remaining 12 entries computed during the step; commit captures them as canonical.)

Implementation (green):
- File: `Sudoku/scratch/SplitMix64Probe/Package.swift` — executable product, swift-tools-version 6.0, platforms `[.macOS(.v26)]`.
- File: `Sudoku/scratch/SplitMix64Probe/Sources/main.swift` — inline `SplitMix64` matching the §How.4.2 source listing; prints two 16-line blocks.

Acceptance:
- `swift run splitmix64-probe` from macOS arm64 dev machine and from a `xcrun simctl spawn "iPhone 16 Pro" splitmix64-probe` invocation produce **byte-identical** output.
- Hex values match the hand-computed reference exactly.
- Output captured in `meetings/2026-05-17_phase0-gates.md`.

Skills to invoke: `swift6-concurrency`, `karpathy-guidelines`.

Depends on: —

Notes: This scratch package is **not** part of `SudokuKit` and is deleted at end of Phase 0; reference vectors migrate into `SudokuEngineTests/Fixtures/SplitMix64Reference.swift` in step 2.3.

### 0.2 Generator performance baseline (Hard p95)

Tests to write first (red):
- Test target `Sudoku/scratch/GeneratorProbe/Tests/PerfProbeTests.swift` (XCTest harness, deleted at end of Phase 0).
- Test name: `test_hardGenerator_p95_under500ms` — runs the prototype generator 30 times on Hard difficulty, asserts `p95 < 500ms`.

Implementation (green):
- File: `Sudoku/scratch/GeneratorProbe/Sources/PrototypeGenerator.swift` — stripped-down implementation of §How.4.3 flow: SplitMix64 + randomized backtracking fill + clue masking + `nakedSingle`-only uniqueness check (not the full 3-tier calibrator; this is a baseline, not the final algorithm).
- File: `Sudoku/scratch/GeneratorProbe/Sources/Measure.swift` — wall-clock measurement using `ContinuousClock`.

Acceptance:
- 30-run Hard sample: median, p50, p95, p99, max recorded in `meetings/2026-05-17_phase0-gates.md`.
- Pass condition: **p95 < 500ms** on dev machine (Apple Silicon, Xcode 26.5 simulator iPhone 16 Pro).
- If p95 ≥ 500ms: open a §How.4.7 ADR amendment proposal before Phase 2 starts; do not proceed.

Skills to invoke: `swift6-concurrency`, `karpathy-guidelines`.

Depends on: 0.1 (reuses the SplitMix64 reference).

Notes: This probe is **shadow-validated** in Phase 2 — step 2.7 re-runs the same measurement against the production `PuzzleGenerator`. Phase 0 result is the contract; Phase 2 must not regress.

### 0.3 App Store policy spot-check (deterministic puzzle + leaderboard)

Tests to write first (red):
- N/A (policy verification; documented evidence is the artifact).

Implementation (green):
- File: `meetings/2026-05-17_phase0-gates.md` § App Store policy spot-check.
- Steps recorded:
  1. Open Apple Developer "App Review Guidelines" (https://developer.apple.com/app-store/review/guidelines/) — version retrieved on 2026-05-17.
  2. Search keywords: `randomly generated`, `deterministic`, `leaderboard`, `Game Center`, `user-generated content`, `gambling`, `algorithm`.
  3. Sections reviewed in full: 1.1 (Objectionable Content), 1.2 (User-Generated Content), 4.0 (Design / Minimum Functionality), 5.1.1 (Privacy), 5.3 (Gaming, Gambling, and Lotteries).
  4. Forum sample (Apple Developer Forums + WWDC labs notes, last 12 months) — link list with retrieval date.
  5. Conclusion paragraph.

Acceptance:
- Conclusion explicitly answers: *"Does any App Store rule prohibit shipping a Game Center leaderboard whose puzzle content is generated locally by a deterministic algorithm with a shared seed?"* Required answer for Phase 0 pass: **No.**
- Evidence committed to `meetings/` (not `docs/`) per the methodology pattern split.

Skills to invoke: `apple-public-repo-security` (for the privacy-disclosure cross-check), `karpathy-guidelines`.

Depends on: —

Notes: If Apple has a new 2026 clause about AI-generated or algorithmically generated content disclosure, document it; v1 generator is deterministic + algorithmic, not ML, so §1.2 AI-generated disclosure likely does not apply, but this must be confirmed not assumed.

---

## Phase 1 — Implementation repo bootstrap + tooling

Creates `Sudoku/` sibling repo from scratch with the tooling baseline.

### 1.1 Repo skeleton + `.gitignore` + LICENSE

Tests to write first (red):
- File: `Sudoku/ci_scripts/test_repo_hygiene.sh` — bash script asserting: no `.env` file tracked, no `*.p8` / `*.p12` / `*.pem` tracked, `.gitignore` contains every entry from `foundations.md §7.4`.

Implementation (green):
- `Sudoku/.gitignore` — verbatim from `foundations.md §7.4`.
- `Sudoku/LICENSE` — MIT (project is public-repo-from-day-1).
- `Sudoku/README.md` — pointer to `Sudoku-spec/` for design context.
- `Sudoku/.gitattributes` — `*.png binary`, snapshot baseline handling.

Acceptance:
- `bash ci_scripts/test_repo_hygiene.sh` exits 0.
- `git ls-files | grep -E '\.(p8|p12|pem|env)$'` returns empty.

Skills to invoke: `apple-public-repo-security`.

Depends on: Phase 0 fully green.

### 1.2 `.mise.toml` + lefthook + gitleaks

Tests to write first (red):
- File: `Sudoku/ci_scripts/test_mise_resolves.sh` — asserts `mise list` shows swiftlint, swiftformat, xcbeautify, gitleaks, lefthook all at pinned versions; `mise exec gitleaks -- version` returns ≥ v8.18.

Implementation (green):
- File: `Sudoku/.mise.toml` — tools per `foundations.md §7.5`; `lefthook` and `gitleaks` source TBD-resolved here (try `aqua:` backend first; fall back to `ubi:` if aqua plugin missing — verify with `mise plugin list --all`). Pin every tool to a specific minor.
- File: `Sudoku/lefthook.yml` — verbatim from `foundations.md §7.5`.
- File: `Sudoku/.gitleaks.toml` — inherits gitleaks `default.toml`; adds two custom rules for CloudKit Key ID and ASC API Key ID (both `[A-Z0-9]{10}` with context filters).
- File: `Sudoku/docs/setup.md` — onboarding: `mise install` → `lefthook install` → Xcode Cloud env-var setup pointers.

Acceptance:
- `mise install` from fresh checkout succeeds on macOS arm64.
- `lefthook install` writes `.git/hooks/pre-commit`.
- A test commit containing `-----BEGIN PRIVATE KEY-----` is blocked by `gitleaks` pre-commit.
- `bash ci_scripts/test_mise_resolves.sh` exits 0.

Skills to invoke: `mise-tool-management`, `apple-public-repo-security`.

Depends on: 1.1.

Notes: Resolves `foundations.md §7.11` lefthook-via-mise open item. If aqua plugin does not provide lefthook, document the actual backend chosen.

### 1.3 SwiftPM package `SudokuKit` skeleton

Tests to write first (red):
- File: `Sudoku/Packages/SudokuKit/Tests/SudokuKitSmokeTests/SmokeTests.swift` — single `@Test func packageCompiles() {}`; verifies swift-testing wiring.

Implementation (green):
- File: `Sudoku/Packages/SudokuKit/Package.swift` — swift-tools-version 6.0; `platforms: [.iOS(.v26), .macOS(.v26)]`; declares 8 product targets (`SudokuEngine`, `GameState`, `PuzzleStore`, `Persistence`, `GameCenterClient`, `Telemetry`, `SudokuUI`, `SudokuKitTesting`) + 8 test targets; `swiftLanguageMode: .v6`; `swiftSettings: [.enableUpcomingFeature("StrictConcurrency"), .enableExperimentalFeature("StrictConcurrency=complete")]`.
- File: per-target `Sources/<Module>/<Module>.swift` placeholder with a single `public func _moduleAnchor() {}`.
- Snapshot framework dep: `pointfreeco/swift-snapshot-testing` from `1.17.0`.

Acceptance:
- `swift build --package-path Sudoku/Packages/SudokuKit` compiles clean (no warnings) on Swift 6 strict mode.
- `swift test --package-path Sudoku/Packages/SudokuKit --filter SudokuKitSmokeTests` green.

Skills to invoke: `swiftpm-modularization`, `swift6-concurrency`, `swift-testing-baseline`, `apple-platform-targets`.

Depends on: 1.2.

### 1.4 App target Xcode project + multiplatform scheme

Tests to write first (red):
- N/A at Xcode-project level; functional tests live in 1.3 / Phase 8.

Implementation (green):
- `Sudoku/App/Sudoku.xcodeproj` — single multiplatform App target, name `Sudoku`, bundle ID `com.wei18.sudoku`, deployment iOS 26 / macOS 26.
- `Sudoku/App/SudokuApp.swift` — minimal `@main struct SudokuApp: App { var body: some Scene { WindowGroup { Text("placeholder") } } }`.
- `Sudoku/App/Info.plist` — minimum; deferred entitlements wire-up to Phase 9.
- `Sudoku/App/Assets.xcassets` — AppIcon placeholder, AccentColor anchor `#5C7A4F` (per `docs/designs/design-system.md`).
- Xcode project references `SudokuKit` via local package.

Acceptance:
- `xcodebuild -scheme Sudoku -destination "platform=iOS Simulator,name=iPhone 16 Pro" build` succeeds.
- `xcodebuild -scheme Sudoku -destination "platform=macOS,arch=arm64" build` succeeds.
- No new warnings.

Skills to invoke: `swiftpm-modularization`, `apple-platform-targets`.

Depends on: 1.3.

### 1.5 Xcode Cloud workflows (PR / Main / Release)

Tests to write first (red):
- N/A.

Implementation (green):
- App Store Connect → Xcode Cloud → 3 workflows per `foundations.md §4`:
  - **PR CI**: trigger on pull request to `main`, branch base merge enabled, build + test action.
  - **Main CI**: trigger on push to `main`, build + archive + TestFlight internal upload, no test action.
  - **Release**: trigger on tag `v*`, build + archive + App Store Connect upload (manual submit).
- File: `Sudoku/ci_scripts/ci_post_clone.sh` — `mise install` + `mise exec gitleaks -- git --pre-commit --staged --redact` (per `foundations.md §7.6`). Fail build on non-zero exit.
- File: `Sudoku/ci_scripts/ci_pre_xcodebuild.sh` — empty placeholder (header only).
- Xcode Cloud env vars: locked Xcode 26.5; no secrets needed at this phase.

Acceptance:
- Push a no-op PR; PR CI runs `ci_post_clone.sh`, `swift test` passes (Phase 1.3 smoke), result reported on GitHub.
- Main CI on first merge produces a TestFlight build (record build number).
- gitleaks step blocks a test PR that intentionally introduces a fake private-key block.

Skills to invoke: `xcode-cloud-single-track-ci`, `mise-tool-management`, `apple-public-repo-security`.

Depends on: 1.4.

### 1.6 GitHub repo public + Secret Scanning Alerts

Tests to write first (red):
- N/A.

Implementation (green):
- Create public GitHub repo `Wei18/Sudoku`.
- Settings → Code security: enable Secret scanning alerts + Push protection.
- Branch protection on `main`: require PR review, require Xcode Cloud PR CI status check.

Acceptance:
- A test push of a sample Apple-format secret to a side branch is blocked by Push protection.
- `main` cannot be pushed to directly.

Skills to invoke: `apple-public-repo-security`.

Depends on: 1.1.

### 1.7 ASC bundle ID + entitlements stubs

Tests to write first (red):
- N/A.

Implementation (green):
- App Store Connect: reserve bundle ID `com.wei18.sudoku`; create iOS + macOS app records (Game Center enabled).
- `Sudoku/App/Sudoku.entitlements` — `com.apple.developer.icloud-services = [CloudKit]`, container `iCloud.com.wei18.sudoku`; `com.apple.developer.game-center = true`.
- CloudKit Dashboard: create container `iCloud.com.wei18.sudoku` with Public + Private DB scopes (Public DB unused in v1 per §How.2 but reserved).

Acceptance:
- Provisioning profile (automatic) builds cleanly via Xcode Cloud (re-trigger 1.5 PR CI).
- CloudKit Dashboard shows container present, no record types yet.

Skills to invoke: `xcode-cloud-single-track-ci`, `apple-public-repo-security`.

Depends on: 1.5, 1.6.

---

## Phase 2 — `SudokuEngine` (pure core)

Implements `design.md §How.4` end-to-end. Pure Swift, no Apple framework imports.

### 2.1 `Board` model + encoding

Tests to write first (red):
- `Tests/SudokuEngineTests/BoardTests.swift` — @Suite `BoardEncoding`:
  - `roundtripEmptyBoard` — encode/decode 81 dots → equal.
  - `roundtripFullBoard` — random valid grid → equal.
  - `rejectMalformedLength` — 80-char string throws `Board.DecodeError.length`.

Implementation (green):
- `Sources/SudokuEngine/Board.swift` — `public struct Board: Sendable, Equatable, Hashable`; fields `cells: [UInt8]` (length 81); methods `init(encoded:) throws`, `encoded() -> String`, `subscript(row:col:)`.
- `public enum CellValue: UInt8, Sendable { case empty = 0, one = 1, ..., nine = 9 }`.

Acceptance:
- 3/3 tests green; `swift test --filter BoardTests` clean.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: Phase 1 complete.

### 2.2 `Board.validate` rules

Tests to write first (red):
- @Suite `BoardValidation` (target ≥ 6 tests):
  - `rowConflict` / `colConflict` / `boxConflict` — each: fixture with one duplicate digit → `.conflict(.row(i))` / `.col(i)` / `.box(i)`.
  - `clueImmutable(digit:)` parameterized over [1,5,9] — placing onto a clue cell throws.
  - `validBoardReturnsOK` — `BoardFixtures.solvedKnown` → `.ok`.

Implementation (green):
- `Sources/SudokuEngine/BoardValidation.swift` — `public enum ValidationOutcome: Sendable, Equatable { case ok; case conflict(Constraint) }`; `public extension Board { func validate() -> ValidationOutcome }`.
- `Sources/SudokuEngine/Fixtures/` — internal `BoardFixtures` (puzzle string constants).

Acceptance:
- ≥ 6 tests green; coverage of `BoardValidation.swift` ≥ 95%.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 2.1.

### 2.3 `DeterministicRNG` + `SplitMix64`

Tests to write first (red):
- `Tests/SudokuEngineTests/SplitMix64Tests.swift` — @Suite `SplitMix64`:
  - `seedZeroFirst16` — asserts 16-output sequence against Phase 0 reference vector (migrated from Phase 0 probe).
  - `seed42First16` — same for seed 42.
  - `independentInstancesIdentical` — two instances with same seed produce same sequence.

Implementation (green):
- `Sources/SudokuEngine/RNG/DeterministicRNG.swift` — `public protocol DeterministicRNG: Sendable { mutating func next() -> UInt64 }`.
- `Sources/SudokuEngine/RNG/SplitMix64.swift` — verbatim from §How.4.2 listing.
- `Sources/SudokuEngine/RNG/ScriptedRNG.swift` — test-only (internal), feeds canned sequence (lives in `SudokuKitTesting`).
- `Sources/SudokuKitTesting/RNG/ScriptedRNG.swift` — public for tests across modules.
- `Tests/SudokuEngineTests/Fixtures/SplitMix64Reference.swift` — frozen reference vectors from Phase 0.

Acceptance:
- 3 tests green.
- Phase 0.1 scratch package deleted; reference vectors live only in `SplitMix64Reference.swift`.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: 2.1, Phase 0 closed.

### 2.4 `Move` + `UndoStack(20)`

Tests to write first (red):
- @Suite `MoveAndUndo`:
  - `applyUnapplySymmetric` — random Move applied then unapplied → original board.
  - `stackCapsAt20` — push 25 moves → oldest 5 dropped; `count == 20`.
  - `redoAfterUndo` — undo + redo → state restored.
  - `pushClearsRedo` — undo then new push clears redo stack.

Implementation (green):
- `Sources/SudokuEngine/Move.swift` — `public struct Move: Sendable, Equatable, Codable { ... }`; `place(row, col, digit)` and `note(row, col, mask)` variants.
- `Sources/SudokuEngine/UndoStack.swift` — fixed capacity 20; ring buffer.

Acceptance:
- 4 tests green; coverage ≥ 95%.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 2.1.

### 2.5 `UniquenessValidator` (DFS + short-circuit)

Tests to write first (red):
- @Suite `UniquenessValidator`:
  - `uniqueSolutionFound` — `BoardFixtures.knownUnique` → `.unique(solution)`.
  - `multipleSolutionsShortCircuit` — fixture with exactly 2 solutions → `.multiple(count: 2, samples: …)` and validator exits before exhaustion (assert step counter < threshold via injected probe).
  - `unsolvable` — contradictory fixture → `.unsolvable`.

Implementation (green):
- `Sources/SudokuEngine/UniquenessValidator.swift` — DFS with second-solution short-circuit; `public enum ValidationResult: Sendable, Equatable { case unique(Board); case multiple(count: Int, samples: [Board]); case unsolvable }`.

Acceptance:
- 3 tests green; DFS step counter probe verifies short-circuit behavior.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 2.2.

### 2.6 `PuzzleCalibrator` (3-layer propagation)

Tests to write first (red):
- @Suite `Calibrator`:
  - `nakedSingleSolvable` — fixture solvable by nakedSingle only.
  - `hiddenSinglePromoted` — fixture requiring hiddenSingle to progress.
  - `nakedPairAppliedExactlyOnce` — counter probe.
  - `easyRejectsNonPropagationOnly` — fixture needing DFS guess → Easy verifier rejects.
  - `easyClueCountBoundary` — clueCount 31 reject, 32 accept, 50 accept, 51 reject.
  - `branchingFactorCounted` — DFS w/o techniques, asserts count.

Implementation (green):
- `Sources/SudokuEngine/Calibrator/PropagationSolver.swift` — three rules with explicit `applied: Int` counters.
- `Sources/SudokuEngine/Calibrator/PuzzleCalibrator.swift` — `public func calibrate(board: Board, target: Difficulty) -> CalibrationResult`.

Acceptance:
- 6 tests green; coverage of calibrator ≥ 95%.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 2.5.

### 2.7 `PuzzleGenerator` + `Puzzle` + retry budget

Tests to write first (red):
- @Suite `Generator`:
  - `frozenOutputSeed0Easy` — frozen `(clues, solution)` snapshot for `(seed=0, .easy, .v1)` (exact string match).
  - `frozenOutputSeed0Medium`, `frozenOutputSeed0Hard` — same.
  - First 5 daily-seed × 3 difficulty = 15 frozen snapshots total (§How.4.6).
  - `retryBudgetFindsValidPuzzle` — feed `ScriptedRNG` forcing 31 calibrator rejections then 1 accept → returns puzzle.
  - `exhaustedAfterN32` — `ScriptedRNG` forcing 32 rejections → throws `GeneratorError.exhausted`.
  - `bitIdenticalRepeatedCalls` — same seed twice → equal `Puzzle`.

Implementation (green):
- `Sources/SudokuEngine/Generator/GeneratorVersion.swift` — `public enum GeneratorVersion: Int, Sendable, Equatable, Codable, CaseIterable { case v1 = 1 }`.
- `Sources/SudokuEngine/Generator/Puzzle.swift` — `public struct Puzzle: Sendable, Equatable, Codable { ... }` (per §How.4.3).
- `Sources/SudokuEngine/Generator/PuzzleGenerator.swift` — `public protocol PuzzleGenerator: Sendable { func generate(seed:difficulty:version:) throws -> Puzzle }` + live `LivePuzzleGenerator` struct.
- `Sources/SudokuEngine/Generator/GeneratorError.swift` — `case exhausted(reason: String)`, `case cancelled` (Sendable + Equatable).
- Re-run Phase 0.2 measurement against `LivePuzzleGenerator`; record updated p95 in `meetings/`. Must not regress vs Phase 0 baseline.

Acceptance:
- 18 tests green (15 frozen + 3 behavior).
- `SudokuEngineTests` coverage ≥ 95% per §How.7.1.
- p95 re-measurement < 500ms.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 2.3, 2.5, 2.6.

Notes: Frozen snapshots are the cross-architecture determinism gate. Any Xcode major upgrade re-runs all 15.

---

## Phase 3 — `GameState`

Implements `design.md §How.5.3` state machine + `§How.5.4` snapshot value type. No CloudKit / GC imports.

### 3.1 `GameSession.Status` state machine

Tests to write first (red):
- `Tests/GameStateTests/SessionStatusTests.swift`:
  - All 5 valid transitions enumerated as parameterized cases.
  - 4 illegal transitions throw `IllegalTransition`.

Implementation (green):
- `Sources/GameState/GameSession.swift` — `public struct GameSession: Sendable` with `public enum Status: Sendable, Equatable { case idle, playing, paused, completed, abandoned }`.
- `Sources/GameState/SessionTransitions.swift` — mutating `start`, `pause`, `resume`, `complete`, `abandon`.

Acceptance:
- Tests green; coverage ≥ 95%.

Skills to invoke: `swift-testing-baseline`, `swift6-concurrency`, `karpathy-guidelines`.

Depends on: Phase 2 complete.

### 3.2 `placeDigit` / `note` / `undo` / `redo`

Tests to write first (red):
- `Tests/GameStateTests/MoveAPITests.swift`:
  - `placeDigitUpdatesBoard` happy + invalid (over clue) throw.
  - `noteTogglesCandidate` — bitmask flip.
  - `undoReversesPlace`, `redoReplaysPlace`.
  - `cannotMoveWhenPaused` throws.

Implementation (green):
- `Sources/GameState/MoveAPI.swift` — extends `GameSession` with `placeDigit`, `note`, `undo`, `redo`; routes through `SudokuEngine.UndoStack`.

Acceptance:
- 5 tests green; coverage ≥ 90%.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 3.1, Phase 2.

### 3.3 Clock-injected `elapsedSeconds`

Tests to write first (red):
- `Tests/GameStateTests/ElapsedTests.swift`:
  - `pauseFreezesClock` (per §How.7.2 sample).
  - `resumeContinuesAccumulation`.
  - `completedFreezes`.

Implementation (green):
- `Sources/SudokuKitTesting/Clock/FakeClock.swift` — `public actor FakeClock { advance(by:) }`.
- `Sources/GameState/Clock+Inject.swift` — `GameSession` holds an `any Clock` (Swift 6 stdlib `Clock` protocol).

Acceptance:
- 3 tests green; `FakeClock` reused in Phase 4–8.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: 3.1.

### 3.4 `GameSessionSnapshot` value type

Tests to write first (red):
- `Tests/GameStateTests/SnapshotTests.swift`:
  - `snapshotMirrorsSession` — round-trip equality.
  - `codableRoundtrip` — JSON encode/decode.
  - `mapToSavedGameFields` — asserts field mapping to `SavedGame` per §How.2 (table-driven).

Implementation (green):
- `Sources/GameState/GameSessionSnapshot.swift` — `public struct GameSessionSnapshot: Sendable, Equatable, Codable { ... }`.
- Public mapping helpers (`toSavedGameFields()`).

Acceptance:
- 3 tests green.

Skills to invoke: `swift-testing-baseline`.

Depends on: 3.2, 3.3.

### 3.5 Telemetry emission on transitions

Tests to write first (red):
- `Tests/GameStateTests/TelemetryEmissionTests.swift`:
  - `completionEventFiresExactlyOnce` (per §How.7.2 sample).
  - `pauseEmitsSessionPaused`.
  - `abandonEmitsSessionAbandoned`.
  - `placeDigitEmitsDigitPlaced`.

Implementation (green):
- `Sources/GameState/TelemetryBridge.swift` — `GameSession` holds `Telemetry` and emits in `place/pause/complete/abandon`. Depends only on `Telemetry` protocol surface (Phase 4 may not yet be implemented; use a forward-declared protocol satisfied by Phase 4).

Acceptance:
- 4 tests green using `SpyTelemetry` from `SudokuKitTesting`.

Skills to invoke: `telemetry-facade-pattern`, `swift-testing-baseline`.

Depends on: 3.4. *Soft dependency on Phase 4.1 (TelemetryEvent enum surface).* If running in parallel, this step blocks on 4.1 only.

---

## Phase 4 — `Telemetry`

Implements `design.md §How.1` fan-out + `foundations.md §5 §6`. Can run in parallel with Phase 3 once 4.1 is done.

### 4.1 `TelemetryEvent` enum + `TelemetrySink` protocol

Tests to write first (red):
- `Tests/TelemetryTests/EventSendableTests.swift`:
  - `allCasesAreSendable` — compile-time check via generic constraint.
  - `equatablePerCase` — pair each case with itself.

Implementation (green):
- `Sources/Telemetry/TelemetryEvent.swift` — `public enum TelemetryEvent: Sendable, Equatable { case digitPlaced(...); case puzzleCompleted(puzzleId: String, mode: GameMode, difficulty: Difficulty, elapsedSeconds: Int); case sessionPaused; case sessionAbandoned; case errorOccurred(source: String, code: String); case metricKitReport(MetricReport) }`.
- `Sources/Telemetry/TelemetrySink.swift` — `public protocol TelemetrySink: Sendable { func receive(_ event: TelemetryEvent) async }`.
- `Sources/Telemetry/GameMode.swift`, `Difficulty.swift` — value types `: Sendable, Equatable, Codable`.

Acceptance:
- 2 tests green; module compiles strict-concurrency clean.

Skills to invoke: `telemetry-facade-pattern`, `swift6-concurrency`.

Depends on: Phase 1.

### 4.2 `Telemetry` actor (fan-out)

Tests to write first (red):
- `Tests/TelemetryTests/FanOutTests.swift`:
  - `allSinksReceiveEvent`.
  - `throwingSinkDoesNotBlockOthers` — even with one sink crashing, others receive.
  - `eventOrderingPreserved` per sink (FIFO).

Implementation (green):
- `Sources/Telemetry/Telemetry.swift` — `public actor Telemetry { public init(sinks: [any TelemetrySink]); public func observe(_ event: TelemetryEvent) async }`.

Acceptance:
- 3 tests green.

Skills to invoke: `telemetry-facade-pattern`, `swift6-concurrency`.

Depends on: 4.1.

### 4.3 `OSLogSink` + `LoggerProtocol` seam

Tests to write first (red):
- `Tests/TelemetryTests/OSLogSinkTests.swift`:
  - `categoryEqualsModuleName` — assert FakeLogger category captured matches event source.
  - `privacyDefaultsPrivate` — non-flagged interpolation passes through `.private`.
  - `publicFlagRespected`.

Implementation (green):
- `Sources/Telemetry/LoggerProtocol.swift` — minimal seam wrapping `os.Logger` (`func log(level:_:message:)`).
- `Sources/Telemetry/OSLogSink.swift` — `public struct OSLogSink: TelemetrySink { ... }`.
- `Sources/SudokuKitTesting/Telemetry/FakeLogger.swift` — captures invocations.

Acceptance:
- 3 tests green.

Skills to invoke: `oslog-logger-defaults`, `telemetry-facade-pattern`.

Depends on: 4.2.

### 4.4 `NoOpTrackingSink`

Tests to write first (red):
- `Tests/TelemetryTests/NoOpSinkTests.swift`:
  - `receiveIsNoOp` — no side effects observable.

Implementation (green):
- `Sources/Telemetry/NoOpTrackingSink.swift` — verbatim from `foundations.md §6`.

Acceptance:
- 1 test green.

Skills to invoke: `telemetry-facade-pattern`, `apple-three-piece-analytics`.

Depends on: 4.1.

### 4.5 `MetricKitSink`

Tests to write first (red):
- `Tests/TelemetryTests/MetricKitSinkTests.swift`:
  - `payloadBecomesMetricKitReportEvent`.
  - `crashDiagnosticIsForwarded`.

Implementation (green):
- `Sources/Telemetry/MetricKitSink.swift` — `public final class MetricKitSink: NSObject, MXMetricManagerSubscriber, TelemetrySink { ... }` (NSObject + Sendable considerations: actor-isolated state + nonisolated delegate methods).
- `Sources/Telemetry/MetricReport.swift` — `public struct MetricReport: Sendable, Equatable, Codable` (decoupled from MetricKit types for cross-actor passing).
- `Sources/SudokuKitTesting/Telemetry/MetricPayloadFixtures.swift` — canned `MXMetricPayload`-like fixtures.

Acceptance:
- 2 tests green.

Skills to invoke: `apple-three-piece-analytics`, `telemetry-facade-pattern`, `swift6-concurrency`.

Depends on: 4.2.

---

## Phase 5 — `Persistence` (CloudKit Private DB)

Implements `design.md §How.2` schema + `§How.6.5` `§How.6.7` conflict / account flows. All work through `FakePrivateCKGateway` in tests; live impl validated manually in Phase 10.

### 5.1 `PersistenceProtocol` + value types

Tests to write first (red):
- `Tests/PersistenceTests/ProtocolShapeTests.swift`:
  - Compile-time: all protocol methods are `async throws`, protocol is `Sendable`.
  - All value types (`SavedGameSummary`, `PersonalRecord`) `Sendable + Equatable + Codable`.

Implementation (green):
- `Sources/Persistence/PersistenceProtocol.swift` — verbatim from §How.5.4 listing.
- `Sources/Persistence/SavedGameSummary.swift`, `PersonalRecord.swift`.

Acceptance:
- Module compiles strict-concurrency clean.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: Phase 3, Phase 4.

### 5.2 Custom zone provisioning

Tests to write first (red):
- `Tests/PersistenceTests/ZoneProvisioningTests.swift`:
  - `provisionCreatesUserZoneOnce` — fake gateway records 1 `CKModifyRecordZonesOperation` add.
  - `idempotentOnExistingZone` — second call observes zone present, no second add.

Implementation (green):
- `Sources/Persistence/Live/PrivateCKGateway.swift` — internal actor wrapping `CKDatabase`; constant `zoneID = CKRecordZone.ID(zoneName: "com.wei18.sudoku.userZone", ownerName: CKCurrentUserDefaultName)`.
- `Sources/SudokuKitTesting/Persistence/FakePrivateCKGateway.swift` — actor mirroring live API surface.

Acceptance:
- 2 tests green.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: 5.1.

### 5.3 `CKDatabaseSubscription` setup

Tests to write first (red):
- `Tests/PersistenceTests/SubscriptionTests.swift`:
  - `subscriptionCreatedOnFirstLaunch`.
  - `idempotentOnRelaunch`.

Implementation (green):
- `Sources/Persistence/Live/SubscriptionInstaller.swift` — installs a single `CKDatabaseSubscription` per §How.2.

Acceptance:
- 2 tests green.

Skills to invoke: `swift6-concurrency`.

Depends on: 5.2.

### 5.4 `SavedGame` CRUD + `generatorVersion` field

Tests to write first (red):
- `Tests/PersistenceTests/SavedGameCRUDTests.swift`:
  - `loadOrCreateNewPuzzleSeedsFromGameState`.
  - `saveRoundtrips`.
  - `markCompletedSetsStatus`.
  - `deleteAbandonedRemovesRecord`.
  - `generatorVersionPersisted`.

Implementation (green):
- `Sources/Persistence/Live/SavedGameStore.swift` — maps `GameSessionSnapshot` ↔ `CKRecord` (12 fields per §How.2).

Acceptance:
- 5 tests green; coverage ≥ 85%.

Skills to invoke: `swift-testing-baseline`, `swift6-concurrency`.

Depends on: 5.2.

### 5.5 `PersonalRecord` CRUD + dedup

Tests to write first (red):
- `Tests/PersistenceTests/PersonalRecordTests.swift`:
  - `recordNameIsModeDifficulty` — deterministic key.
  - `reCompletingSamePuzzleIdDoesNotBump` (§How.2 末段 rule).
  - `fetchAllReturnsAtMostSix`.

Implementation (green):
- `Sources/Persistence/Live/PersonalRecordStore.swift`.

Acceptance:
- 3 tests green.

Skills to invoke: `swift-testing-baseline`.

Depends on: 5.2.

### 5.6 Per-field LWW conflict resolver

Tests to write first (red):
- `Tests/PersistenceTests/ConflictResolverTests.swift`:
  - `boardNotesUndoSwitchedAsGroup` — newer lastModifiedAt wins all three.
  - `elapsedSecondsTakesMax`.
  - `statusCompletedWinsOverInProgress`.
  - `personalRecordBestTimeTakesMin`.
  - `personalRecordCountsTakeMax`.
  - `threeConflictsThrowSyncConflict`.

Implementation (green):
- `Sources/Persistence/Live/ConflictResolver.swift` — per §How.6.7 table; retry budget 2 + final throw.

Acceptance:
- 6 tests green; coverage ≥ 90%.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 5.4, 5.5.

### 5.7 `CKAccountChanged` flow (Case A / B / C)

Tests to write first (red):
- `Tests/PersistenceTests/AccountFlowTests.swift`:
  - `caseANeverSignedIn` — `iCloudNotSignedIn` thrown; reads of `SavedGame` from local cache still succeed.
  - `caseBSignedOutDuringSession` — flush triggered, local cache retained, subsequent CK ops throw `iCloudSignedOutDuringSession`.
  - `caseCAccountChanged` — hash mismatch detected; wipe-on-confirm clears caches.

Implementation (green):
- `Sources/Persistence/Live/AccountMonitor.swift` — observes `CKAccountChanged`; tracks `fetchUserRecordID` hash in Keychain.
- Local cache layer in `Persistence` (file-system backed inside App container).

Acceptance:
- 3 tests green.

Skills to invoke: `swift-testing-baseline`, `apple-public-repo-security`.

Depends on: 5.4, 5.5.

---

## Phase 6 — `PuzzleStore`

Implements `design.md §How.4.3` identity assembly + `§How.5.1` `PuzzleProviderProtocol`.

### 6.1 `PuzzleProviderProtocol` + identity value types

Tests to write first (red):
- `Tests/PuzzleStoreTests/IdentityTests.swift`:
  - `dailyIdentityFormat` — `YYYY-MM-DD-{easy|medium|hard}`.
  - `practiceIdentityBase32`.
  - All value types Sendable/Equatable.

Implementation (green):
- `Sources/PuzzleStore/PuzzleProviderProtocol.swift` — `public protocol PuzzleProviderProtocol: Sendable`.
- `Sources/PuzzleStore/PuzzleIdentity.swift`, `PuzzleEnvelope.swift`, `PuzzleKind.swift` — verbatim from §How.4.3.

Acceptance:
- 3 tests green.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: Phase 2.

### 6.2 Live `PuzzleStore` wrapping `PuzzleGenerator`

Tests to write first (red):
- `Tests/PuzzleStoreTests/StoreLiveTests.swift`:
  - `dailyTrioDeterministicAcrossCalls` (per §How.7.3 sample).
  - `practiceDrawsDistinctPuzzles` — different salt → different puzzleId.
  - `generatorExhaustionPropagates`.

Implementation (green):
- `Sources/PuzzleStore/PuzzleStore.swift` — `public actor PuzzleStore: PuzzleProviderProtocol`; derives seeds per §How.4.1; assembles `PuzzleEnvelope`.
- `Sources/SudokuKitTesting/PuzzleStore/FakeGenerator.swift` — actor for tests.

Acceptance:
- 3 tests green; coverage ≥ 85%.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: 6.1.

### 6.3 In-memory daily trio cache

Tests to write first (red):
- `Tests/PuzzleStoreTests/CacheTests.swift`:
  - `dailyTrioCachedForSameDate` — second call hits cache (counter probe).
  - `cacheInvalidatedOnDateChange`.

Implementation (green):
- Internal cache keyed by `(date, generatorVersion)` inside `PuzzleStore`.

Acceptance:
- 2 tests green.

Skills to invoke: `swift6-concurrency`.

Depends on: 6.2.

### 6.4 Practice salt + OSLog `.public` logging

Tests to write first (red):
- `Tests/PuzzleStoreTests/SaltLoggingTests.swift`:
  - `practiceSaltLoggedPublic` — FakeLogger sees `.public` interpolation containing salt.

Implementation (green):
- `Sources/PuzzleStore/PracticeSalt.swift` — wraps `RandomNumberGenerator` injection (live = `SystemRandomNumberGenerator`).
- Logs salt via `OSLogSink` `.public`.

Acceptance:
- 1 test green; salt source is injectable for tests.

Skills to invoke: `oslog-logger-defaults`, `telemetry-facade-pattern`.

Depends on: 6.2.

---

## Phase 7 — `GameCenterClient`

Implements `design.md §How.3` end-to-end.

### 7.1 Protocol + value types

Tests to write first (red):
- `Tests/GameCenterClientTests/ProtocolShapeTests.swift`:
  - All methods `async throws`; protocol `: Sendable`.
  - All value types `Sendable + Equatable`.

Implementation (green):
- `Sources/GameCenterClient/GameCenterClient.swift` — verbatim from §How.3.3 listing (protocol + all value types + `GameCenterError`).
- `Sources/SudokuKitTesting/GameCenter/FakeGameCenterClient.swift` — actor; scripted state.

Acceptance:
- Module compiles strict-concurrency clean.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: Phase 4.

### 7.2 Live `GKLocalPlayer` authentication

Tests to write first (red):
- `Tests/GameCenterClientTests/AuthTests.swift`:
  - `authenticatedStateSurfaced` — fake `GKAuthDriver` returns success → `.authenticated(Player)`.
  - `cancelledMapsToError`.
  - `restrictedMapsToRestricted`.
  - `authStateUpdatesStreamsChanges`.

Implementation (green):
- `Sources/GameCenterClient/Live/LiveGameCenterClient.swift` — wraps `GKLocalPlayer` (only target importing `GameKit`).
- `Sources/GameCenterClient/Live/AuthDriver.swift` — testable seam over GKLocalPlayer.

Acceptance:
- 4 tests green.

Skills to invoke: `swift6-concurrency`, `swift-testing-baseline`.

Depends on: 7.1.

### 7.3 `submitScore` with Daily-only + first-time + same-UTC-day + `.v1` leaderboard ID

Tests to write first (red):
- `Tests/GameCenterClientTests/SubmitScoreTests.swift`:
  - `practiceModeNeverSubmits` (per §How.7.5 sample).
  - `dailyFirstTimeSubmits`.
  - `dailySecondTimeSkipped`.
  - `crossDayCompletionSkipped`.
  - `leaderboardIDSuffixedV1`.

Implementation (green):
- `Sources/GameCenterClient/SubmitGuards.swift` — `completedDailyPuzzleIds: Set<String>` cache + UTC-day comparator.
- `Sources/GameCenterClient/LeaderboardIDs.swift` — `com.wei18.sudoku.leaderboard.{difficulty}.daily.v1`.

Acceptance:
- 5 tests green.

Skills to invoke: `swift-testing-baseline`, `karpathy-guidelines`.

Depends on: 7.2, Phase 5 (for `completedDailyPuzzleIds` seed).

### 7.4 `reportAchievement` (mode-agnostic, Persistence-counted)

Tests to write first (red):
- `Tests/GameCenterClientTests/AchievementTests.swift`:
  - `firstPuzzleUnlocks`.
  - `dailyStreak3DerivedFromPersistence`.
  - `practiceComplete100PercentProgress`.
  - `dailySweepRequiresAllThreeDifficulties`.
  - `idempotentDoubleReport`.

Implementation (green):
- `Sources/GameCenterClient/AchievementEvaluator.swift` — reads `PersistenceProtocol` counts; computes 8 achievements per §How.3.2 table.

Acceptance:
- 5 tests green.

Skills to invoke: `swift-testing-baseline`.

Depends on: 7.3, Phase 5.

### 7.5 `fetchLeaderboardSlice` (3 scopes) + friends auth precondition

Tests to write first (red):
- `Tests/GameCenterClientTests/LeaderboardSliceTests.swift`:
  - `globalTopReturnsTopN`.
  - `aroundPlayerSplitsAroundSelf`.
  - `friendsOnlyRequiresAuthorization` — `.denied` throws `.friendsAccessDenied`.
  - `notDeterminedTriggersRequest`.
  - `cacheStaleAfter5min`.

Implementation (green):
- `Sources/GameCenterClient/Leaderboard/Slice.swift` — wraps `GKLeaderboard.loadEntries`.

Acceptance:
- 5 tests green.

Skills to invoke: `swift-testing-baseline`, `swift6-concurrency`.

Depends on: 7.2.

### 7.6 `GameCenterSink` (Telemetry consumer)

Tests to write first (red):
- `Tests/GameCenterClientTests/SinkTests.swift`:
  - `puzzleCompletedFanOutFiresSubmitAndAchievements`.
  - `unauthenticatedNoOp`.
  - `restrictedNoOp`.

Implementation (green):
- `Sources/GameCenterClient/GameCenterSink.swift` — `: TelemetrySink`; consumes `.puzzleCompleted` per §How.3.3 fan-out pseudocode.

Acceptance:
- 3 tests green.

Skills to invoke: `telemetry-facade-pattern`, `swift-testing-baseline`.

Depends on: 7.3, 7.4.

### 7.7 macOS region-restricted fallback

Tests to write first (red):
- `Tests/GameCenterClientTests/RegionTests.swift`:
  - `unavailableInRegionMappedFromGKError`.
  - `restrictedHidesLeaderboardUI` — UI presentation flag asserted.

Implementation (green):
- `Sources/GameCenterClient/Live/RegionMapper.swift` — heuristic combining `GKError.Code` + `Locale.current.region`; documented in code comment.

Acceptance:
- 2 tests green.

Skills to invoke: `swift-testing-baseline`.

Depends on: 7.2.

---

## Phase 8 — `SudokuUI`

Implements `design.md §How.5.1`–`§How.5.8`. All Views consume protocols only; no `CloudKit` / `GameKit` imports. References `docs/designs/` per-View specs.

### 8.1 `Theme` protocol + `DefaultTheme`

Tests to write first (red):
- `Tests/SudokuUITests/ThemeTests.swift`:
  - `defaultThemeTokensMatchDesignSystem` — accent `#5C7A4F` etc. per `docs/designs/design-system.md`.

Implementation (green):
- `Sources/SudokuUI/Theme/Theme.swift` — protocol.
- `Sources/SudokuUI/Theme/DefaultTheme.swift` — tokens.

Acceptance:
- 1 test green.

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: Phase 1.

### 8.2 `AppRoute` enum + navigation

Tests to write first (red):
- `Tests/SudokuUITests/RouteTests.swift`:
  - All `AppRoute` cases `Hashable + Sendable`.
  - Deep-link round-trip from `CompletionView → LeaderboardView`.

Implementation (green):
- `Sources/SudokuUI/Navigation/AppRoute.swift` — verbatim from §How.5.2.
- Compact/regular split in `RootView`.

Acceptance:
- 2 tests green.

Skills to invoke: `swiftui-expert-skill`.

Depends on: 8.1.

### 8.3 `RootView` + auth `.task`

Tests to write first (red):
- Snapshot: `RootView` empty state (no resume), iPhone light + Mac light = 2 images.
- Behavior: `authenticate()` invoked exactly once on `.task` (Spy).

Implementation (green):
- `Sources/SudokuUI/Root/RootView.swift`, `RootViewModel.swift` (per §How.5.4).

Acceptance:
- 2 snapshots + 1 behavior test green.

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 8.2, Phase 7.1.

### 8.4 `HomeView` (4 mode cards, Liquid Glass)

Tests to write first (red):
- Snapshot: iPhone light + Mac light = 2.
- Behavior: tap mode card routes correctly.

Implementation (green):
- `Sources/SudokuUI/Home/HomeView.swift`, `HomeViewModel.swift` — uses `.glassEffect()`.

Acceptance:
- 2 snapshots green.

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 8.3.

### 8.5 `DailyHubView` (3 puzzle cards + completion checks + `.exhausted` alert)

Tests to write first (red):
- Snapshots (per §How.5.8): 3 — unfinished / completed Easy / all completed.
- Behavior: `GeneratorError.exhausted` → Alert per §How.6.3.

Implementation (green):
- `Sources/SudokuUI/Daily/DailyHubView.swift`, `DailyHubViewModel.swift`.

Acceptance:
- 3 snapshots + 1 behavior test green.

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 8.4, Phase 6.

### 8.6 `PracticeHubView` (difficulty picker + draw + shimmer >100ms)

Tests to write first (red):
- Snapshots (per §How.5.8): 3 — idle / drawing-shimmer / drawn.
- Behavior: shimmer appears when fetch latency > 100ms (FakeClock).

Implementation (green):
- `Sources/SudokuUI/Practice/PracticeHubView.swift`, `PracticeHubViewModel.swift`.

Acceptance:
- 3 snapshots + 1 behavior test green.

Skills to invoke: `swiftui-expert-skill`.

Depends on: 8.4, Phase 6.

### 8.7 `BoardView` (cells, digit pad, undo/redo, pencil, pause overlay, keyboard)

Tests to write first (red):
- Snapshots (per §How.5.8): **12** — iPhone/Mac × light/dark × {empty, in-progress with errors, just-before-complete}. Includes 1 ja + 1 ko + 1 zh-TW variant.
- Mac keyboard: `1`-`9` fills, `0`/`delete` clears, `p` toggles pencil, `⌘Z` undo, `⌘⇧Z` redo, arrow keys move focus.
- A11y dump: VoiceOver label per §How.5.7.

Implementation (green):
- `Sources/SudokuUI/Board/BoardView.swift`, `GameViewModel.swift` (per §How.5.4 listing).
- `BoardCellView`, `DigitPadView`, `PauseOverlayView`.
- `.focusable() + .onKeyPress()` for keyboard; `.keyboardShortcut()` for undo/redo.

Acceptance:
- 12 snapshots + 2 keyboard tests + 1 A11y test green.
- `BoardView` view inspection asserts `.glassEffect()` is **not** applied (§How.5.1).

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 8.4, Phase 3, Phase 5.

### 8.8 `CompletionView` (3 state variants)

Tests to write first (red):
- Snapshots (per §How.5.8): 3 — authenticated with leaderboard / unauthenticated CTA / leaderboard fetch failed. Includes 1 zh-TW hero variant.
- Behavior: deep link to `LeaderboardView` on tap.

Implementation (green):
- `Sources/SudokuUI/Completion/CompletionView.swift`, `CompletionViewModel.swift`.

Acceptance:
- 3 snapshots + 1 behavior test green.

Skills to invoke: `swiftui-expert-skill`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 8.7, Phase 7.5.

### 8.9 `LeaderboardView` (3 scopes + AX3+ vertical stack)

Tests to write first (red):
- Behavior: scope toggle changes data source; AX3+ Dynamic Type collapses to vertical stack.

Implementation (green):
- `Sources/SudokuUI/Leaderboard/LeaderboardView.swift`, `LeaderboardViewModel.swift`.

Acceptance:
- 2 behavior tests green.

Skills to invoke: `swiftui-expert-skill`.

Depends on: 8.4, Phase 7.5.

### 8.10 `SettingsView`

Tests to write first (red):
- Behavior: Generator v1 row displays current version; clear cache invokes Persistence.

Implementation (green):
- `Sources/SudokuUI/Settings/SettingsView.swift`, `SettingsViewModel.swift`.

Acceptance:
- 2 behavior tests green.

Skills to invoke: `swiftui-expert-skill`.

Depends on: 8.4, Phase 5, Phase 7.

### 8.11 Snapshot baseline lock (21 images)

Tests to write first (red):
- N/A (baseline acceptance is the artifact).

Implementation (green):
- Verify `__Snapshots__/` contains exactly 21 PNGs matching the §How.5.8 matrix.
- Commit images.

Acceptance:
- `git ls-files Sudoku/Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/ | wc -l` = 21.
- All `SudokuUITests` green on PR CI.

Skills to invoke: `swift-testing-baseline`.

Depends on: 8.3–8.10.

---

## Phase 9 — DI + Privacy + L10n

Wires the App target, ships PrivacyInfo, seeds the localization catalog.

### 9.1 `SudokuApp` entry + `AppComposition.live/preview/tests`

Tests to write first (red):
- `Tests/AppCompositionTests/CompositionTests.swift`:
  - `liveCompositionWiresAllProtocols`.
  - `previewCompositionUsesFakes`.
  - `testsCompositionUsesFakes`.

Implementation (green):
- `Sudoku/App/SudokuApp.swift` — per §How.1 listing.
- `Sudoku/App/AppComposition.swift` — three factory methods.
- `Sudoku/App/CompositionRoot/Live.swift`, `Preview.swift`, `Tests.swift` — wire concrete impls.

Acceptance:
- 3 tests green; App target compiles and launches in iPhone + Mac simulators.

Skills to invoke: `swiftpm-modularization`, `swift6-concurrency`.

Depends on: Phase 8.

### 9.2 GameCenter + CloudKit entitlements wiring

Tests to write first (red):
- N/A (entitlement verification is build-time).

Implementation (green):
- `Sudoku/App/Sudoku.entitlements` — finalized per 1.7 stub.
- `Info.plist` — `NSGameKitFriendListUsageDescription` 7-locale strings (placeholder for L10n step).

Acceptance:
- App launches on simulator; `GKLocalPlayer.local.isAuthenticated` returns a value (sandbox account in Phase 10).
- CloudKit container query in dev environment returns the user zone.

Skills to invoke: `apple-public-repo-security`.

Depends on: 9.1.

### 9.3 `PrivacyInfo.xcprivacy`

Tests to write first (red):
- `Tests/AppCompositionTests/PrivacyManifestTests.swift`:
  - `manifestPresent`.
  - `noThirdPartyTrackingDomains`.
  - `requiredReasonsAPIsDeclared` — `UserDefaults` (CA92.1) if used, file-timestamp APIs if used.

Implementation (green):
- `Sudoku/App/Resources/PrivacyInfo.xcprivacy` — per `foundations.md §6` (no IDFA, no PII, no third-party SDKs).

Acceptance:
- 3 tests green; manifest parses as valid plist.

Skills to invoke: `apple-public-repo-security`, `apple-three-piece-analytics`.

Depends on: 9.1.

### 9.4 `Localizable.xcstrings` seed (en + zh-TW)

Tests to write first (red):
- `Tests/SudokuUITests/L10nTests.swift`:
  - `allUserFacingStringsHaveEnAndZhTW` — scans `SudokuUI/` for `String(localized:)` calls, asserts catalog hit.

Implementation (green):
- `Sudoku/App/Resources/Localizable.xcstrings` — seeded with all keys, source = en, zh-TW filled.
- Error UI vocabulary keys per §How.6.9 (`error.<source>.<case>.{title|body|action}`).

Acceptance:
- 1 test green; catalog opens in Xcode 26.5 string catalog editor without warnings.

Skills to invoke: `ai-translated-localization`.

Depends on: Phase 8.

### 9.5 AI-translated 5-locale pass (ja / zh-CN / es / th / ko)

Tests to write first (red):
- `Tests/SudokuUITests/L10nCompletenessTests.swift`:
  - `all7LocalesPresent`.
  - `noUntranslatedMarkers` — no `<TRANSLATE>` literals in catalog.

Implementation (green):
- Run AI translation agent flow (per `ai-translated-localization` skill) for the 5 remaining locales.
- Manual review pass for SF Symbol placeholders and numeric format strings.

Acceptance:
- 2 tests green.
- Each locale spot-checked in `xcrun simctl spawn` with locale override.

Skills to invoke: `ai-translated-localization`.

Depends on: 9.4.

### 9.6 GC achievement / leaderboard names localized via ASC API

Tests to write first (red):
- N/A (ASC-side; manual verification).

Implementation (green):
- Script `Sudoku/ci_scripts/upload_gc_metadata.sh` — uses ASC API key (stored as Xcode Cloud secret) to upload localized names for 3 leaderboards × 7 locales = 21 strings + 8 achievements × 7 locales = 56 strings.
- Source strings sourced from `Localizable.xcstrings` via a small Swift tool.

Acceptance:
- App Store Connect → Game Center page shows all 77 localized entries.

Skills to invoke: `ai-translated-localization`, `xcode-cloud-single-track-ci`.

Depends on: 9.5.

---

## Phase 10 — Release

TestFlight, manual validation, App Store submission.

### 10.1 Internal TestFlight via Main CI

Tests to write first (red):
- N/A.

Implementation (green):
- Merge a release-candidate branch to `main`; Main CI uploads to TestFlight.
- Internal testers (developer + 1 secondary device with second iCloud account).

Acceptance:
- TestFlight build installable on iPhone 16 Pro + Mac arm64.
- App launches, completes a Practice puzzle, persists to iCloud, visible on second device.

Skills to invoke: `xcode-cloud-single-track-ci`.

Depends on: Phase 9 complete.

### 10.2 Game Center sandbox manual validation checklist

Tests to write first (red):
- N/A (manual checklist).

Implementation (green):
- Checklist file: `meetings/2026-06-XX_release-rehearsal.md`:
  - [ ] Sandbox `GKLocalPlayer` authenticates on iPhone.
  - [ ] Same on Mac.
  - [ ] Daily Easy first completion submits score.
  - [ ] Second completion of same `puzzleId` does **not** resubmit.
  - [ ] Cross-day completion does **not** submit (UTC manipulation via `Settings → Date & Time`).
  - [ ] `daily.streak_3` triggers after 3 calendar days of completions.
  - [ ] `daily.sweep` triggers when all 3 difficulties done same UTC day.
  - [ ] Friends-only leaderboard requires authorization prompt.
  - [ ] Unauthenticated state shows degraded UI per §How.3.4 table.

Acceptance:
- All 9 items checked green.

Skills to invoke: `apple-three-piece-analytics`.

Depends on: 10.1.

### 10.3 CloudKit development container validation checklist

Tests to write first (red):
- N/A.

Implementation (green):
- Checklist file: same as 10.2:
  - [ ] Custom zone `com.wei18.sudoku.userZone` provisioned on first launch.
  - [ ] `CKDatabaseSubscription` registered, silent push delivered after second-device write.
  - [ ] `SavedGame` round-trips across iPhone ↔ Mac.
  - [ ] `PersonalRecord` round-trips across devices.
  - [ ] Per-field LWW resolves a hand-crafted conflict (force two simultaneous writes).
  - [ ] iCloud sign-out: `iCloudSignedOutDuringSession` flow triggers Alert; local cache retained.
  - [ ] iCloud account change: wipe-on-confirm clears caches.
  - [ ] Quota exceeded simulation (manual CloudKit Dashboard fill): banner shown, game still playable.

Acceptance:
- All 8 items green; CloudKit dev container promoted to production via CloudKit Dashboard.

Skills to invoke: `apple-public-repo-security`.

Depends on: 10.1.

### 10.4 App Store metadata + screenshots

Tests to write first (red):
- N/A.

Implementation (green):
- 7-locale App Store metadata (title, subtitle, description, keywords, promotional text, what's new).
- Screenshot sets: iPhone 6.7" + 6.1" + iPad 12.9" + Mac — captured via Phase 8 snapshot infra (re-use `BoardView` snapshots tweaked for App Store dimensions).
- Privacy policy URL: hosted on GitHub Pages from `Sudoku-spec/` repo.

Acceptance:
- App Store Connect "Ready for Submission" checklist all green.

Skills to invoke: `ai-translated-localization`, `ui-ux-pro-max:ui-ux-pro-max`.

Depends on: 10.2, 10.3.

### 10.5 Production submission

Tests to write first (red):
- N/A.

Implementation (green):
- Tag `v1.0.0` on `main` → Xcode Cloud Release workflow uploads to App Store Connect.
- Manual submit for review.

Acceptance:
- Apple review approved; App live in 7 locale storefronts (US, TW, JP, CN, ES, TH, KR).

Skills to invoke: `xcode-cloud-single-track-ci`, `apple-public-repo-security`.

Depends on: 10.4.

---

## Appendix A — File path conventions

| Kind | Path |
|---|---|
| Production code | `Sudoku/Packages/SudokuKit/Sources/<Module>/` |
| Tests | `Sudoku/Packages/SudokuKit/Tests/<Module>Tests/` |
| Shared testing helpers | `Sudoku/Packages/SudokuKit/Sources/SudokuKitTesting/` |
| App target | `Sudoku/App/` (SudokuApp.swift, Assets.xcassets, Info.plist, Sudoku.entitlements, Resources/) |
| Localization | `Sudoku/App/Resources/Localizable.xcstrings` |
| Privacy manifest | `Sudoku/App/Resources/PrivacyInfo.xcprivacy` |
| CI scripts | `Sudoku/ci_scripts/` (`ci_post_clone.sh`, `ci_pre_xcodebuild.sh`, `upload_gc_metadata.sh`) |
| Tool versioning | `Sudoku/.mise.toml` |
| Pre-commit hooks | `Sudoku/lefthook.yml` |
| Gitleaks rules | `Sudoku/.gitleaks.toml` |
| Setup docs | `Sudoku/docs/setup.md` |
| Snapshot baselines | `Sudoku/Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/<TestSuite>/...` (committed) |
| Scratch (Phase 0 only) | `Sudoku/scratch/` (deleted at end of Phase 0) |
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
- `swift run --package-path Sudoku/scratch/SplitMix64Probe splitmix64-probe` matches hand-computed reference.
- `swift test --package-path Sudoku/scratch/GeneratorProbe --filter test_hardGenerator_p95_under500ms` → green.
- `meetings/2026-05-17_phase0-gates.md` exists and contains the App Store policy conclusion paragraph.

### Phase 1
- `bash Sudoku/ci_scripts/test_repo_hygiene.sh` → exit 0.
- `bash Sudoku/ci_scripts/test_mise_resolves.sh` → exit 0.
- `swift build --package-path Sudoku/Packages/SudokuKit` → clean (0 warnings).
- `xcodebuild -scheme Sudoku -destination "platform=iOS Simulator,name=iPhone 16 Pro" build` → clean.
- `xcodebuild -scheme Sudoku -destination "platform=macOS,arch=arm64" build` → clean.
- Xcode Cloud PR CI passes on a no-op PR.

### Phase 2
- `swift test --package-path Sudoku/Packages/SudokuKit --filter SudokuEngineTests` → green.
- Coverage of `SudokuEngine` ≥ 95% (manual `xcrun llvm-cov` check; not CI-enforced).
- 15 frozen `(seed, difficulty)` snapshots match exact strings.
- Re-measured Hard p95 < 500ms; recorded in `meetings/`.

### Phase 3
- `swift test --package-path Sudoku/Packages/SudokuKit --filter GameStateTests` → green.
- Coverage of `GameState` ≥ 90%.

### Phase 4
- `swift test --package-path Sudoku/Packages/SudokuKit --filter TelemetryTests` → green.
- Coverage of `Telemetry` ≥ 90%.

### Phase 5
- `swift test --package-path Sudoku/Packages/SudokuKit --filter PersistenceTests` → green.
- Coverage of `Persistence` ≥ 85%.
- No `import CloudKit` outside `Sources/Persistence/Live/`.

### Phase 6
- `swift test --package-path Sudoku/Packages/SudokuKit --filter PuzzleStoreTests` → green.
- Coverage of `PuzzleStore` ≥ 85%.

### Phase 7
- `swift test --package-path Sudoku/Packages/SudokuKit --filter GameCenterClientTests` → green.
- Coverage of `GameCenterClient` ≥ 80% (excluding `Live/`).
- No `import GameKit` outside `Sources/GameCenterClient/Live/`.

### Phase 8
- `swift test --package-path Sudoku/Packages/SudokuKit --filter SudokuUITests` → green.
- `git ls-files Sudoku/Packages/SudokuKit/Tests/SudokuUITests/__Snapshots__/ | wc -l` = 21.
- No `import CloudKit` / `import GameKit` anywhere in `Sources/SudokuUI/`.

### Phase 9
- `xcodebuild -scheme Sudoku -destination "generic/platform=iOS" archive` → green.
- `PrivacyInfo.xcprivacy` validates against Apple's privacy manifest checker.
- All 7 locales present in `Localizable.xcstrings`; 0 untranslated keys.
- App Store Connect Game Center: 21 leaderboard strings + 56 achievement strings present.

### Phase 10
- TestFlight build installs and runs on iPhone 16 Pro + Mac arm64.
- All 9 Game Center sandbox checklist items green.
- All 8 CloudKit dev container checklist items green.
- App Store Connect "Ready for Submission" green.
- `git tag v1.0.0` pushed; Xcode Cloud Release workflow succeeds.
- Apple review approved.
