# LinkedIn — Dev Story (DRAFT)

**Goal:** Portfolio / credibility
**Voice:** Developer, understated, specifics over superlatives
**Status:** DRAFT — nothing published. Leader/user review before posting.

Fact grounding cited inline as `[VF: <row>]` (Verified Facts table) or `[ARCH]` (Architecture facts) from `docs/marketing/BRIEF.md`.

---

## Variant A — Long (full dev story)

I shipped two Apple-platform games out of one Swift package — and the second one was mostly an exercise in *not* writing new code.

Sudoku is the primary app: iPhone and Mac from a single codebase, a real SwiftUI Mac build, not Catalyst. [VF: Platforms] Minesweeper is the second app, and it exists to prove a point: that the architecture I split out for the first game could actually compose a new game. It mirrors Sudoku in every layer except the gameplay screen. [ARCH]

A few decisions I'd defend in a review:

— **Swift 6 language mode with complete concurrency checking, from the first commit.** [ARCH] Not migrated to later. Starting there forced the data-race questions up front instead of leaving them as a future tax.

— **Portable leaf cores.** The puzzle/engine math (`SudokuEngine`, `MinesweeperEngine`) imports only Foundation — no Apple UI frameworks — so the logic is unit-testable in isolation and could be lifted to another front-end. [ARCH]

— **A shared shell, not copy-paste.** Navigation, settings, the hub, toasts, the banner slot — those live in one `GameShellKit` that both apps consume. The second app ships only its board and the parts that genuinely differ. "Minesweeper mirrors Sudoku except the board" is a structural fact, not a tagline. [ARCH]

— **Restricted framework imports.** CloudKit lives only in the persistence module, GameKit only in the Game Center module, the Google ad SDK only in one ads module. Everything above consumes protocol seams, which is why the suite runs on a clean CI runner with no live Apple services. [ARCH]

— **Testing without XCTest.** swift-testing for units, swift-snapshot-testing with the PNGs committed, so UI regressions show up as a diff in review. [ARCH]

On the product side I kept the footprint deliberately small: no third-party analytics SDK, no accounts beyond the player's own iCloud, no tracking. [VF: Privacy] Sudoku is free with a single removable banner and a one-time Remove Ads purchase — not ad-free, removable. [VF: Monetization] Saves and records sync through the player's own iCloud. [VF: iCloud sync]

The whole repo has been public since the first commit — architecture docs, review cycles, and the decision logs are all readable. If you want to see how it's actually wired rather than how I describe it, that's the more honest artifact.

Solo-built. [ARCH] Happy to talk through any of the boundaries above.

#SwiftUI #Swift6 #iOSDev #SoftwareArchitecture #SwiftPackageManager

---

## Variant B — Short (feed-skim version)

Two Apple-platform games, one Swift package — and the second app was mostly an exercise in *not* writing new code.

Sudoku is primary (iPhone + Mac, real SwiftUI Mac, not Catalyst). [VF: Platforms] Minesweeper is the second app, built to prove the architecture composes: it mirrors Sudoku in every layer except the board. [ARCH]

Decisions I'd defend:
— Swift 6 + complete concurrency checking from the first commit [ARCH]
— Portable leaf cores (Foundation only, no Apple UI) [ARCH]
— A shared `GameShellKit`, not copy-paste — the second app ships only its board [ARCH]
— swift-testing + committed snapshot PNGs, suite runs on a clean runner via protocol seams [ARCH]

Privacy-first product to match: no third-party analytics, no accounts beyond iCloud, no tracking. [VF: Privacy] Free with a removable banner + one-time Remove Ads — removable, not ad-free. [VF: Monetization]

Public since the first commit, so the wiring is readable, not just describable. Solo-built.

#SwiftUI #Swift6 #iOSDev #SoftwareArchitecture

---

## Notes for Leader
- App Store / TestFlight links intentionally omitted — Sudoku is in submission prep, Minesweeper not yet submitted. [VF: Status] Add a link only once live. `[UNVERIFIED — Leader confirm]` whether a public store/TestFlight URL exists yet.
- Repo URL intentionally not hardcoded here. `[UNVERIFIED — Leader confirm]` the canonical public repo URL to append as the post's link/comment.
- No userbase / ranking / award numbers used (Do-Not-Claim).
