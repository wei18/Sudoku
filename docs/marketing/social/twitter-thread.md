# X / Twitter — Engineering Thread (DRAFT)

**Goal:** Portfolio / credibility (thread) + a user-acquisition single-post variant
**Voice:** Developer, dry, concrete. ≤3 hashtags per post.
**Status:** DRAFT — nothing published. Leader/user review before posting.

Fact grounding cited inline as `[VF]` / `[ARCH]` from `docs/marketing/BRIEF.md`. Privacy framing = Path B (no absolute "no tracking").

---

## Thread (portfolio) — 8 posts

**1/**
I shipped two Apple-platform games from one Swift package — and the second app was mostly an exercise in *not* writing new code.

Here's how the architecture made that possible. 🧵

**2/**
Sudoku is the primary app: iPhone and Mac from one codebase. A real SwiftUI Mac build, not Catalyst. [VF: Platforms]

Minesweeper is the second app — it exists to prove the shared shell composes a new game. It mirrors Sudoku in every layer except the board. [ARCH]

**3/**
Swift 6 language mode with *complete* concurrency checking — from the first commit, not a later migration. [ARCH]

Starting strict forces the data-race questions up front instead of leaving them as a future tax.

**4/**
Portable leaf cores: `SudokuEngine` and `MinesweeperEngine` import only Foundation. No Apple UI frameworks. [ARCH]

The puzzle/engine math is unit-testable in isolation and could be lifted to another front-end.

**5/**
A shared `GameShellKit`, not copy-paste. Navigation, settings, hub, toasts, banner slot — one shell, both apps. [ARCH]

The second app ships only its board + what genuinely differs. "Mirrors except the board" is structural, not a slogan.

**6/**
Restricted framework imports: CloudKit only in persistence, GameKit only in Game Center, the ad SDK only in one ads module. [ARCH]

Everything above consumes protocol seams — so the suite runs on a clean CI runner with no live Apple services.

**7/**
Testing without XCTest: swift-testing for units + swift-snapshot-testing with the PNGs committed. [ARCH]

UI regressions show up as an image diff in review.

**8/**
Product footprint to match: no first-party analytics SDK profiling you, no account beyond your iCloud. [VF: Privacy]

Sudoku is free with a removable banner + one-time Remove Ads — removable, not ad-free; tailored ads are opt-in via ATT. [VF: Monetization]

Public since the first commit. Solo-built. https://github.com/wei18/Sudoku

#Swift6 #iOSDev #SwiftUI

---

## Single-post variant (user-acquisition)

A calm Sudoku for iPhone and Mac. No account beyond your own iCloud; no first-party analytics profiling you. [VF: Privacy]

Saves and records sync through iCloud; daily leaderboards via Game Center. [VF: iCloud sync, Game Center]

Free, with an optional one-tap Remove Ads. https://apps.apple.com/app/id6771248206 [VF: Monetization]

#Sudoku #iOS

---

## Notes for Leader
- Repo: https://github.com/wei18/Sudoku — Sudoku on the App Store (v2.5): https://apps.apple.com/app/id6771248206 (both filled). Minesweeper (v1.0) not yet submitted; its page (live once approved) is https://apps.apple.com/app/id6775733519 — omit until you want to surface MS. [VF: Status]
- Hashtag counts kept ≤3/post.
- No userbase / ranking / award numbers (Do-Not-Claim). Sudoku framed as removable banner with opt-in tailored ads, never absolute "no tracking" or "ad-free".
