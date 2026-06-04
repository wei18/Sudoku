# Marketing Positioning Brief — Sudoku & Minesweeper

**Audience for this file:** every content/PR/ASO/social agent. Read this first. Ground EVERY
claim in the Verified Facts table. If you want to say something not in the table, mark it
`[UNVERIFIED — Leader confirm]` rather than asserting it. We have previously shipped two
factually-wrong store claims (see §Do-Not-Claim); do not repeat that class of error.

## Positioning (dual)

The user chose **both** goals — write so a single artifact can serve both where possible,
and split voice only where it must:

1. **Portfolio / credibility** (audience: hiring managers, senior engineers, the iOS dev
   community). Hook = a solo-built, production-grade, privacy-first Apple-platform app with
   clean modular architecture, Swift 6 strict concurrency, snapshot testing, and two apps
   sharing portable cores. Channels: README, dev-story (LinkedIn / Show HN), architecture
   showcase.
2. **User acquisition** (audience: people who want a calm, private puzzle game). Hook =
   no tracking, iCloud sync, Game Center, free with an optional one-tap Remove Ads.
   Channels: App Store ASO, App Store copy, social.

Voice: calm, precise, understated. No hype adjectives ("amazing", "revolutionary"). No
emoji-spam. Confidence through specifics, not superlatives. This mirrors the apps' own
"calm" brand contract.

## Verified Facts (the ONLY claims you may assert)

| Topic | Sudoku | Minesweeper |
|---|---|---|
| Status | v2.3.5, App Store submission prep | v1, build-out, not yet submitted |
| Platforms | iOS + macOS (SwiftUI) | iOS + macOS (SwiftUI) |
| Localization | 7 locales (zh-TW, en, ja, zh-CN, es, th, ko) | same 7 locales |
| Game Center | Leaderboards + **daily** leaderboards, live | per-difficulty **daily** leaderboards, live |
| iCloud sync | Full game saves + records sync via CloudKit | **MonetizationState only** — NO game saves synced |
| Monetization | Free; **removable banner ad** + one-time **Remove Ads** IAP | (ads planned, not yet live) |
| Privacy | No third-party tracking SDK. Apple-only: App Store Analytics + MetricKit + Game Center. PrivacyInfo.xcprivacy shipped | same privacy posture |
| Saved-game / resume | Has saved-game persistence | **NO saved-game / resume flow** (do not claim resume) |

## Architecture facts (for portfolio/dev content only)

- Single Swift Package, multi-target, thin App target, DI composition root.
- Portable game cores (`SudokuEngine`, `MinesweeperEngine`) with no Apple-UI deps — the two
  apps share a `GameShellKit` shell; Minesweeper mirrors Sudoku's architecture.
- Swift 6 language mode, complete concurrency checking from day one.
- swift-testing + pointfreeco/swift-snapshot-testing; snapshot PNGs committed.
- Xcode Cloud single-track CI; mise-managed tool versions; gitleaks + lefthook pre-commit.
- Solo-built by the developer (Wei18).

## Do-Not-Claim (previously-shipped errors — never repeat)

- ❌ "No ads" / "ad-free" for **Sudoku** — it ships a removable banner. Correct framing:
  "free, with an optional one-tap Remove Ads."
- ❌ "Resume your saved game" for **Minesweeper** — there is no saved-game flow.
- ❌ Any third-party-analytics or social-login claim — there are none.
- ❌ "Syncs your games across devices" for **Minesweeper** — only monetization state syncs.
- ❌ Award/ranking/userbase numbers — we have none to cite. Do not invent.

## Output rules

- Write to your assigned subdir only (no cross-writes): `docs/marketing/launch/`,
  `docs/marketing/aso/`, `docs/marketing/social/`. App Store copy edits go where the
  dispatch says.
- These are DRAFTS for Leader/user review. Nothing here is published. Do not call any
  external/publishing API.
- Cite which Verified-Fact row backs each headline claim where practical.
