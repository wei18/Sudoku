# ASC Submission Checklist — v2.6 (both apps; Minesweeper's first submission ships as 2.6.0)

Linear copy-paste session guide. Work top-to-bottom per app.
All source files live under `docs/app-store/`.

---

## Before you start (one-time per session)

- [ ] Have `secrets/.env` open (ASC_REVIEW_EMAIL, ASC_REVIEW_PHONE).
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
| Phone Number | Contact table (from secrets/.env ASC_REVIEW_PHONE) |
| Email | Contact table (from secrets/.env ASC_REVIEW_EMAIL) |
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

- [ ] CloudKit Production schema deployed for both apps (user-owned — Console only).
- [ ] Production AdMob IDs swapped in (secrets/.env — rebuild + upload required).
- [ ] App Privacy questionnaire completed for each app in ASC.
- [ ] All IAPs attached and **Ready to Submit**.
- [ ] Build uploaded via TestFlight (`mise run tf:upload <app> <platform> --i-am-sure`).
- [ ] Build selected in the Version Information → Build section.
- [ ] Pricing set (Free with IAP).
- [ ] Diff ASC live page against YAML files after save — ASC silently trims whitespace.
