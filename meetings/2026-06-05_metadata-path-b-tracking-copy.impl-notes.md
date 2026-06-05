# Impl Notes — metadata Path-B tracking copy fix (2026-06-05)

Status: COMPLETE
Owner: App Store Optimizer subagent
Dispatched by: Leader
Started: 2026-06-05

## 設計決定 (Design decisions)

- **Grounding source** — All gentle framing taken verbatim-in-spirit from `docs/marketing/BRIEF.md`
  §Do-Not-Claim "No tracking" entry + Privacy row. Approved Path B framing: "no first-party
  analytics SDK building a profile of you; ads may use an ad identifier to stay relevant, only with
  your permission — decline and ads still work (just less tailored), or remove ads entirely. The
  tracking is for ad relevance, not a personal profile."
- **Per-field length adaptation** — promo ≤170 chars forces a short variant ("Ads may use an ad ID
  to stay relevant — only with your OK; decline or remove them"). description (≤4000) gets the full
  gentle paragraph. whats_new (≤4000) gets a one-line gentle variant.
- **Minesweeper description (L28) is NOT false** — it says "No first-party analytics. No CRM. No
  backend of our own" + names Google's banner-ad library; it never claims "no tracking". Per dispatch
  §3 I still append the gentle ad-identifier-for-relevance note to the third-party-SDK sentence so the
  description doesn't *imply* zero tracking. This is an honesty enhancement, not a falsehood fix.
- **Minesweeper whats_new has NO tracking claim** — nothing to change there.

## 偏離 (Deviations)

- **#306 whats_new line not found as described** — Dispatch §3 expected Sudoku whats_new ~L52 to read
  "ads are non-personalized — no tracking, privacy unchanged" (from held #306 PR). The actual branch
  base has the simpler `• No tracking. An optional banner you can remove...` at L54 in all 7 Sudoku
  files. #306's specific phrasing is NOT on this branch base. I fix the line that exists (the false
  "No tracking" bullet) under Path B framing; this still supersedes #306's intent (#306 would have
  reintroduced a "no tracking" claim). Flagged so Leader can confirm #306 is fully superseded.

## 折衷 (Tradeoffs)

- **Promo voice vs. completeness** — At ≤170 chars I cannot fit "decline → still works" AND "remove
  ads" AND "no first-party profiling". Picked: keep the "remove with one purchase" hook (it's the
  monetization CTA) + add a short honest ad-ID clause; drop the decline-still-works nuance from promo
  only (it stays in description). Rationale: promo is a hook, description carries the full honest detail.

## 字數 (Char-cap verification)

- All 14 `promotional_text` fields re-verified ≤170 after Path-B rewrite (en/es/th promos initially
  ran 175–211 over; tightened: SUD en 169, MS en 168, SUD es 168, MS es 169, SUD th 162, MS th 170).
  CJK promos unchanged-length and well under cap. descriptions/whats_new all far under 4000.
- COPY-REVIEW.md still contains historical "No tracking" strings (lines 47/91/94) — left intact on
  purpose: it is a review/audit doc describing this very defect, NOT a live listing field. Editing it
  would erase the audit trail. Out of dispatch scope (scope = listing.yaml). Flagged for Leader.

## 未決 (Open questions)

- **#306 supersession** — Confirm the held #306 PR is closed/superseded by this branch, since its
  whats_new content (a "no tracking" reassertion) directly conflicts with Path B. Default: treated as
  superseded per dispatch §3. Risk if wrong: #306 merge would re-break the live copy.
