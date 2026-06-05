# Press Kit — Sudoku & Minesweeper (DRAFT)

> Draft for Leader/user review. Every claim is grounded in `docs/marketing/BRIEF.md`
> Verified Facts (privacy framing = Path B). Items marked `[UNVERIFIED — Leader confirm]`
> are genuine open product decisions, not facts.

---

## One-liner

Two calm, privacy-respecting logic games for iPhone and Mac, built solo from a single
Swift 6 codebase.

## Short descriptions

### Sudoku — 50 words

Sudoku is a calm logic game for iPhone and Mac. Play Daily ranked puzzles or untimed
Practice, with progress synced through your own iCloud and Game Center leaderboards. No
first-party analytics profiling you. Free, with an optional one-tap Remove Ads purchase.
Seven languages, one native SwiftUI codebase across both platforms.

### Sudoku — 100 words

Sudoku is a deliberately calm logic game for iPhone and Mac. Choose Daily puzzles ranked on
Game Center — including daily leaderboards — or play untimed Practice rounds at your own
pace. Saves and records follow you across devices through your own iCloud, with no account
beyond it. There's no first-party analytics SDK building a profile of you; the only Apple
services are App Store Analytics, MetricKit, and Game Center. It is free with a single
removable banner; ads may use an ad identifier for relevance only with your permission, or
a one-time Remove Ads purchase clears them. Localized in seven languages, native on both.

### Minesweeper — 50 words

Minesweeper is the classic, kept calm, for iPhone and Mac. Play Beginner, Intermediate, or
Expert with a first-tap-safe board and per-difficulty daily leaderboards on Game Center. No
first-party analytics profiling you. Built from the same Swift 6 codebase as its sibling
Sudoku, sharing a common app shell across both platforms.

### Minesweeper — 100 words

Minesweeper is the classic mine-finding puzzle, kept deliberately calm, for iPhone and Mac.
Play Beginner, Intermediate, or Expert difficulties on a first-tap-safe board, with
per-difficulty daily leaderboards live on Game Center. It carries the same privacy posture
as its sibling Sudoku: no first-party analytics SDK building a profile of you, with Apple's
own App Store Analytics, MetricKit, and Game Center as the only services. Minesweeper is
built from the same Swift 6 codebase as Sudoku and shares a common navigation and settings
shell, so the two apps differ only where the gameplay genuinely differs. Localized in seven
languages, native SwiftUI on both platforms.

## Key facts

| | Sudoku | Minesweeper |
|---|---|---|
| Status | v2.5, available on the App Store | v1.0, in build-out, not yet submitted |
| Platforms | iOS + macOS, native SwiftUI | iOS + macOS, native SwiftUI |
| Languages | 7 (zh-TW, en, ja, zh-CN, es, th, ko) | 7 (same set) |
| Game Center | Leaderboards + daily leaderboards | Per-difficulty daily leaderboards |
| iCloud | Full saves + records via CloudKit | Monetization state only (no game saves) |
| Monetization | Free; removable banner + one-time Remove Ads IAP | Ads planned, not yet live |
| Privacy | No first-party analytics SDK; ads may use an ad identifier for relevance only with permission | Same posture (ads not yet live) |

## What's notable (portfolio / credibility angle)

- **Privacy by construction.** No first-party analytics SDK builds a profile of you. The
  Apple-side services are App Store Analytics, MetricKit, and Game Center. A
  `PrivacyInfo.xcprivacy` manifest is shipped; it honestly declares that AdMob may use the
  iOS ad identifier for ad relevance, gated behind the ATT permission prompt — decline and
  ads still serve, just less tailored, or remove ads entirely.
- **Swift 6 from the first line.** Swift 6 language mode with complete concurrency checking
  enabled from day one, not retrofitted.
- **Shared portable cores.** Two apps are built from one Swift Package. The game engines
  (`SudokuEngine`, `MinesweeperEngine`) import only Foundation — no Apple UI — and the apps
  share a common `GameShellKit` shell. Minesweeper mirrors Sudoku's architecture in every
  layer except the gameplay screen, by reuse rather than copy-paste.
- **Tested and reproducible.** swift-testing plus pointfreeco's swift-snapshot-testing, with
  snapshot images committed. CloudKit and Game Center are exercised through protocol fakes so
  the suite runs on a clean CI runner.

## What's notable (user angle)

- **Calm by design.** No streak pressure, no nags — Daily ranked play if you want it,
  untimed Practice if you don't.
- **Your data stays yours.** Saves live in your own iCloud; there's no account beyond it and
  no first-party analytics profiling you.
- **Fair monetization.** Free to play with a single removable banner; one tap and one
  one-time purchase clears it for good.
- **Native on both screens.** One app, iPhone and Mac, real SwiftUI on each.

## Developer bio

Built solo by Wei18, an Apple-platform developer. The full source spec, architecture
decisions, and engineering methodology for both apps are public and have been since the
first commit: https://github.com/wei18/Sudoku

## Boilerplate

Sudoku and Minesweeper are two calm, privacy-respecting logic games for iPhone and Mac,
built solo from a single Swift 6 codebase. Both keep a deliberately small footprint: no
first-party analytics SDK profiling the player, no accounts beyond the player's own iCloud.
Ads (Sudoku) may use an ad identifier for relevance only with the player's permission, and
can be removed entirely. The project is developed in the open as a portfolio of clean,
modular Apple-platform engineering.

## Where to find it

- Sudoku on the App Store: https://apps.apple.com/app/id6771248206
- Minesweeper on the App Store (live once approved): https://apps.apple.com/app/id6775733519
- Source: https://github.com/wei18/Sudoku
- The simplest way to reach the developer is to find the app and leave a review on the
  App Store. (No dedicated press/contact email exists.)

## Assets available on request

`[UNVERIFIED — Leader confirm]` — list of screenshots, app icons, and device frames to be
confirmed once captured.
