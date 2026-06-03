# Impl Notes — ASC submission prep (Sudoku v2.5 + Minesweeper v1) (2026-06-04)

Status: COMPLETE
Owner: Developer/Researcher (worktree dispatch)
Dispatched by: Leader
Started: 2026-06-04

Scope: research + materials + plan for App Store submission ahead of the
built binaries (#236, expanded). No ASC API Swift impl this round.

## 設計決定 (Design decisions)

- **Per-app metadata structure** — Existing `docs/app-store/metadata/{locale}/`
  is Sudoku-implicit (single-app). I chose to introduce
  `docs/app-store/metadata/minesweeper/{locale}/listing.yaml` *alongside* the
  existing Sudoku-implicit tree (NOT a disruptive `sudoku/` move). Rationale:
  the Sudoku files + the `iap/` dir are already referenced by README,
  v2.5-readiness, the asc-ops-handoff skill, and `ASCRegister` future-mode
  notes by their current path. Moving them to `sudoku/` is a churny rename
  that breaks those references for zero functional gain this round. A new
  `minesweeper/` subtree is the minimal, reversible mirror. Documented the
  choice + the eventual `sudoku/` symmetrisation as a future option in the
  metadata README.

- **MS metadata honesty boundary** — MS as actually wired (read Live.swift,
  parity audit, Info.plist) has: Daily hub (STUB — placeholder cards, no
  date-seeded engine, no persisted completion), Practice hub, AdMob banner,
  Remove Ads IAP, CloudKit persistence wiring, Telemetry. It has **NO Game
  Center** (only the entitlement is set; no `LiveGameCenterClient`, no
  leaderboards/achievements registered). So MS listings:
    - DO mention: minesweeper gameplay, first-click safety, three classic
      difficulties (Beginner 9×9/10, Intermediate 16×16/40, Expert 16×30/99),
      cross-device, no-tracking-beyond-ads, Remove Ads IAP, 7 languages,
      Mac-native.
    - Do NOT mention: leaderboards / achievements / Game Center (not wired) —
      flagged "pending feature" in the review notes + listing comments.
    - Daily: mentioned cautiously as the app currently ships the Daily hub
      but the date-seeded scoring engine is a follow-up; I describe it as
      "a daily set of boards" without promising leaderboard scoring.

- **MS review-notes IAP/ATT accuracy** — MS Info.plist now carries
  `GADApplicationIdentifier`, `GADBannerUnitID`, `NSUserTrackingUsageDescription`,
  `ITSAppUsesNonExemptEncryption=false` (advanced past the 2026-06-02 parity
  audit which flagged them missing). So MS review notes describe the same
  ATT/UMP + Remove Ads sandbox flow as Sudoku. Banner placement: MS has
  `MinesweeperBannerSlotView`.

- **MS PrivacyInfo caveat surfaced** — `Minesweeper/Resources/PrivacyInfo.xcprivacy`
  is STILL the verbatim Sudoku copy (NSPrivacyTracking=true + AdMob domains),
  with a "flip to false if monetization diverges" comment. Since MS DID wire
  AdMob, the `true` stance is now correct, but the file's framing comment is
  stale ("copied in anticipation"). I noted in the MS review notes that the
  manifest reflects the real AdMob integration; did not edit the manifest
  (out of scope; surgical).

- **ASC metadata-API plan = formalising the BACKLOG item** — asc-ops-handoff
  skill lists "Upload App Metadata … `ASCRegister app-metadata` mode" as
  📅 BACKLOG. The plan doc turns that backlog line into a concrete resource
  map + subcommand shape, mirroring the existing `iap` subcommand
  (Config + ASCClient+IAP + Reconciler) pattern.

## 偏離 (Deviations)

- **Did not create `docs/app-store/review/` screenshots** — #236 lists IAP
  flow / GC leaderboard / privacy-rationale screenshots under
  `docs/app-store/review/`. Per task constraint ("don't fabricate images"),
  I list the required attachments in each review .md as a checklist with
  `status: pending-built-app` rather than committing placeholder PNGs.

## 折衷 (Tradeoffs)

- **`minesweeper/` subtree vs `{sudoku,minesweeper}/` split** — Considered
  fully symmetrising now (move Sudoku into `sudoku/`). Picked the additive
  `minesweeper/` subtree to keep the diff surgical and avoid breaking the
  many existing path references. The README documents the asymmetry + the
  migration path, so a future symmetrisation is a known, cheap follow-up.

- **Locale coverage** — Fully drafted MS `en` + `zh-Hant` (author-source tier)
  and also drafted `ja`, `zh-Hans`, `es`, `th`, `ko` (AI-translated tier) so
  the 7-locale set is complete, matching Sudoku's coverage. Translations
  follow `ai-translated-localization` etiquette already applied in the Sudoku
  files (no honorifics in ja; no ครับ/ค่ะ in th; 해요체 in ko; neutral LATAM
  es; term-level zh-Hans).

## 未決 (Open questions)

- **MS support / privacy-policy URLs** — Sudoku uses
  `github.com/wei18/Sudoku/issues` + `.../docs/privacy-policy.md`. MS has no
  published repo URL yet. I used `github.com/wei18/Minesweeper/...` as the
  parallel placeholder and flagged it. Leader/User: confirm the MS repo slug
  (or whether MS ships from the same Sudoku monorepo URL).

- **MS app name / subtitle final wording** — Drafted "Minesweeper — Classic &
  Daily" (en) / "踩地雷 — 經典與每日" (zh-Hant). zh-Hant term: Taiwan convention
  is 踩地雷; mainland 扫雷 used for zh-Hans. Confirm 踩地雷 is the preferred TW
  brand name.

- **Sudoku v2.5 whats_new** — The existing Sudoku `listing.yaml` whats_new is
  the v1.0 release text. v2.5 adds monetization (banner ads + Remove Ads IAP).
  I did NOT edit the Sudoku listing.yaml files this round (out of scope — task
  is MS listings + review notes + plan). The Sudoku v2.5 whats_new refresh is
  noted as a follow-up in the review doc. Confirm whether to also draft the
  Sudoku v2.5 whats_new across 7 locales (separate small task).
