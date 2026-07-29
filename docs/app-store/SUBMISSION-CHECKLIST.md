# ASC Submission Checklist — v2.6 (both apps; Minesweeper's first submission ships as 2.6.0)

Linear copy-paste session guide. Work top-to-bottom per app.
All source files live under `docs/app-store/`.

---

## Step 0 — run the preflight gate FIRST (Leader-orderable, read-only)

A real 2026-07-28 submission attempt hit nine ASC-side prerequisites one at a
time, each discovered only when a mutating call was already rejected — because
nothing in this repo tracked them. `mise run preflight:submission <app> <platform>`
checks all nine (plus version/editable-state, screenshot coverage, and IAP) in
one read-only pass and exits non-zero if anything blocks. Run it before
starting this checklist, and again right before clicking Submit:

```
mise run preflight:submission all all
mise run preflight:submission all all --fix   # safe auto-fill only (see table below)
```

| # | Prerequisite | Owner | Auto-fixable via `--fix`? |
|---|---|---|---|
| 1 | `appStoreVersions.releaseType` = `MANUAL` (not `AFTER_APPROVAL`, which auto-releases the instant Apple approves) | Leader-orderable | ✅ yes |
| 2 | A processed build attached to the version | Leader-orderable | ✅ yes (newest `VALID` build for the platform) |
| 3 | `copyright` set on the version (value lives in `app-meta.yaml`) | Leader-orderable | ✅ yes |
| 4 | App price schedule set (empty → `STATE_ERROR.APP_PRICING_REQUIRED`, submission refused) | 🙋 user (web UI — Pricing and Availability; a decision, not automatable) | ❌ no |
| 5 | `ageRatingDeclaration` fully answered | 🙋 user (web UI — App Information → Age Rating; a decision) | ❌ no |
| 6 | `contentRightsDeclaration` answered | 🙋 user (web UI — App Information; a decision) | ❌ no |
| 7 | `appStoreReviewDetail` record exists with contact name/email/phone | 🙋 user (PII — see review-information.md contact table below) | ❌ no |
| 8 | Screenshots present for every locale that carries listing text × every required device class | Leader-orderable (`ASCRegister metadata screenshots --i-am-sure`) | ❌ no (preflight only detects the gap; upload is a separate step) |
| 9 | No stray/in-flight `reviewSubmissions` record blocking a new one (cannot be DELETEd; can only be cancelled while `IN_REVIEW`/`UNRESOLVED_ISSUES` — see `asc-entity-error-recipes.md`) | 🙋 user (ASC web UI — cancelling an in-flight review is a judgment call) | ❌ no |

App Privacy has no ASC REST API at all (verified) — the preflight prints it as
a MANUAL-VERIFY line, never a silent PASS. It stays 🙋 user, always.

---

## Before you start (one-time per session)

- [ ] Run `mise run preflight:submission all all` — fix everything it reports
      as Leader-orderable before continuing below.
- [ ] Have `docs/app-store/review/<app>-v2.6-review-information.md` open — the
      contact name/phone/email are supplied by the user directly at
      submission time; they are **not** stored anywhere in this repo (correcting
      a prior false claim that they lived in `secrets/.env`).
- [ ] Have `memory/project/asc-api-credentials.md` open (Apple ID numbers).
- [ ] Log in to [appstoreconnect.apple.com](https://appstoreconnect.apple.com).

---

## SUDOKU — App Information (non-versioned, set once)

**ASC path:** My Apps → Sudoku → App Information

| ASC field | Source | Value |
|---|---|---|
| Name | `sudoku/<locale>/listing.yaml` → `name` | per locale (see table below) |
| Subtitle | `sudoku/<locale>/listing.yaml` → `subtitle` | per locale |
| Privacy Policy URL | any `listing.yaml` | `https://github.com/wei18/Sudoku/blob/main/docs/privacy-policy.md` |
| Primary Category | `sudoku/app-meta.yaml` | Games → Puzzle, Board |
| Secondary Category | `sudoku/app-meta.yaml` | (none — same genre rule) |
| Copyright | `sudoku/app-meta.yaml` | `2026 Wei18` |
| Age Rating | any `listing.yaml` | 4+ |

---

## SUDOKU — Version Information (v2.6, per locale × 7)

**ASC path:** My Apps → Sudoku → [version 2.6] → Version Information → [select locale]

For each of the 7 locales, paste from `metadata/sudoku/<locale>/listing.yaml`:

| Locale | ASC locale code | Source file |
|---|---|---|
| English | en-US | `sudoku/en/listing.yaml` |
| Traditional Chinese | zh-Hant | `sudoku/zh-Hant/listing.yaml` |
| Japanese | ja | `sudoku/ja/listing.yaml` |
| Simplified Chinese | zh-Hans | `sudoku/zh-Hans/listing.yaml` |
| Korean | ko | `sudoku/ko/listing.yaml` |
| Spanish | es-ES | `sudoku/es/listing.yaml` |
| Thai | th | `sudoku/th/listing.yaml` |

**Fields to paste per locale:**

| ASC field | YAML key | Char limit |
|---|---|---|
| Name | `name` | 30 |
| Subtitle | `subtitle` | 30 |
| Promotional Text | `promotional_text` | 170 |
| Description | `description` | 4000 |
| Keywords | `keywords` | 100 (comma-separated) |
| What's New | `whats_new` | 4000 — **skip on first-ever submission for that platform** |
| Support URL | `support_url` | — |

> **whats_new gate:** ASC rejects `whats_new` on a version that has never been
> released on a given platform (HTTP 409 STATE_ERROR). If this is the first iOS
> or macOS release, leave What's New blank for that platform.

---

## SUDOKU — App Review Information

**ASC path:** My Apps → Sudoku → [version 2.6] → App Review Information

Source: `docs/app-store/review/sudoku-v2.6-review-information.md`

| ASC field | Source |
|---|---|
| First Name | Contact table in review-information.md |
| Last Name | Contact table in review-information.md |
| Phone Number | Contact table — supplied by the user directly at submission time (not stored in this repo) |
| Email | Contact table — supplied by the user directly at submission time (not stored in this repo) |
| Demo Account Username | (leave blank — no login required) |
| Demo Account Password | (leave blank — no login required) |
| Notes | Paste the fenced code block verbatim from review-information.md |

---

## SUDOKU — In-App Purchases

**ASC path:** My Apps → Sudoku → In-App Purchases → Remove Ads

Source: `metadata/sudoku/iap/remove-ads.yaml`

- [ ] IAP exists and status = **Ready to Submit**
- [ ] Attached to this version
- [ ] Review screenshot uploaded (see `iap/remove-ads.yaml` → `screenshot.expected_path`)

---

## MINESWEEPER — App Information (non-versioned)

**ASC path:** My Apps → Minesweeper → App Information

| ASC field | Source | Value |
|---|---|---|
| Name | `minesweeper/<locale>/listing.yaml` → `name` | per locale |
| Subtitle | `minesweeper/<locale>/listing.yaml` → `subtitle` | per locale |
| Privacy Policy URL | any `listing.yaml` | `https://github.com/wei18/Sudoku/blob/main/docs/privacy-policy.md` |
| Primary Category | `minesweeper/app-meta.yaml` | Games → Board, Puzzle |
| Secondary Category | `minesweeper/app-meta.yaml` | (none) |
| Copyright | `minesweeper/app-meta.yaml` | `2026 Wei18` |
| Age Rating | any `listing.yaml` | 4+ |

---

## MINESWEEPER — Version Information (v2.6, per locale × 7)

**ASC path:** My Apps → Minesweeper → [version 2.6.0] → Version Information → [select locale]

| Locale | ASC locale code | Source file |
|---|---|---|
| English | en-US | `minesweeper/en/listing.yaml` |
| Traditional Chinese | zh-Hant | `minesweeper/zh-Hant/listing.yaml` |
| Japanese | ja | `minesweeper/ja/listing.yaml` |
| Simplified Chinese | zh-Hans | `minesweeper/zh-Hans/listing.yaml` |
| Korean | ko-KR | `minesweeper/ko/listing.yaml` |
| Spanish | es-ES | `minesweeper/es/listing.yaml` |
| Thai | th | `minesweeper/th/listing.yaml` |

Same field set as Sudoku table above.

> **whats_new gate:** Minesweeper 2.6.0 is the FIRST release on both platforms
> (version string synced with Sudoku since a3e80d7; ASC confirmed 2026-07-04) —
> leave What's New blank in ASC for both iOS and macOS. The `whats_new` key in
> the YAML is authored for future reference; ASC will reject it on first submission.

---

## MINESWEEPER — App Review Information

**ASC path:** My Apps → Minesweeper → [version 2.6.0] → App Review Information

Source: `docs/app-store/review/minesweeper-v2.6-review-information.md`

Same field mapping as Sudoku above.

---

## MINESWEEPER — In-App Purchases

**ASC path:** My Apps → Minesweeper → In-App Purchases → Remove Ads

Source: `metadata/minesweeper/iap/remove-ads.yaml`

- [ ] IAP `com.wei18.minesweeper.iap.remove_ads` created in ASC
- [ ] Status = **Ready to Submit**
- [ ] Attached to this version
- [ ] Review screenshot uploaded

---

## Screenshots (both apps)

**ASC path:** [version] → Version Information → [locale] → Screenshots

Strategy: `docs/app-store/screenshot-strategy.md`
PNG files: `docs/app-store/screenshots/<app>/<device-class>/<locale>/`

Required device classes per Apple (at least one of each required set):
- iPhone 6.9" or 6.7" (required)
- iPad Pro 13" (required if iPad is supported)
- Mac (required for macOS)

---

## Final gates before clicking "Submit for Review"

- [ ] `mise run preflight:submission all all` reports zero BLOCK rows (re-run —
      Step 0 was before the rest of this checklist, state may have drifted).
- [ ] CloudKit Production schema deployed for both apps (user-owned — Console only).
- [ ] Production AdMob IDs swapped in (secrets/.env — rebuild + upload required).
- [ ] App Privacy questionnaire completed for each app in ASC (MANUAL-VERIFY —
      no API; the preflight cannot check this one).
- [ ] Build uploaded via TestFlight (`mise run tf:upload <app> <platform> --i-am-sure`).
- [ ] Diff ASC live page against YAML files after save — ASC silently trims whitespace.
