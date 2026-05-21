# Spec Drift Audit — 2026-05-21

Status: COMPLETE
Scope: `docs/design.md` (v1), `docs/foundations.md`, `docs/v2/design.md`, `docs/v2/plan.md`, `docs/methodology.md`, `docs/privacy-policy.md`, plus cross-check against `Packages/AppMonetizationKit/Package.swift` (read-only).

---

## Verdict

**Yellow** — no blocking factual contradictions between v1 and v2 corpora (v1 claims are correctly scoped to "v1"; v2 break-glass is properly registered in `foundations.md §9`). However there is a cluster of **section-number drift** inside `docs/v2/design.md` itself: the v2 doc was authored before `foundations.md` settled on `§9` as the break-glass section number, and the v2 doc still references the old `§3` / `§3.1` numbering in three places. Additionally one privacy-policy claim (UMP-then-ATT ordering) does not exactly match the v2 design's "UMP → ATT → AdMob init" boot sequence wording. None of these affect shipped code; all are pre-v2-ship doc fixes.

---

## Findings (severity-ranked)

### S1 (must fix before v2 ship)

**S1-1. `docs/v2/design.md §How.9` self-references the wrong section number for the break-glass clause.**
- v2/design.md line 286–296 introduces the break-glass and quotes it as "**§3.1 第三方 SDK 例外（v2 起）**".
- The break-glass actually lives at `foundations.md §9` (§9.1 / §9.2), per `foundations.md` lines 425–449. The v2 doc's own §Decisions table also says "foundations.md §3 加 break-glass for AdMob" (line 314) — same wrong number.
- v2/design.md line 333 ("下一步" §2) likewise says "更新 `docs/foundations.md §3` 加 break-glass 條款" — already done, and in §9 not §3.
- Fix: in `docs/v2/design.md`, replace the three `§3` / `§3.1` references with `§9` / `§9.1`; update the §Decisions row to "foundations.md §9 加 break-glass for AdMob"; remove or strike the "下一步" §2 bullet (the work is done — see `foundations.md §9.1`).

**S1-2. `docs/v2/design.md §How.9` body text contradicts what was actually written into `foundations.md §9.1`.**
- v2/design.md §How.9 says: "`foundations.md §6` 目前說『v1 走 Apple 三件套，不引入第三方 tracking SDK』。v2 在 `foundations.md §9` 加 break-glass" — this part is correct.
- But the quoted block immediately below is labelled "§3.1" (see S1-1) and does not match the actual prose now in `foundations.md §9.1`. `foundations.md §9.1` has richer content (privacy connectives, isolation contract wording, Privacy posture line) than the v2 doc's quoted draft.
- Fix: replace the quoted block in v2/design.md §How.9 with a one-line pointer "詳見 [`docs/foundations.md §9.1`](../foundations.md#91-admob--appmonetizationkitadsadmob-target-內隔離)"; remove the inline draft to prevent further drift.

### S2 (fix in v2 stabilization)

**S2-1. v1 design.md `§不在 v1 範圍 → 視覺資源 → Lottie` bullet (line 1496) is stale on two facts.**
- Claims Lottie would be "**第一個第三方 dep**" — no longer true once AdMob lands (v2.0 already merged per `meetings/2026-05-21_v2.0-monetization-kit-foundations.impl-notes.md`, `Packages/AppMonetizationKit/Package.swift` already declares GoogleMobileAds 11.x).
- Points readers to "`foundations.md §3`" for the deviation log — wrong section; should be `§9`.
- Fix: amend the Lottie bullet — "AdMob 已於 v2 起為第一個第三方 SDK；若引入 Lottie 將為**第二個** ... 加入前需在 `foundations.md §9` 新增 §9.X 子節，依 §9.2 程序執行".

**S2-2. v1 design.md L40 absolute claim is technically scoped to v1 but lacks a forward-pointer to v2.**
- Line 40 success-criterion: "除了 CloudKit + Game Center + Xcode Cloud + App Store Connect Analytics + MetricKit 之外，**我方不維運任何後端服務、不引第三方 SDK**". This is under "v1 成功標準" so technically not invalidated by v2. But casual readers will hit it without the v2-promotion footnote.
- The v1 商業模式 line (33) already has a "廣告策略保留在 backlog... 等 v2 評估" hint, and `§不在 v1 範圍 → 商業模式` (line 1482) explicitly promotes v2. So the chain is recoverable.
- Fix: add a one-line note after line 40 — "v2 起 AdMob 為受控例外（`foundations.md §9.1`、`docs/v2/design.md`）；v1 criterion 仍以 v1 build 為準".

**S2-3. `privacy-policy.md` UMP / ATT ordering wording vs `docs/v2/design.md §How.4` flow.**
- privacy-policy.md §廣告 (lines 73–74) lists UMP **after** ATT in the bullet ordering ("Requests tracking permission on first launch via ATT" → next bullet "For users in EU/UK/CA … presents GDPR/CCPA via UMP").
- v2/design.md §How.4 line 181 specifies the real call order: "UMP consent → ATT prompt → AdMob initialize". v2/plan.md v2.3.7 (lines 230–235) and v2.2.3 (line 149) re-state the same UMP → ATT → AdMob init order.
- Risk: a reader of the privacy policy may infer ATT-then-UMP, which contradicts what the App will actually do.
- Fix: in privacy-policy.md §廣告 reorder the bullets so UMP appears first, or add a sentence "UMP consent (jurisdiction-dependent) is presented before ATT".

**S2-4. v2/design.md §How.7 `AppComposition` snippet shows 5+3 separate stored properties; v2/plan.md v2.3.3 introduces RouteFactory which shrinks the surface to `routeFactory + 3 monetization deps`.**
- v2/design.md lines 230–263 shows the **intermediate** state (post v2.3.2, pre-v2.3.3) where `AppComposition` holds 8 separately-typed deps.
- v2/plan.md v2.3.3 (line 184–193) is where RouteFactory promotion collapses the 5 destination-view deps into one `routeFactory`. Final shape is `(rootViewModel, routeFactory, adProvider, iapClient, adGate)` — 5 deps.
- Drift: the v2 design snippet shows the *transition* state, not the final state, and gives no breadcrumb that v2.3.3 will refactor it. Reader-confusing.
- Fix: either annotate the snippet "intermediate state — see v2.3.3 RouteFactory promotion for final shape" or replace it with the post-RouteFactory shape.

### S3 (nits)

**S3-1. v2/plan.md line 7 link to "foundations.md §9 第三方 SDK 例外條款（v2 起）"** — correct text, but the markdown anchor `#9-第三方-sdk-例外條款v2-起` depends on the heading slugifier. Verify the anchor resolves on GitHub render before publishing.

**S3-2. v2/plan.md §Backlog (line 332–334)** just points at `docs/v2/design.md §Backlog` and `§Decisions`. Each phase claims a TODO sweep ("Phase v2.X 收尾 TODO sweep") per methodology.md §7, but no sweep evidence is yet committed. v2.0 / v2.1 / v2.2 impl-notes exist in `meetings/`; v2.3 only has Part A; v2.4 only has Part 1. Status header on v2/design.md and v2/plan.md remain `DRAFT` — consistent.

**S3-3. v2/design.md line 308–309** lists 廣告頻率 as "7-day grace + 1/day + dismissed-skip" — matches v2/plan.md v2.0.4 (lines 55–60) which encodes Day 0 / Day 7 / dismissed-today / hasPurchasedRemoveAds. ✓ no drift, but the v2/design §What table is row 6, and §Decisions row 6 / 7 / 8 split the same concept into three rows — small duplication, not a bug.

**S3-4. Package.swift vs foundations §9.1 isolation contract.**
- `Packages/AppMonetizationKit/Package.swift` lines 24–34: only `AdsAdMob` target depends on `GoogleMobileAds`; `MonetizationCore` / `IAPStoreKit2` / `MonetizationTesting` have zero third-party dep. ✓
- foundations.md §9.1 line 434–436 states the same contract. ✓
- v2/design.md §How.1 lines 56–61 dep direction also matches. ✓
- All three say the same thing; no drift. (Recorded as a positive cross-doc consistency anchor.)

**S3-5. methodology.md §Patterns and §Backlog** are aligned with the v2 dispatch reality (v2.0 / v2.1 / v2.2 / v2.3 Part A / v2.4 Part 1 all have impl-notes meeting logs with date prefix `2026-05-21_v2.X-*.impl-notes.md` — consistent with `meeting-logs-convention`). No drift.

---

## Cross-doc reference table

| Concept | v1 design | v2 design | v2 plan | foundations | privacy-policy |
|---|---|---|---|---|---|
| Third-party SDK policy | §What 成功標準 L40 ("不引第三方 SDK", v1-scoped); §不在 v1 範圍 line 1482 promotes v2; line 1496 Lottie bullet **stale (S2-1)** | §How.9 break-glass body (correctly cites §9 once, wrongly cites §3 / §3.1 three times — **S1-1, S1-2**) | (implicit; phase v2.2 ⚠️ note line 117 cites "foundations §9.1" ✓) | §9 / §9.1 (canonical) | §third-party-services L48 ("None embedded") still says "v1 baseline" but no v2-equivalent paragraph; partial coverage via §廣告與 IAP |
| AdGate frequency (7-day grace, 1/day, dismissed-skip) | n/a | §What table row 6 / §Decisions row 7-9 / §How.3 ✓ | v2.0.4 AdGate tests L55-60 ✓ | (n/a — product concern) | §廣告 L61-63 ✓ |
| IAP shape ("Remove Ads", $2.99, non-consumable) | n/a | §What row 3 / §How.5 ASC L186-191 ✓ | v2.4.4 ASC product registration L282-286 ✓ | (n/a) | §內購 L93-96 ✓ |
| AdsAdMob isolation contract | n/a | §How.1 dep direction L56-61; §How.9 (wrong §3 ref — S1-1) | v2.2.1 isolation audit L126; v2.2.3 audit L151 ✓ | §9.1 (canonical) ✓ | (n/a) |
| `MonetizationState` CloudKit record | n/a | §How.3 L155-157 ✓ | v2.3.1 schema L161-168 ✓ | (n/a — product concern) | (n/a) |
| ATT / UMP order | n/a | §How.4 L181: "UMP → ATT → AdMob init" ✓ | v2.2.3 L149; v2.3.7 L230-235 ✓ | (n/a) | §廣告 bullets — **ordering reads ATT-first (S2-3)** |
| PrivacyInfo.xcprivacy v2 delta | n/a | §How.8 L271-275 ✓ | v2.4.1 L249-255 ✓ | (n/a) | §廣告 L80-86 ✓ (8 domains explicitly listed — superset of v2/design "per Google docs", OK) |
| AppComposition shape | §How.1 L148-159 v1 (5 deps) | §How.7 L230-263 v2 intermediate (8 deps, pre-RouteFactory — **S2-4**) | v2.3.2 + v2.3.3 final = 5 deps via RouteFactory | (n/a) | (n/a) |
| Methodology §7 TODO sweep | (n/a — process) | (n/a) | each phase says "收尾 TODO sweep" ✓ | §9.2 process rule for new SDK adds ✓ | (n/a) |

---

## Files inspected

- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/design.md` (full, in 3 reads — 1500+ lines)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/foundations.md` (full)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/v2/design.md` (full)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/v2/plan.md` (full)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/methodology.md` (full)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/docs/privacy-policy.md` (full)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/AppMonetizationKit/Package.swift` (full, read-only spot check)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/meetings/` ls (for naming convention compliance check)

No `.swift` source files outside `Package.swift` were read. No edits made outside this report.
