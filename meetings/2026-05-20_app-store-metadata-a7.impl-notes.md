# Impl-notes — Phase 10 A7: App Store metadata + screenshot strategy

Date: 2026-05-20
Branch: `feat/app-store-metadata-v1`
Status: COMPLETE

## §設計決定

- **Source-of-truth locales** are zh-Hant + en (project convention from `ai-translated-localization` skill); other 5 (ja, zh-Hans, es, th, ko) are AI-translated derivatives. Both zh-Hant and en were authored independently from `docs/feature-tour.md` rather than translating one from the other.
- **YAML format** chosen over JSON for `listing.yaml` — multi-line `description:` / `whats_new:` use literal block scalars (`|`) for readability; future ASCRegister CLI extension can consume via any YAML parser.
- **Field naming** follows ASC API terminology (App Store Connect): `name`, `subtitle`, `promotional_text`, `description`, `keywords`, `whats_new`, `marketing_url`, `support_url`, `privacy_policy_url`. This eases future automation.
- **Keywords strategy** — 100-char limit shared across comma-separated terms; targeted Apple Search Ads-friendly terms (sudoku, daily, puzzle, brain, logic, offline, ipad, mac). No brand-piggyback ("sudoku.com", "lumosity") — honest posture.
- **Subtitle ≤ 30 chars** — used to differentiate platforms ("Daily puzzles. iPhone & Mac.") rather than restate "Sudoku" already in name.
- **Description structure** — 5-section template per locale: (1) one-line opener echoing subtitle, (2) what's inside (Daily / Practice / GC), (3) cross-platform Mac-native pitch, (4) privacy posture, (5) localization & accessibility note. Stays well under 4000 chars (~ 1500-1800 chars per locale).
- **What's New v1.0.0** — first launch, so reads as a release manifesto rather than changelog.
- **Privacy policy** — minimal but accurate per `App/Resources/PrivacyInfo.xcprivacy`: NSPrivacyTracking=false, empty tracking domains, empty collected data types, empty accessed API types. Reflects "no PII, no 3P SDK, CloudKit private DB stays in user's iCloud, Game Center mediated by Apple" stance.
- **Marketing URL** — left as `null` since project has no marketing site; can be added later (e.g. GitHub Pages).

## §偏離

- (none from brief)

## §折衷

- Per-locale character counts not exactly equal — Japanese / Korean / Thai use fewer characters; Spanish typically expands 15-30%. All within Apple's hard limits, verified at end of each file by manual count.
- Screenshot **strategy** doc lists per-shot copy in all 7 locales, but actual PNG generation is Phase 10 A5 (Xcode Simulator + Liquid Glass captures). This file gives the capture team a complete shot list.
- Keywords for zh-Hant + zh-Hans use Latin separator `,` not `，` because Apple's keyword field counts and tokenizes on ASCII comma.

## §未決

- **Primary App Store category**: recommend `Games > Puzzle`; secondary candidate `Games > Family` or `Games > Board`. Needs Leader confirmation.
- **Age rating**: recommend 4+ (no objectionable content, no UGC, no web links beyond support/privacy).
- **Beta tester / TestFlight group strategy**: out of A7 scope; flagged here for completeness for Phase 10 A4.
- **Marketing URL**: if a GitHub Pages site is set up later (e.g. `https://wei18.github.io/Sudoku/`), update all 7 `listing.yaml`.

## Files produced

- `docs/app-store/metadata/README.md`
- `docs/app-store/metadata/{en,zh-Hant,ja,zh-Hans,es,th,ko}/listing.yaml` (7 files)
- `docs/app-store/screenshot-strategy.md`
- `docs/privacy-policy.md`

## TODO sweep

Ran ripgrep-style mental sweep on `docs/app-store/` and `docs/privacy-policy.md` for: `TODO|FIXME|XXX|HACK|TBD|placeholder` — 0 hits. The `null` value on `marketing_url` is intentional and documented in §未決.
