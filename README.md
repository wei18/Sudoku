English | [繁體中文](README.zh-Hant.md)

# Sudoku-spec

Two calm, privacy-respecting, cross-platform logic games — built in a single monorepo that doubles as a portfolio of (a) clean, modular **Swift 6** architecture and (b) a documented **human + Claude-agent engineering workflow**.

- **Sudoku** is the primary app (feature-complete; App Store submission in progress).
- **Minesweeper** is a second app that exists to prove the shared `GameShellKit` architecture composes a new game — it mirrors Sudoku in every layer except the gameplay screen.

Both run on **iPhone and Mac** from one codebase, sync through the player's own iCloud, and keep a deliberately small footprint: no first-party analytics, no accounts beyond iCloud, no tracking — with ads limited to a single, removable banner in the monetized builds.

> This repo has been **public since its first commit**. Every architectural decision, every review cycle, and the full collaboration methodology are readable in `docs/`, `meetings/`, and `.claude/skills/`. That openness is part of the point.

---

## The two apps

| | **Sudoku** (primary) | **Minesweeper** (second app) |
|---|---|---|
| One-liner | Daily & Practice logic for iPhone and Mac | The classic, made calm — for iPhone and Mac |
| Status | Feature-complete; v2.6 monetization (banner + Remove-Ads IAP); App Store submission in progress | Mirrors Sudoku across every layer except the board — built and tested; v2.6, App Store submission in progress |
| Modes | Daily (3 puzzles/day, global, leaderboard-ranked) + Practice (random, unranked) | Beginner / Intermediate / Expert, first-tap-safe |
| Cross-device | iCloud Private DB sync of saves + records | Settings + purchase state via iCloud; no saved-game flow yet |
| Platforms | iOS 26 / macOS 26, real SwiftUI Mac app (not Catalyst) | Same |

> **On "v2.6":** that's the **repo milestone**, and since the SDD-003 version sync (a3e80d7) it's also both apps' store version string — Sudoku *and* Minesweeper ship `CFBundleShortVersionString` **2.6.0**. Minesweeper's *first* App Store submission therefore goes out as 2.6.0, not 1.0: one synced version across the repo, the binaries, and ASC.

**Ethos (both apps).** No personal data is collected. No third-party analytics SDKs are embedded. Saves live in the player's own iCloud Private Database; Game Center submissions go to Apple. In the monetized builds the *only* third-party SDK is Google's banner-ad library, isolated to a single module — and the banner can be removed permanently with a one-time, non-consumable In-App Purchase.

---

## Why this repo is interesting

This is not a tutorial project. It is a real, public iOS codebase that carries two distinct stories side by side:

1. **A clean modular Swift 6 architecture** that was deliberately split so a *second* game could reuse the first's shell.
2. **A reproducible record of applying Claude agents to a shipping iOS project** — a Leader/Developer state-machine methodology, with the original decision logs preserved.

---

## Architecture

The codebase is two thin app shells over a set of local Swift Package Manager packages. Each app target holds only `@main`, Info.plist / entitlements / assets, and a DI composition root; all screens, logic, and storage live in packages.

```
Sudoku/                      # thin shell: @main + DI composition root
Minesweeper/                 # thin shell: @main + DI composition root (mirrors Sudoku)
Packages/
├── SudokuCoreKit/           # pure-Swift core: SudokuEngine + GameState (leaf, portable)
├── MinesweeperCoreKit/      # pure-Swift core: MinesweeperEngine + MinesweeperGameState (leaf)
├── TimeKit/                 # pure-Swift core: UTCDay date helpers + MonotonicClock (leaf, portable)
├── DeterminismKit/          # pure-Swift core: SplitMix64 / DeterministicRNG shared by both engines (leaf)
├── TelemetryKit/            # Logger + Tracking abstraction + TelemetryTesting fixtures
├── PersistenceKit/          # CloudKit persistence + PersistenceTesting
├── GameCenterKit/           # GameCenterClient + GameCenterTesting
├── RemindersKit/            # shared local-notification reminders (UserNotifications isolated to Live)
├── GameAudioKit/            # shared SFX / BGM / haptics audio engine (AVFoundation isolated to Live)
├── GameShellKit/            # GameShellUI — the navigation shell both apps share
├── SettingsKit/             # SettingsUI — the shared settings sections both apps mount
├── GameAppKit/              # shared app-composition layer: GameRootViewModel / GameRoot / ResumePill / ResumeCandidate
├── AppMonetizationKit/      # MonetizationCore/UI + AdsAdMob + IAPStoreKit2 (third-party SDK isolation)
├── SudokuKit/               # Sudoku-specific: PuzzleStore / SudokuUI / AppComposition
├── MinesweeperKit/          # Minesweeper-specific: MinesweeperUI / MinesweeperAppComposition
└── ASCRegisterKit/          # macOS-only dev CLI for App Store Connect ops (not in either app binary)
```

**Dependencies point inward only** (leaf cores ← shared kits ← per-app kits ← app target; reverse imports are forbidden — see [`docs/foundations.md §2`](docs/foundations.md)). A few principles hold the shape together:

- **Portable leaf cores.** `SudokuCoreKit` and `MinesweeperCoreKit` import only Foundation — no Apple frameworks — so the puzzle/engine math could be lifted to another front-end (an Android port is an explicit backlog item).
- **Restricted framework imports.** CloudKit lives only in `PersistenceKit`, GameKit only in `GameCenterKit`, UserNotifications only in `RemindersKit`'s Live files, and the Google Mobile Ads SDK only in `AppMonetizationKit/AdsAdMob`. Everything above consumes protocol seams, which keeps the UI and logic layers unit-testable and preview-able.
- **A shared shell, not copy-paste.** When Minesweeper needed the same navigation, hub, toast, and banner-slot surfaces, those were extracted into `GameShellKit` (`GameShellUI`) rather than duplicated, while the shared settings sections live in `SettingsKit` (`SettingsUI`). The second app reuses the shell and ships *only* its gameplay UI and the bits that genuinely differ — which is exactly why "Minesweeper mirrors Sudoku except the board" is a true statement, not a slogan.
- **Game-prefixed targets.** Where two games need the same domain target (each game has its own `GameState`), names are game-prefixed (`MinesweeperEngine`, `MinesweeperGameState`, `MinesweeperUI`) so the generated Xcode workspace has no module-name collisions; genuinely shared targets are named by *function* (`GameShellUI`).

---

## The AI-collaboration angle

The repo is also a working record of running Claude agents on a real iOS project. Three layers sit alongside the code:

- **`docs/`** — the spec layer. Product and technical design (`v1/`, `v2/`), the cross-version engineering foundations, and the methodology itself.
- **`meetings/`** — the raw, dated decision logs. These are the source of truth for *why* the docs look the way they do, including review rounds, rejected alternatives, and root-cause analyses.
- **`.claude/skills/`** — project-specific, reusable agent skills distilled from patterns that recurred (for example, the build-time secret-injection pattern for AdMob identifiers).

The collaboration model is a **Leader / Developer state machine**, defined in [`docs/methodology.md`](docs/methodology.md):

- The **Leader** (the coordinating session) understands intent, writes and reviews documents, decomposes work, and dispatches tasks — but does not write implementation code.
- **Developer / Reviewer / Designer / Architect** sub-agents implement, review, and design against a precise dispatch contract (scope, docs to read, skills to invoke, return format, verification criteria), with their output gated by the Leader before anything reaches the user.

Work advances through explicit states — `GOAL_RECEIVED → PROPOSAL → RFC → USER_APPROVED → IMPL → CLOSED` — with a code-review step inserted whenever a change is large or touches sensitive modules. The methodology document also captures the recurring **patterns** and **anti-patterns** observed across phases, which is the part most directly reusable on another project.

---

## Repo map & reading order

1. [`docs/v1/design.md`](docs/v1/design.md) — what v1 does (§What) and how it's built (§How).
2. [`docs/v2/design.md`](docs/v2/design.md) — the v2 monetization layer (AdMob banner + Remove-Ads IAP + UMP / ATT).
3. [`docs/foundations.md`](docs/foundations.md) — cross-version engineering platform decisions (Swift 6, modularization, testing, CI, Logger, secrets).
4. [`docs/methodology.md`](docs/methodology.md) — the Claude-agent collaboration model, dispatch contract, and backlog routing.
5. [`meetings/`](meetings/) — the original per-session decision records behind everything above.

The full documentation map lives in [`docs/README.md`](docs/README.md); reusable agent skills live in [`.claude/skills/`](.claude/skills/).

> The sibling `Sudoku/` repo originally planned as a separate codebase was merged into this repo on 2026-05-17 — for a portfolio, a single readable unit beats jumping across repos.

---

## Tech facts

- **Language:** Swift 6 language mode with **complete** concurrency checking, from the first line of code.
- **Packaging:** Swift Package Manager — a small set of local packages, thin app targets.
- **Platforms:** iOS 26 / macOS 26 floor (chosen to use Liquid Glass APIs); the Mac build is a real SwiftUI app, not Catalyst.
- **Testing:** [swift-testing](https://github.com/swiftlang/swift-testing) for unit/integration tests (no XCTest) plus [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing); CloudKit and Game Center are exercised through protocol fakes so the suite runs on a clean CI runner.
- **Apple services:** CloudKit (private-DB save/record sync) and Game Center (recurring daily leaderboards + achievements, Sudoku).
- **CI / tooling:** Xcode Cloud as the primary CI track (PR / Main / Release workflows), advisory GitHub Actions for lint/link/metadata, [Tuist](https://tuist.io) generating the umbrella `Game` Xcode project from `Project.swift`, and [mise](https://mise.jdx.dev) as the version + task source of truth, with lefthook + gitleaks pre-commit hooks.
- **Monetization (v2, Sudoku):** a single removable AdMob banner and a one-time Remove-Ads IAP, with UMP consent and ATT, all isolated inside `AppMonetizationKit`.

---

## Security posture

This is a public spec repo and has been from day one. No secret, PII, or identifiable player data may appear in any commit — enforced by a gitleaks pre-commit hook, an Xcode Cloud post-clone secret scan, GitHub secret-scanning alerts, and a `.gitignore` blocklist. App-public-but-pre-launch-sensitive identifiers (such as AdMob IDs) are injected at build time rather than committed. The full policy is [`docs/foundations.md §7`](docs/foundations.md).
