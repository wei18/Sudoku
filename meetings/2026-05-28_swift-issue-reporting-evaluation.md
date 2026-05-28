# Evaluation — `pointfreeco/swift-issue-reporting`

**Date**: 2026-05-28
**Issue**: [#178](https://github.com/wei18/Sudoku/issues/178)
**Verdict**: **DEFER** (re-evaluate on triggers below)
**Decision owner**: Leader
**Branch**: `eval/178-swift-issue-reporting`

---

## TL;DR

`swift-issue-reporting` is a high-quality, MIT-licensed, zero-dependency Point-Free library that unifies runtime invariant reporting across Production / Preview / Test. The technical fit is good and §9 break-glass cost is near-zero. **However**, the current Sudoku codebase has only **3 production invariant sites**, of which **2 are intentional load-bearing `fatalError` rails** that the library would functionally weaken, and **1 is a DEBUG-only `assertionFailure`** that already does what we want. The cost (new dep, new mental model, training surface for every future contributor) does not yet pay for itself. Defer until a documented trigger fires.

---

## 1. Repo verification (gh API)

| Field | Value |
|---|---|
| License | MIT (Copyright 2021 Point-Free, Inc.) |
| Language | 100% Swift, pure source SPM |
| Stars / forks | 510 / 101 |
| Last push | 2026-05-12 (actively maintained) |
| Default branch | `main` |
| Open issues | 4 |
| Third-party deps | **None** (pure stdlib + Swift Testing / XCTest weak link) |
| Privacy manifest impact | Zero — no networking, no PII collection, no system framework that requires API-reason declaration |
| Origin | Evolution of `xctest-dynamic-overlay`; **SPM URL must still point to `https://github.com/pointfreeco/xctest-dynamic-overlay`** for compat (per README "Important" callout) |

Used in production by `swift-dependencies`, `swift-composable-architecture`, `swift-navigation`, `swift-perception`, `swift-custom-dump`, `swift-clocks` — established Point-Free ecosystem standard.

Swift 6 strict concurrency: per README the library targets the same Swift versions as TCA / swift-navigation, both of which currently ship with Swift 6 strict concurrency clean. Verification gate would need actual `Package.resolved` integration to confirm, but no concurrency footguns expected (the API surface is essentially `reportIssue(_:)` and `withExpectedIssue { … }`).

---

## 2. Current invariant-reporting site survey

Command:
```
grep -rn "fatalError\|assertionFailure\|preconditionFailure" Packages/*/Sources
grep -rn "Issue.record" Packages/*/Tests
```

### Production sites (3 total)

| File:Line | Kind | Classification | Would lib help? |
|---|---|---|---|
| `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift:36` | `fatalError("REPLACE_IN_v2.5.3: production AdMob banner ad unit ID not wired …")` | **Intentional load-bearing rail**. Comment lines 32-34 explicitly call out: *"The `fatalError` is intentional — any Release build that reaches this site before the v2.5.3 swap fails loudly at first ad load rather than silently serving an empty/test placeholder."* | **No / harmful.** `reportIssue` defaults to a non-fatal purple warning in Release; we'd need to configure it to `fatal` here, which is exactly what `fatalError` already does in one line with zero indirection. |
| `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift:32` (comment ref) | Same site as above | Same | Same |
| `Packages/SudokuKit/Sources/SudokuUI/Board/GameViewModel.swift:184` | `assertionFailure("preview fixture wiring bug: \(error)")` | **DEBUG-only preview-path guard**. Comment: *"An invalid coord here is a programmer error in fixture wiring, never a runtime user path — make it loud in DEBUG."* | **Marginal.** `assertionFailure` already fires in DEBUG and no-ops in Release; semantics are exactly what `reportIssue` provides minus the Preview purple-warning and the test-failure integration. Since this path is *never reached* in a real ViewModel test (it's the preview-only branch), the test-failure integration adds zero coverage. |

### Test sites (991 occurrences)

Already on swift-testing (`#expect`, `Issue.record`) across `SudokuKit`, `SudokuCoreKit`, `AppMonetizationKit`, `GameCenterKit`, `PersistenceKit`, `TelemetryKit`. No `XCTFail` legacy. The library would **not** replace any of these (it complements, not replaces, `Issue.record` — both feed into the same test-failure pipeline).

### What is NOT in the codebase

- Zero `preconditionFailure`
- Zero `XCTFail`
- Zero `fatalError("unreachable")` / `fatalError("TODO")` style placeholders
- Zero `#warning` / `#error` invariant markers
- Zero split-brain "test-version vs prod-version of the same invariant" patterns

---

## 3. Trigger condition check (from issue #178)

### (a) "Passed test but prod crashed" incident?

**No.** Reviewed `meetings/` for RCA logs:

- `meetings/2026-05-25_swift-test-hang-rca.md` — root cause was a leaked `for await` Task in `MonetizationStateController.bootstrap()`; orthogonal to invariant reporting.
- `meetings/2026-05-25_rca-fix-b.impl-notes.md` — follow-up fix for the same issue.
- `meetings/2026-05-25_issue-67-error-funnel.impl-notes.md` — error funnel cleanup, not invariant-related.

No documented incident where a test passed and production hit an invariant violation. Trigger (a) **not met**.

### (b) Invariant source-of-truth split across Production / Preview / Test?

**No.** Survey above shows 3 sites total, each scoped to exactly one of {Production, Preview-only}. The `LiveAdMobBridge` site is deliberately a Release-only rail (DEBUG branch defines a constant test ad unit ID, so `fatalError` cannot fire in DEBUG). The `GameViewModel` site is deliberately Preview/DEBUG-only. There is no invariant that exists in all three contexts simultaneously. Trigger (b) **not met**.

### (c) Would adopting unify `LiveAdMobBridge` `fatalError` + `GameViewModel` `assertionFailure`?

**Technically yes, behaviourally no.** Both could be rewritten as `reportIssue(...)`, but:

- The AdMob site **requires** Release-fatal behaviour (it's the paired-flip safety net for v2.5.3 ad-unit-ID swap; see `docs/v2/v2.5-readiness.md §v2.5.3`). Configuring `reportIssue` to Release-fatal recreates `fatalError` semantics with extra indirection.
- The GameViewModel site is on a path that **no test exercises** (preview-only fixture), so the test-failure integration adds zero detection value.
- "Unification" here means 2 call sites with different desired Release semantics under one API, which is a net cognitive-load increase, not decrease.

---

## 4. Comparison vs current state

| Aspect | Current | With swift-issue-reporting |
|---|---|---|
| Production invariant escape hatch | `fatalError` (1-liner, zero deps) | `reportIssue` configured to `fatal` (1 line + 1 reporter config + 1 SPM dep) |
| DEBUG-only programmer-error guard | `assertionFailure` (1-liner, stdlib) | `reportIssue` (1 line + 1 SPM dep) |
| Preview-time visibility | Print to console / `assertionFailure` crash on DEBUG | Purple Xcode runtime warning (nicer) |
| Test integration | Direct `Issue.record` in tests | `reportIssue` auto-records test failure (only relevant if production code is exercised in tests) |
| New mental model | None | Every contributor learns when to use `reportIssue` vs `fatalError` vs `assertionFailure` vs `Issue.record` |
| §9 break-glass cost | N/A | One §9.X subsection in `docs/foundations.md`, isolation contract (probably testable everywhere), MIT-license acknowledgment via LicensePlist |
| Binary size impact | 0 | Negligible (pure Swift, small surface) |

**Net delta**: One nicer Preview-warning UX, zero new bug-detection coverage, +1 dep, +1 mental model.

---

## 5. §9 Break-glass prerequisite checklist

| Item | Status | Note |
|---|---|---|
| Apple-only alternative exists? | **Verified ✓** | `fatalError` / `assertionFailure` / `Issue.record` already cover current needs |
| License compatible (permissive) | **Verified ✓** | MIT |
| Privacy manifest delta | **Verified ✓** | Zero — no network, no PII, no API-reason-required syscalls |
| Binary size impact | **Verified ✓** | Negligible |
| Isolation strategy | **Verified ✓** | No isolation needed — logging-style lib, can be imported by any target (this is *not* an SDK in §9.1 sense) |
| Swift 6 strict concurrency | **Unconfirmed ?** | Library is Sendable-clean per maintainer claims; would need actual integration to verify against our `swift6-concurrency` skill defaults |
| Justification: why no Apple-only alt? | **Fails** | Apple-only stack covers all 3 current call sites adequately |

**Gate result**: §9 isolation/cost gates pass, but the "no Apple-only alternative" gate **fails** — Apple-only primitives already serve our 3 sites without split-brain.

---

## 6. Decision: **DEFER**

### Re-evaluation triggers

Re-open #178 when **any** of the following occurs:

1. **Production invariant site count grows past ~10**, especially if any site is *exercised by both tests and production* (i.e., true split-brain emerges).
2. **First "passed test but prod crashed" RCA** lands in `meetings/`.
3. **Adoption of `swift-dependencies` or `swift-composable-architecture`** — both transitively depend on `swift-issue-reporting`, so the cost amortizes to zero and adoption becomes a no-op consolidation. (TCA adoption is currently not on the roadmap; if it lands, this evaluation must be redone.)
4. **Migration of any ViewModel guard to a path that *is* exercised by tests** — at that point the test-failure integration starts paying for itself.

### Why not REJECT

The library is genuinely well-designed and the §9 cost is low. Rejecting permanently would over-commit; deferring keeps the door open without paying the integration cost today. Karpathy guideline §2 (Simplicity First): "No abstractions for single-use code."

### Why not ADOPT now

Per §1 of Karpathy guidelines and Leader review criteria (Completeness): adopting a 4th invariant-reporting primitive for 3 call sites violates Surgical Changes and adds no detection coverage. The library shines at ~10+ sites with a healthy mix of test/preview/prod overlap; we are at 3, all non-overlapping.

---

## 7. Follow-up actions

- [x] Comment verdict on #178
- [x] Add `evaluated` label to #178 (do NOT close — keep open per backlog convention)
- [ ] User: confirm `evaluated` label exists in repo; if not, Leader will create it
- [ ] No follow-up implementation issue filed (DEFER path)
- [ ] Reassess on any trigger in §6
