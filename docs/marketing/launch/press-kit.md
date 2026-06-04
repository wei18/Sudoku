# Press Kit — Sudoku & Minesweeper (DRAFT)

> Draft for Leader/user review. Every claim is grounded in `docs/marketing/BRIEF.md`
> Verified Facts. Items marked `[UNVERIFIED — Leader confirm]` are not in that table.

---

## One-liner

Two calm, privacy-respecting logic games for iPhone and Mac, built solo from a single
Swift 6 codebase.

## Short descriptions

### Sudoku — 50 words

Sudoku is a calm logic game for iPhone and Mac. Play Daily ranked puzzles or untimed
Practice, with progress synced through your own iCloud and Game Center leaderboards. No
third-party tracking. Free, with an optional one-tap Remove Ads purchase. Seven languages,
one native SwiftUI codebase across both platforms.

### Sudoku — 100 words

Sudoku is a deliberately calm logic game for iPhone and Mac. Choose Daily puzzles ranked on
Game Center — including daily leaderboards — or play untimed Practice rounds at your own
pace. Saves and records follow you across devices through your own iCloud, with no account
beyond it. The app embeds no third-party analytics SDK; the only outside services are
Apple's own App Store Analytics, MetricKit, and Game Center. It is free to play with a
single removable banner, and a one-time Remove Ads purchase clears it permanently.
Localized in seven languages, it runs natively from one SwiftUI codebase on iPhone and Mac.

### Minesweeper — 50 words

Minesweeper is the classic, kept calm, for iPhone and Mac. Play Beginner, Intermediate, or
Expert with a first-tap-safe board and per-difficulty daily leaderboards on Game Center. No
third-party tracking. Built from the same Swift 6 codebase as its sibling Sudoku, sharing a
common app shell across both platforms.

### Minesweeper — 100 words

Minesweeper is the classic mine-finding puzzle, kept deliberately calm, for iPhone and Mac.
Play Beginner, Intermediate, or Expert difficulties on a first-tap-safe board, with
per-difficulty daily leaderboards live on Game Center. It carries the same privacy posture
as its sibling Sudoku: no third-party analytics SDK, with Apple's own App Store Analytics,
MetricKit, and Game Center as the only outside services. Minesweeper is built from the same
Swift 6 codebase as Sudoku and shares a common navigation and settings shell, so the two
apps differ only where the gameplay genuinely differs. Localized in seven languages, native
SwiftUI on both platforms.

## Key facts

| | Sudoku | Minesweeper |
|---|---|---|
| Status | v2.3.5, App Store submission prep | v1, in build-out, not yet submitted |
| Platforms | iOS + macOS, native SwiftUI | iOS + macOS, native SwiftUI |
| Languages | 7 (zh-TW, en, ja, zh-CN, es, th, ko) | 7 (same set) |
| Game Center | Leaderboards + daily leaderboards | Per-difficulty daily leaderboards |
| iCloud | Full saves + records via CloudKit | Monetization state only (no game saves) |
| Monetization | Free; removable banner + one-time Remove Ads IAP | Ads planned, not yet live |
| Tracking | None third-party; Apple-only services | None third-party; Apple-only services |

## What's notable (portfolio / credibility angle)

- **Privacy-first by construction.** No third-party tracking SDK ships in either app. The
  only outside services are Apple's own: App Store Analytics, MetricKit, and Game Center. A
  `PrivacyInfo.xcprivacy` manifest is shipped.
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
  no third-party tracking.
- **Fair monetization.** Free to play with a single removable banner; one tap and one
  one-time purchase clears it for good.
- **Native on both screens.** One app, iPhone and Mac, real SwiftUI on each.

## Developer bio

Built solo by Wei18, an Apple-platform developer. The full source spec, architecture
decisions, and engineering methodology for both apps are public and have been since the
first commit.

## Boilerplate

Sudoku and Minesweeper are two calm, privacy-respecting logic games for iPhone and Mac,
built solo from a single Swift 6 codebase. Both keep a deliberately small footprint: no
third-party analytics, no accounts beyond the player's own iCloud, and no tracking. The
project is developed in the open as a portfolio of clean, modular Apple-platform
engineering.

## Contact

`[UNVERIFIED — Leader confirm]` — press/contact email, website, and App Store links to be
supplied.

## Assets available on request

`[UNVERIFIED — Leader confirm]` — list of screenshots, app icons, and device frames to be
confirmed once captured.
