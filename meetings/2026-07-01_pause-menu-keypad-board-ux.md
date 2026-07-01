# 2026-07-01 — unified pause menu, 3×3 keypad, in-board highlighting

Continuation of the sim-UX-audit fix stream. Arc: fix the remaining audit items
(#647/#649) → the owner reframed the leave-dialog fix into **merging Close+Pause into
one pause menu** → several design rounds to match the owner's actual mental model →
then a two-part Sudoku gameplay-UX pass (**3×3 keypad** + **in-board highlighting**),
run as an agent-team design phase before implementation.

## Shipped (all merged to main)

| PR | What | Closes |
|---|---|---|
| #657 | 44pt pause hit target + MS revealed-cell grid border | #647, #649 |
| #658 | Sudoku iPhone digit strip → **3×3 grid** + per-key remaining-count (==1 sage / ==0 dim-disable) | — |
| #659 | CI: relax PR-title `subjectPattern` `^[a-z]` → `^[a-z0-9]` (allow digit-first subjects) | — |
| #660 | **unified pause + leave menu** (both apps) — one button → full-screen mask + centred "Leave Game?" card + Resume/Leave | (supersedes #648) |
| #661 | in-board **peer + same-digit highlighting** (Sudoku) | — |

Also closed **#648** (Leave dialog had no visible Cancel) — resolved by #660: the custom
pause card has an explicit visible Resume(=cancel) alongside Leave, so it no longer
depends on iOS 26's `.confirmationDialog` render (which drew only "Leave").

## The pause menu — 4 design rounds, owner-driven

The owner asked to merge the board's Close(✕) and Pause(‖) into one button whose menu
offers Resume + Leave. My first cut over-built it (a new full-blur "Game Paused" card).
It took the owner sending **a screenshot of the actual current leave dialog + "just add
a Resume"** to land the intent. Final shape (both apps, shared `PauseOverlayView`):

- One button → pauses (timer frozen) → **full-screen `.ultraThinMaterial` mask** (original
  pause blur, board hidden = anti-cheat) with a **screen-centred** "Leave Game?" card
  (`leave.game.title`), **Resume** (`.borderedProminent`, brand accent — sage-green Sudoku
  / steel-blue MS) + **Leave** (`.bordered` destructive red). Tap the mask = Resume.
- Removed the ✕ button, the leave `.confirmationDialog`, and the dead Epic-2 leave-VM
  plumbing (deleted 4 orphaned tests). Top **chrome timer hidden while paused** so the
  mask isn't pierced. The overlay was moved from the board-square frame up to the
  board-body `.overlay` so the mask fills the whole screen and the card is screen-centred.
- A **UI Designer review pass** (owner-requested) then tightened it: Resume prominent (not
  equal-weight), card `maxWidth 340`, timer-bleed fixed. Kept the iCloud-explicit save copy
  (#616 decision) against the reviewer's simplify suggestion.

## Agent-team design phase for B (keypad + board UX)

Ran two design agents in parallel before implementing: one proposed the **3×3 keypad**
(remaining-count per key, notes-mode wash, SE/AX5 fit), one audited **in-board UX** against
the actual code (peer-highlight, same-digit, auto-advance, notes-auto-removal, haptics) and
separated already-shipping from gaps. Owner picked: keypad-with-remaining-count (last-one
sage), peer + same-digit highlight (deferred auto-advance / notes-removal). Then dispatched
implementation. Highlighting uses a new `cell.sameDigit` token (vivid leaf-green) distinct
from the pre-existing-but-unwired `cell.highlighted` (peer) and `cell.selected`; priority
`error > selected > sameDigit > peer > given > base`; `cell()` extracted to
`BoardView+Highlighting.swift` to stay under the 400-line `file_length` ceiling.

## Lessons (saved to memory)

- **Ground a UX redesign in the ACTUAL current screen (a real screenshot), and default to
  "keep the screen + add the one thing."** An abstract ASCII mock approved in a question let
  the owner and me picture different things; only their screenshot converged us.
  (`ground-ux-redesign-in-actual-screen`)
- **Before `git worktree remove -f -f`, check for uncommitted work and commit/salvage it
  first.** I force-removed a stalled agent's worktree in the same cleanup batch and lost its
  partial (uncommitted) B2 work; had to redo it. Grab the commit first, salvage second.
  (`check-worktree-before-force-remove`)
- **Don't trust a subagent's "tests pass"** — a prior branch's DEBUG hook had a real compile
  error (`onChange(of:)` needing `Equatable`) masked by an incremental build; only a clean
  build surfaced it. Re-run the gate; clean-build before debugging sim/code mismatches.
- **PR-title subject** can now start with a digit (`^[a-z0-9]`); still never an uppercase
  letter. Fixed the recurring CI friction at the source (#659), not by contorting titles.
- **Verify shared-code changes on BOTH apps** (`verify-changes-on-both-apps`) — the pause
  menu is one shared `PauseOverlayView`; sim-checked Sudoku (green) and confirmed MS (blue).

## Residual (harmless / follow-up)
- Orphaned `game.paused` L10n key (added then title switched to `leave.game.title`);
  `scan:l10n` doesn't flag unused keys, so it's non-blocking — clean up in a later pass.
- `interactive-sim-ux-audit/scripts/` kept **local, uncommitted** per owner (reusable idb
  drive harness).
