# 2026-06-03 — Follow-up sweep + docs/config CR audit

Post-hoc meeting log. New session continuing the 2026-06-03 AdMob secret-injection
+ MS monetization work. Two phases: (1) clearing the four follow-up issues that
PR #265 / #259 CRs spawned, (2) two read-only Code Reviewer audits (docs currency,
config redundancy) and acting on their findings.

Roles: Leader (this session) + dispatched Developer / Code Reviewer subagents.

---

## Phase 1 — Follow-up issue sweep (#266 / #267 / #260 / #262)

Four issues closed, four PRs merged. Two were genuine work (Developer-dispatched),
two collapsed to doc/comment corrections once investigated (Leader inline).

| Issue | PR | What | Path |
|-------|----|------|------|
| #266 | #268 | Scrub residual production AdMob IDs from `docs/` + `meetings/` → memory-file references | Developer + Leader review |
| #267 | #269 | Document accepted `AppInfo.plist` drift tradeoff (option c) in `InfoPlistAdMobKeysTests` | Leader inline |
| #260 | #270 | Correct stale "pending U15" toast-wire comments | Leader inline |
| #262 | #271 | Add behavioral test proving `MonetizationStateController` reads the MS productId | Developer + Leader self-verify |

### Decisions / discoveries

- **#266 under-counted by the issue author.** Subagent found line 13 of
  `2026-05-25_v2.5.2-admob-banner-wiring.impl-notes.md` carried a *full literal
  production banner unit id* (issue described it only as "banner unit id"), and
  line 77 was a raw numeric app-id inside an `rg` isolation-audit example (not a
  `ca-app-pub-` string). Both scrubbed. Google universal **test** IDs
  (`3940256099942544`) left intact. History retains pre-scrub values — force-push
  not permitted per repo convention; HEAD scrub stops reinforcement.
- **#260 was already done.** Investigation showed the toastOverlay wire shipped in
  PR #263 (U15): `composition.rootView` → `MinesweeperRoot(routeFactory:, toastController:)`
  → `.toastOverlay(...)`, and `MinesweeperApp` renders `composition.rootView`.
  No feature work remained — only two stale comments still said "pending U15".
  **Rejected** writing duplicate wiring code; downgraded to a comment fix.
- **#267 resolved as a decision, not code.** Accepted option (c): the smoke test
  only guards the two AdMob keys (not plausibly deleted by accident), so the
  verbatim-copy drift risk is acceptable. Escalate to a byte-for-byte sync
  sentinel (option d) only on a real drift incident. Documented at the code site.
- **#262 negative control.** The new test seeds the preview `FakeIAPClient` with a
  `minesweeperRemoveAdsProductId` product priced `$4.99` (≠ the `$2.99`
  empty-catalog fallback); had the composition wired Sudoku's productId, the
  lookup would miss and fall back, failing the assertion. Leader re-ran
  `swift test --filter MinesweeperAppCompositionTests` → 7 tests pass (did not
  rely on the subagent's report alone).

---

## Phase 2 — Two Code Reviewer audits (docs currency, config redundancy)

Dispatched two read-only Code Reviewers in parallel (non-overlapping domains).

### Docs CR — `docs/` currency + redundancy

Verdict: docs healthy **except** `docs/v2/v2.5-readiness.md`, which lagged two
shipped changes (High severity — App-Review-facing).

Acted on via **PR #273**:
- §v2.5.3 still instructed editing `App/Info.plist` + a `LiveAdMobBridge.swift`
  Release `fatalError` branch that #265 deleted. Rewritten to the single-edit
  xcconfig flip (`Tuist/AdMob.xcconfig`) + runtime-guard verification step.
- Residual "7-day grace" assumptions (#256 zeroed `gracePeriodDays`) removed,
  including the **App-Reviewer test path** that said "wait 7 days OR adjust
  device clock". Now: banner appears from first launch.
- Added `docs/foundations.md` §7.7.1 documenting the xcconfig + Info.plist `$()`
  build-time injection pattern (cross-refs skill `build-time-secret-injection`).

CR confirmed `meetings/` (124 files) is an append-only archive — out of scope for
"dead weight"; design/v1 docs are correctly v1-scoped, not contradictions.

### Config CR — build/config redundancy

Verdict: config surface is genuinely DRY. Two notable outcomes:

- **Corrected a Leader misjudgement.** Leader suspected duplicate `ci_post_clone.sh`
  (root + `ci_scripts/`). CR verified via `git ls-files`: no root copy exists —
  only `ci_scripts/ci_post_clone.sh` is tracked (exactly where Xcode Cloud looks).
  No duplication, no drift. Package.swift surface is DRY (GameShellKit extraction
  is real — MS consumes `GameShellUI`, not copy-pasted Sudoku code).
- **TelemetryKit `swiftLanguageModes`** (PR #272): it was the only one of 9
  manifests omitting `swiftLanguageModes: [.v6]`. Added for consistency; build
  verified.
- **`.gitignore` line 9 `!.env.example` — finding declined.** CR flagged it as
  dead weight (guards a nonexistent root `.env.example`). Leader removed it, then
  an isolated `git check-ignore` test showed line 9 is genuinely inert for
  `secrets/.env.example` (governed by line 14 `!secrets/*.example` either way) —
  so the CR was technically right it changes nothing today. **But** it's a 1-line
  defensive un-ignore on a security-adjacent file with negligible removal value
  and asymmetric downside if convention changes. Reverted the removal; kept line 9.

---

## Net result

- Issues closed: #266, #267, #260, #262.
- PRs merged: #268, #269, #270, #271 (Phase 1); #272, #273 (Phase 2 CR fixes).
- AdMob secret-injection security loop now complete across source / Info.plist /
  docs / meetings (#264 → #265 → #266).
- `v2.5-readiness.md` is submission-accurate again (no obsolete flip steps, no
  grace residue in the App-Review path).

## Open / deferred

- Config CR Low findings left as-is: `ci_pre_xcodebuild.sh` empty stub (documented
  reserved hook), `.swiftpm/` gitignore line (harmless).
- `.gitignore` line 9 kept by decision (above) — not a backlog item.
