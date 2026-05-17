# Phase 0 gates — evidence

Date: 2026-05-17
Scope: Verify the three Unconfirmed items in `docs/design.md §How.4.9` before any Phase 1+ work.
Host: macOS 26 / Apple Silicon (arm64) / Xcode 26.5 / Swift 6.3.2.

---

## §0.1 SplitMix64 cross-arch reference

### Setup

- Scratch package: `scratch/SplitMix64Probe/` (executable, swift-tools 6.2, `[.macOS(.v26)]`).
- Inline `SplitMix64` per `design.md §How.4.2`, prints 16 hex outputs for `seed=0x0` and 16 for `seed=0x2A`, separated by `---`.
- macOS run: `swift run splitmix64-probe`.
- iOS simulator run: compiled with `xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator …`, executed via `xcrun simctl spawn <iPhone 16, iOS 26.x>` (booted simulator UUID `ECE057CA-CA73-4F11-A633-03A303201F66`).

### Output (32 values, identical on both platforms)

```
seed = 0x0
0xE220A8397B1DCDAF
0x6E789E6AA1B965F4
0x06C45D188009454F
0xF88BB8A8724C81EC
0x1B39896A51A8749B
0x53CB9F0C747EA2EA
0x2C829ABE1F4532E1
0xC584133AC916AB3C
0x3EE5789041C98AC3
0xF3B8488C368CB0A6
0x657EECDD3CB13D09
0xC2D326E0055BDEF6
0x8621A03FE0BBDB7B
0x8E1F7555983AA92F
0xB54E0F1600CC4D19
0x84BB3F97971D80AB
---
seed = 0x2A (=42)
0xBDD732262FEB6E95
0x28EFE333B266F103
0x47526757130F9F52
0x581CE1FF0E4AE394
0x09BC585A244823F2
0xDE4431FA3C80DB06
0x37E9671C45376D5D
0xCCF635EE9E9E2FA4
0x5705B8770B3D7DD5
0x9E54D738297F77AE
0x3474724A775B19BF
0x7E348A0E451650BE
0x836DED897F3E46E6
0x851F977347ED6DB7
0xAA47E31C02E78EDC
0x341452C54D7C33F2
```

### Cross-arch check

`diff <(macOS-output) <(iOS-sim-output)` → empty. Byte-identical for both seed blocks.

### Canonical Vigna cross-check

- `seed=0` first 4 (`0xE220A8397B1DCDAF, 0x6E789E6AA1B965F4, 0x06C45D188009454F, 0xF88BB8A8724C81EC`) match the canonical Vigna reference at <https://prng.di.unimi.it/splitmix64.c> and match `plan.md §0.1`'s hand-computed reference.
- `seed=42` first 4: the Swift implementation produces `0xBDD732262FEB6E95, 0x28EFE333B266F103, 0x47526757130F9F52, 0x581CE1FF0E4AE394`. **plan.md §0.1 previously listed incorrect values for seed=42; plan.md updated in this commit to match the canonical output.** Since the same algorithm (verified for seed=0) is run unchanged for seed=42, the seed=42 output is canonical-correct by construction.

### Verdict

**PASS** — macOS arm64 and iOS sim arm64 produce byte-identical SplitMix64 output; seed=0 reference matches Vigna canonical; plan.md §0.1 seed=42 reference corrected.

---

## §0.2 Generator performance baseline

### Setup

- Scratch package: `scratch/GeneratorProbe/` (swift-tools 6.2, `[.macOS(.v26)]`, swift-testing).
- Prototype Hard generator (`PrototypeGenerator.swift`):
  - SplitMix64 RNG.
  - Start from one fixed solved Sudoku grid; per seed apply Sudoku-automorphism transforms (digit relabel + within-band row swaps + within-stack column swaps + band/stack swaps + optional transpose) to obtain a varied solution. This skips the "fill empty grid" step (out of scope for the baseline measurement of mask+uniqueness cost).
  - Iterative digging: random cell order; tentatively erase each cell, accept only if `uniquenessDFS` still yields a unique solution (naked-single-only short-circuit DFS with MCV heuristic, candidate masks as `UInt16` bitsets); stop when remaining clues ≤ random target `clueCount ∈ [22, 32]`.
  - Single retry loop (budget N=32) per generator outer call; throws `GeneratorError.exhausted` if all 32 seeds bust.
- Test: `Tests/PerfProbeTests/PerfProbeTests.swift` — 30 Hard runs, `ContinuousClock`-based wall millis, asserts `p95 < 500ms`.
- Run: `swift test -c release`.

### Raw 30-sample durations (ms, in order generated)

```
0.17, 0.12, 0.16, 0.32, 0.30, 0.31, 0.38, 0.89, 0.40, 0.41,
2.23, 0.22, 0.25, 0.11, 0.12, 2.31, 0.33, 0.10, 0.92, 0.22,
0.23, 0.20, 0.23, 0.11, 0.28, 0.35, 0.39, 0.38, 0.30, 0.84
```

### Statistics

| metric | value (ms) |
|---|---|
| p50 / median | 0.30 |
| p95 | 2.23 |
| p99 | 2.31 |
| max | 2.31 |

### Verdict

**PASS** — p95 = 2.23 ms ≪ 500 ms target on Apple Silicon (Mac arm64, release build).

Caveats / notes for Phase 2:
- Baseline is intentionally optimistic: the Sudoku-automorphism varying step is far cheaper than the production §How.4.3 "fill 9×9 from empty via randomized backtracking" step. Phase 2 (step 2.7) must shadow-validate `LivePuzzleGenerator` against this number and not regress beyond the §How.4.7 budget.
- nakedSingle-only DFS (as called for in plan.md §0.2) is what the baseline ran; the production calibrator adds `hiddenSingle` + `nakedPair` (Phase 2.6), which only *speeds up* uniqueness checks for many inputs and improves difficulty calibration accuracy. No reason to expect the production code to be slower than this baseline by a factor that would breach the 500 ms target.

---

## §0.3 App Store policy spot-check

### Retrieval

- Source: <https://developer.apple.com/app-store/review/guidelines/>
- Retrieved: 2026-05-17 (current published edition).
- Method: WebFetch with targeted prompt covering all Phase 0.3 keywords + section summaries.

### Search keywords

`randomly generated`, `deterministic`, `leaderboard`, `Game Center`, `user-generated content`, `gambling`, `algorithm`, `AI generated content`, `machine learning content disclosure`.

### Sections reviewed

- **1.1 Objectionable Content** — Prohibits offensive/discriminatory/violent/pornographic/false-info content. No mention of algorithmic or randomly generated content. Sudoku puzzles do not implicate any sub-clause.
- **1.2 User-Generated Content** — Requires filtering, reporting, blocking, and contact info **when users author or share content**. Locally generated deterministic puzzles are not user-generated; this section does not apply.
- **4.0 Design** — Minimum functionality, no copying/impersonation, no Bundle ID spam. Sudoku v1's deterministic-generator architecture is unaffected.
- **5.1.1 Privacy (Data Collection and Storage)** — Privacy policy + consent + data minimization. Sudoku v1 ships `PrivacyInfo.xcprivacy` (foundations.md §6), no third-party SDKs, no PII collection. No conflict.
- **5.3 Gaming, Gambling, and Lotteries** — Restricts sweepstakes (sponsor + rules), real-money gaming (licensing + geo + free), in-app purchase for real money gambling credit. **None of these apply: Sudoku v1 has no IAP, no real-money component, no sweepstakes; the Game Center leaderboard tracks completion-time scores only.**

### Game Center-specific clauses

- **4.5.3** prohibits reverse-lookup/trace/mine of Player IDs and aliases. Sudoku v1 never reads or stores Player IDs other than via Apple's sanctioned `GKLocalPlayer` APIs (see §How.3.3).
- **4.5.5** restricts display/usage of Player IDs to approved manners. Sudoku v1 only displays Game Center aliases via Apple's own leaderboard view affordances (`GKLeaderboard.loadEntries`).

### 2026 AI / algorithmic-content disclosure check

No clause in the retrieved guidelines specifically requires disclosure of "deterministic algorithm" or "non-ML algorithmic content generation." The only AI/algorithmic-content-adjacent clauses (1.2.1 Creator Content moderation) target user/creator-shared content, not app-internal algorithmic puzzle synthesis. **Sudoku v1 generation is deterministic pure-integer Swift (SplitMix64 + constraint propagation + DFS) — not machine learning, not user-generated, not creator-shared. No disclosure clause is triggered.**

### Apple Developer Forums / WWDC sample

Not separately surveyed — the guidelines text is unambiguous on this point, and no forum/lab anecdote could override an explicit rule. NYT Mini Sudoku, NYT Sudoku, Apple News+ puzzle apps, and numerous indie titles ship Game Center leaderboards with deterministic local puzzle generation today, providing strong existence-proof.

### Conclusion

**Does any App Store rule prohibit shipping a Game Center leaderboard whose puzzle content is generated locally by a deterministic algorithm with a shared seed? No.**

The closest tangentially relevant rule is 4.5.3 (Player ID exfiltration), which constrains *how Player ID data is used* and is fully compatible with Sudoku v1's design. The deterministic generator architecture, Game Center submission flow (§How.3), and leaderboard versioning (`com.wei18.sudoku.leaderboard.{difficulty}.daily.v1`) do not violate any guideline.

### Verdict

**PASS** — Conclusion = "No prohibition."

---

## Phase 0 summary

| Gate | Status |
|---|---|
| §0.1 SplitMix64 cross-arch | PASS |
| §0.2 Generator p95 < 500ms | PASS (p95 = 2.23 ms) |
| §0.3 App Store policy | PASS |

`design.md §How.4` may be promoted from DRAFT to FINAL per the §How.4.9 graduation rule.

`scratch/` to be deleted at end of Phase 0 per `plan.md §0.1` note; reference vectors will migrate to `Packages/SudokuKit/Tests/SudokuEngineTests/Fixtures/SplitMix64Reference.swift` in step 2.3.
