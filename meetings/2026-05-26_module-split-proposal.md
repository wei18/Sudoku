# Proposal — Module Split: Telemetry / GameCenterClient / Persistence → Independent SwiftPM Packages

Date: 2026-05-26
Author: Senior Developer (subagent)
Status: PROPOSAL — no implementation
Trigger source: `docs/foundations.md §Backlog` entry dated 2026-05-23
Verdict (TL;DR): **Defer the full 3-way split. Optionally extract `Telemetry` only as a low-cost, high-clarity standalone (decision deferred to Leader/User).**

---

## 1. Current state

`Packages/SudokuKit/` is a 9-target monolithic SwiftPM package. The three subjects of this proposal live as sibling targets inside it:

| Target | Files | LOC | Apple-framework imports | Internal deps |
|---|---:|---:|---|---|
| `Telemetry` | 11 | 734 | `Foundation`, `os` (internal), `MetricKit` | `GameState`, `SudokuEngine` |
| `GameCenterClient` | 11 | 1,187 | `Foundation`, `GameKit`, `UIKit` | `SudokuEngine`, `Telemetry`, `Persistence` |
| `Persistence` | 13 | 1,580 | `Foundation`, `CloudKit` (internal) | `GameState`, `SudokuEngine`, `Telemetry`, `MonetizationCore` (cross-pkg) |

Total: 35 files / 3,501 LOC across the three modules. They make up ~30% of the package by file count.

### Direct consumers (in-package)

- `Telemetry` is imported by: `GameCenterClient`, `Persistence`, `PuzzleStore`, `SudokuUI`, `AppComposition`, `SudokuKitTesting`, and 7 test targets.
- `GameCenterClient` is imported by: `SudokuUI` (a single ViewModel + the RouteFactory), `AppComposition`, `SudokuKitTesting`.
- `Persistence` is imported by: `GameCenterClient`, `SudokuUI`, `AppComposition`, `SudokuKitTesting`, `PuzzleStore` (indirectly via `Telemetry`-shared types).

### Dependency-direction observations

1. **Telemetry is a true leaf-ish module** (only depends on `GameState` + `SudokuEngine`, both pure-value packages with no IO). Everything else imports Telemetry; Telemetry imports nothing IO-bound.
2. **GameCenterClient imports Persistence** (for `LiveGameCenterClient`'s leaderboard ID source — promoted by #128 / M6 last week). This means a clean split would require Persistence to move first or simultaneously.
3. **Persistence imports `MonetizationCore` from the sibling `AppMonetizationKit` package.** Cross-package import already works; this is precedent that the workspace tolerates extraction.

---

## 2. Proposed split (the maximal version on the backlog)

Three new packages siblings of `SudokuKit/` and `AppMonetizationKit/`:

### 2.1 `Packages/TelemetryKit/`
- Targets: `Telemetry` (renamed `TelemetryCore`?), `TelemetryTesting` (extract `FakeLogger` + `RecordingSink` from `SudokuKitTesting`)
- Public API surface: `TelemetryEvent`, `TelemetrySink`, `Telemetry` facade, `OSLogSink`, `NoOpTrackingSink`, `MetricKitSink`, `GameStateTelemetryAdapter`, `UserFacingError`, `ErrorReporter`
- Cross-platform: yes (no UIKit/AppKit)
- Downstream: `SudokuKit`, `AppMonetizationKit` (does NOT currently depend; would gain optional dep if we want monetization events to flow through Telemetry)
- Dep on `GameState`/`SudokuEngine`: **breaks** if those stay inside `SudokuKit`. Either (a) Telemetry stops depending on them (would need to genericize `TelemetryEvent` payloads — major API churn), (b) `GameState` + `SudokuEngine` also extract to a foundational `SudokuCoreKit/`, (c) accept the cross-pkg dep `TelemetryKit → SudokuKit/{GameState,SudokuEngine}` (circular: SudokuKit also depends on TelemetryKit). **(c) is impossible; (b) is the only clean answer.** This balloons the split scope.

### 2.2 `Packages/GameCenterKit/`
- Targets: `GameCenterClient`, `GameCenterTesting`
- Public API: `GameCenterClient` protocol, `LiveGameCenterClient`, `AuthDriver`, `GameCenterSink`, `AchievementEvaluator`, ID types
- Platform: **iOS-only `.iOS(.v26)`** (GameKit available on macOS but our UIKit imports + push-auth surface are iOS-shaped). Would need `#if canImport(UIKit)` guards or a `.macOS` conditional dep — non-trivial.
- Downstream: `SudokuKit` (only)
- Apple-framework cost: GameKit + UIKit link-time
- Test surface: `GameCenterClientTests` (9 test files) moves with it

### 2.3 `Packages/PersistenceKit/`
- Targets: `Persistence`, `PersistenceTesting`
- Public API: `Persistence` protocol, `LivePersistence` (actor, post #126), `LivePrivateCKGateway`, `MonetizationStateStore`, `LiveMonetizationStateStore`, `ConflictResolver`, `SavedGameMapper`, zone provisioning
- Platform: cross-platform (CloudKit available on both)
- Downstream: `SudokuKit`, `GameCenterKit` (if both extract)
- Cross-pkg dep: `MonetizationCore` from `AppMonetizationKit` (already cross-pkg, unchanged)

### 2.4 Net package count
- Before: 2 packages (`SudokuKit`, `AppMonetizationKit`)
- After full split: 5 packages (`SudokuCoreKit`, `TelemetryKit`, `GameCenterKit`, `PersistenceKit`, `SudokuKit` [now only `PuzzleStore` + `SudokuUI` + `AppComposition` + `SudokuKitTesting` + `ASCRegister`], `AppMonetizationKit`)
- = **5 packages** if we accept that `GameState` + `SudokuEngine` must also extract (see §2.1 cost).

---

## 3. Migration order (proposed)

Each step is a single PR; main stays green between steps.

1. **PR 1 — Extract `SudokuCoreKit/`** containing `SudokuEngine` + `GameState`. Pure-value, no IO, no Apple framework imports. **Pre-requisite** for any of Telemetry / GameCenter / Persistence to extract (they all import these). Risk: low — pure deletion + path move + Package.swift authoring. ~1,700 LOC moved.
2. **PR 2 — Extract `TelemetryKit/`** (consumes `SudokuCoreKit`). Public-API breaking change: zero (re-export). Downstream `SudokuKit` Package.swift gains `.package(path: "../TelemetryKit")` dep on every target that imports Telemetry (which is most of them).
3. **PR 3 — Extract `PersistenceKit/`** (consumes `SudokuCoreKit` + `TelemetryKit` + cross-pkg `AppMonetizationKit/MonetizationCore`). 13 files + 11 test files.
4. **PR 4 — Extract `GameCenterKit/`** (consumes `SudokuCoreKit` + `TelemetryKit` + `PersistenceKit`). iOS-only platform handling required.
5. **PR 5 — Tuist `Project.swift` regen** to reflect the new package set; verify Xcode Cloud `ci_post_clone.sh` still resolves all deps; snapshot test paths verified.

Each step ships an independent PR with green CI. Estimated calendar effort: 1 dispatch per PR ≈ 5 subagent runs.

---

## 4. Risk / cost analysis

### 4.1 Build-time cost
- SwiftPM resolves each `Package.swift` independently. 5 packages vs 2 means more `.build/` directories, more incremental cache fragmentation.
- Initial clean build: **probably faster** (smaller per-package parallelism boundaries).
- Incremental build after touching one file in `Telemetry`: **probably faster** (fewer downstream targets need re-typecheck because the package boundary blocks whole-module recompilation of consumers).
- Net: **mild positive on build time**, but not measured. The backlog trigger says "compilation noticeably slow" — current build is not slow today.

### 4.2 Tuist regen cost
- `Project.swift` references `Packages/SudokuKit` as a local SwiftPM dep. Adding 3 more local deps is mechanical (5 lines per package in `Project.swift`).
- Tuist `generate` time impact: negligible (it's already resolving the SudokuKit graph).

### 4.3 Xcode Cloud cost
- `ci_post_clone.sh` runs `mise install` then SwiftPM resolves transitively. New packages auto-discovered.
- ci_post_xcodebuild.sh / archive workflows: unaffected.
- Total CI minute cost: **+5-10s per build** for additional SwiftPM resolution. Trivial.

### 4.4 Test cost
- Each new package gets its own `swift test` command. Tests run independently — minor reduction in cross-target test interference.
- Snapshot baselines (`__Snapshots__/`) currently sit in `Tests/SudokuUITests/__Snapshots__/`. Unaffected by the split (only Telemetry/GameCenter/Persistence tests move, and they don't use snapshot testing).

### 4.5 impl-notes / `meetings/` paths
- No file relocation needed. Meeting log conventions unaffected.

### 4.6 Snapshot baseline paths
- `pointfreeco/swift-snapshot-testing` resolves baselines via `#filePath`. Moving a test file moves the baseline lookup path. Affected files: NONE — none of the moved test files are snapshot tests.

### 4.7 Reverse dependency: PrivacyInfo.xcprivacy
- Privacy manifest lives in `App/Resources/`. Currently scoped to the App's link-time deps. Extracting GameCenter/Persistence does not change which Apple APIs are linked → no manifest changes.

### 4.8 Risk: hidden cyclic dependencies
- **Telemetry depends on `GameState` + `SudokuEngine`** for typed payloads (`Mode`, `Difficulty` enums). Per §2.1 this forces `SudokuCoreKit/` extraction first, otherwise a cycle.
- **GameCenterClient depends on `Persistence`** (added by #128). Forces extraction in the order Persistence-then-GameCenter, not concurrent.
- No other unexpected cycles found in grep.

### 4.9 Cost summary
- Concrete cost: ~5 PRs of mechanical refactoring + Package.swift authoring.
- Estimated total LOC churn: ~4,000 LOC moved across PRs (mostly imports + Package.swift, not logic).
- Per-PR review effort: medium (mechanical but cross-cutting). Code Reviewer required per methodology §8.

---

## 5. Triggers re-affirmed

The backlog entry's stated trigger: **"second app wants to reuse any target / OR `SudokuKit` compile time noticeably slow"**.

As of 2026-05-26:
- **No second app exists.** v2 ships in days; no v3 product on roadmap.
- **`SudokuKit` compile is not slow.** swift build clean ≈ 12s; incremental ≈ 1-2s.
- AdMob's `AppMonetizationKit` extraction precedent worked, BUT it was justified by third-party SDK isolation (foundations §9.1) — a hard architectural constraint, not a convenience.
- No collaborator or open-source consumer has asked for Telemetry-as-library.

Conclusion: **the documented trigger is not met.**

### User opt-out reasons that would invalidate the split
- "We're not building a 2nd app, ever" → defer indefinitely
- "Tuist regen overhead more painful than build-time win" → defer
- "We'd rather invest the dispatch budget in feature work / v2 polish" → defer
- "swiftformat / lefthook / mise toolchain churn is enough YAK to chew this cycle" → defer

---

## 6. Recommendation

### Primary recommendation: **DEFER full split**
The trigger is not met. No demonstrated pain. v2 ship is days away — opportunity cost of 5 dispatches on a no-pain refactor is high. Re-evaluate when:
- A second app product enters scope, OR
- Clean swift build of SudokuKit exceeds 30s consistently, OR
- An external collaborator/consumer requests TelemetryKit as a public library.

### Optional secondary: **Telemetry-only extraction (LOW-cost win)**
If Leader/User want some forward motion, extract **only** `TelemetryKit/` *after* first extracting `SudokuCoreKit/` (the prerequisite per §2.1).

Why Telemetry uniquely qualifies:
- Pure values + protocol; zero IO-bound or Apple-platform-restricted code (no GameKit, no CloudKit, no UIKit).
- Independent reuse story is plausible (it's the closest thing in this codebase to a "library").
- Smallest of the three (734 LOC vs 1,187 / 1,580).
- Once extracted, `TelemetryKit` becomes a candidate to be open-sourced separately if the user ever wants to demonstrate the `telemetry-facade-pattern` skill as a real artifact.

Cost: 2 PRs (`SudokuCoreKit` + `TelemetryKit`) instead of 5. ~6-8h of dispatch + review across 2 sessions.

### Rejected: middle ground (extract GameCenter or Persistence only)
- GameCenterClient is iOS-only and tightly bound to Apple's leaderboard ID surface — no reuse value outside this app.
- Persistence is CloudKit-bound and entangled with `MonetizationCore`'s state store; the cross-pkg dep already exists, extracting won't add clarity.
- Neither has the "library-quality" character that Telemetry has.

### Adjust the split shape?
- Yes: drop GameCenterKit/PersistenceKit from the plan permanently. Keep only TelemetryKit as a documented optional. Update `docs/foundations.md §Backlog` to reflect the narrower scope.

---

## 7. Decision matrix

| Option | Effort | Risk | Pay-off today | Pay-off if 2nd app | Recommend |
|---|---|---|---|---|---|
| A. Full 3-way split (as backlog) | 5 PRs | Medium | None measured | High | **No (defer)** |
| B. Telemetry-only extraction | 2 PRs | Low | Minor build-time win + cleaner deps | Medium | **Optional** |
| C. Defer entirely | 0 PRs | None | n/a | n/a | **Yes (primary)** |
| D. Cancel from backlog | 0 PRs | None | Reclaim cognitive overhead of an open backlog item | n/a | Consider with C |

---

## 8. Open questions for Leader/User

1. Is there a v3 product idea (sibling app / watchOS / iPad-Pro variant) that would consume Telemetry independently? If yes, B becomes more attractive.
2. Is "TelemetryKit as open-source artifact" a goal? If yes, B becomes a goal in its own right.
3. Should the backlog entry be narrowed to "Telemetry-only optional extraction" or removed entirely?

---

## 9. References

- `docs/foundations.md §Backlog` entry 2026-05-23 (source of this proposal)
- `docs/foundations.md §6, §7` (Telemetry architecture, public-repo posture)
- `docs/methodology.md §8` (Code Reviewer threshold — would apply to every split PR since they all touch `Package.swift`)
- Precedent: `AppMonetizationKit/` extraction (v2.3.2) — justified by third-party SDK isolation, not generic modularization
- Recent renames affecting scope: #128 (GameCenter IDs unified), #126 (LivePersistence actor), #129 (typed Mode enum)
