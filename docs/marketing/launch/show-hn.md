# Show HN (DRAFT)

> Draft for Leader/user review. Engineering-story / portfolio piece, in HN's understated
> voice. Grounded in `docs/marketing/BRIEF.md` Verified + Architecture facts.

---

## Title (≤80 chars)

`Show HN: Two iOS/macOS puzzle games from one Swift 6 package, source-public`

(74 chars.)

Alternates:
- `Show HN: A modular Swift 6 codebase where a second game reuses the first's shell`
- `Show HN: Solo-built Sudoku and Minesweeper sharing portable Swift cores`

## Body

I've been building two small Apple-platform puzzle games — a Sudoku and a Minesweeper —
solo, in a single public Swift Package. The interesting part isn't the games; it's that the
second app exists mainly to prove the first app's architecture composes a new game without
copy-paste. The whole spec, decision logs, and methodology have been public since the first
commit.

Some of the engineering decisions:

- **One package, two thin apps.** Each app target holds only `@main`, Info.plist /
  entitlements / assets, and a DI composition root. Every screen, all the logic, and all the
  storage live in local SwiftPM packages.

- **Portable, Foundation-only cores.** `SudokuEngine` and `MinesweeperEngine` import only
  Foundation — no Apple UI frameworks — so the puzzle math is unit-testable in isolation and
  could in principle be lifted to another front-end. Dependencies point inward only; reverse
  imports are forbidden.

- **A shared shell, not a fork.** The navigation, settings, hub, and banner-slot surfaces
  were extracted into a `GameShellKit` shell that both apps consume, rather than duplicated.
  That's what makes "Minesweeper mirrors Sudoku except the board" a literal statement
  instead of a slogan. Where two games need the same domain target, names are game-prefixed
  to avoid module collisions; genuinely shared targets are named by function.

- **Swift 6 strict concurrency from day one.** Swift 6 language mode with complete
  concurrency checking, enabled from the first line rather than migrated to later.

- **Testing without live Apple services.** swift-testing for unit/integration, plus
  pointfreeco's swift-snapshot-testing with snapshot PNGs committed. CloudKit and Game
  Center sit behind protocol seams and are exercised through fakes, so the suite runs on a
  clean CI runner.

- **Tooling.** Xcode Cloud as the primary CI track, Tuist generating the Xcode project from
  a `Project.swift`, mise for tool versions, and gitleaks + lefthook on pre-commit. The repo
  carries no secrets; build-time-sensitive identifiers are injected at build, not committed.

On the product side, both games are deliberately calm and privacy-respecting: no
third-party analytics SDK, no account beyond the player's own iCloud, native SwiftUI on
both iPhone and Mac. Sudoku is free with a single removable banner and a one-time Remove Ads
purchase; Minesweeper isn't submitted to the App Store yet.

There's a second thread in the repo I'd be curious for feedback on: it's also a worked
record of running an AI Leader/Developer agent workflow on a real shipping iOS project, with
the dispatch contract and the per-session decision logs kept alongside the code.

Repo link: `[UNVERIFIED — Leader confirm public repo URL]`
App Store link (Sudoku): `[UNVERIFIED — Leader confirm; app is in submission prep, may not be live at post time]`

Happy to go into any of the architecture or testing choices.
