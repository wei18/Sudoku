# First-Run Guidance — Design Proposal (FIRST-RUN)

**Status:** PROPOSAL (design spec, not yet implemented)
**Date:** 2026-07-11
**Author:** Developer/Designer subagent → Leader review
**Companion:** `meetings/2026-07-11_design-db-uiux-audit.md` (audit findings this
spec responds to)

---

## 1. Problem

Both apps cold-launch straight to `HOME` with zero onboarding. This audit
round confirmed the gap is total, not partial:

- A repo-wide search for onboarding/tutorial/coachmark/tooltip/firstRun turns
  up **no first-run UI and no "have I launched before" flag anywhere** —
  `resumeCandidate == nil` only means "no saved game," not "first launch"
  (`Packages/GameAppKit/Sources/GameAppKit/GameHomeView.swift:69-78`).
- Minesweeper's reveal/flag mode toggle — the one control whose meaning is
  least self-evident from its icon alone — has exactly one piece of
  explanatory text in the whole app, and it's VoiceOver-only
  (`accessibilityHint`); sighted first-time users get zero visual
  affordance for what tap-mode even is
  (`Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperBoardView.swift:596-618`).
- Neither `SUD-BOARD` nor `MS-BOARD` has a teaching layer at mount: Sudoku
  drives straight to `.playing`; Minesweeper mounts in `.idle`
  (first-click-safe) but still shows nothing beyond the bare board.
- This audit's own `HOME` finding (N1 in the findings report) — four
  equal-weight mode cards with no first-time recommended entry point — is a
  related but separate gap; this proposal's primary path deliberately leaves
  `HOME` untouched (see §3) and handles onboarding entirely inside the board.

Net effect: Minesweeper's tap-mode/chord mechanics in particular are not
self-explanatory to a new player, and there's no repo precedent for how a
"first time" state would even be represented.

## 2. Evidence from pattern database

- **Reject — long onboarding funnels.** Headway (41 screens), Lifesum (31),
  and Cleo (27) all use long pre-app-value funnels to drive subscription
  conversion. That volume and intent are the opposite of this app's "calm
  graph paper" brand and its no-subscription monetization stance — explicitly
  not a fit, ruled out.
- **Adopt — Zip's "watching a quick guide" pattern.** A ≤3-screen guide,
  skippable, delivered close to the real task, that gets a user to
  understanding the core interaction fast. This shape (not the funnel shape)
  is what this proposal borrows.
- **Adopt — ChatGPT's empty-state / coach-mark pattern.** Rather than a
  separate onboarding flow, guidance is layered directly on top of the real,
  functioning screen the user is about to use. No detour screen to skip past.
- **Vocabulary precedent — Duolingo's `coach-mark-card` element** (present in
  the design-db element vocabulary for Duolingo's add-a-widget flow).
  Confirms "coach-mark overlay on a real screen" is a named, recognized
  pattern in the database, not a bespoke invention for this spec.

## 3. Proposed solution

### 3.1 Primary path — board coach-mark overlay (recommended)

First entry into `SUD-BOARD` or `MS-BOARD` (per-app, tracked independently)
shows a 3-point coach-mark sequence layered over the live board — not a
separate screen, not inserted into `HOME`. `HOME` gets zero new steps; cold
launch stays exactly as fast as it is today.

**Sudoku (3 points, single sentence each):**
1. Point at the grid → *"Tap a cell to select it."*
2. Point at the digit pad → *"Tap a number to fill it in."*
3. Point at the pencil toggle → *"Pencil mode adds small notes instead of a final answer."*

**Minesweeper (3 points, single sentence each) — higher priority than Sudoku,
since its mechanics are less self-evident:**
1. Point at the reveal/flag mode toggle → *"Switch between digging and
   flagging mines."*
2. Point at the grid → *"Press and hold a revealed number to auto-clear its
   safe neighbors."* (chord)
3. Point at any numbered cell → *"A number tells you how many mines touch
   that cell."*

**Mechanics:**
- Each point renders as a spotlight/callout anchored to the real element
  (matches the coach-mark pattern above) with a single line of copy and a
  "Next" affordance; the last point's affordance reads "Got it."
- A persistent "Skip" control is available on every point of the sequence,
  not just the first — dismisses the whole sequence immediately.
- State: a `hasSeenFirstRunGuide` flag, stored **per app** (independent
  Sudoku/Minesweeper flags — consistent with the copy-paste-adapt model both
  apps already follow; see hard constraint in §6). Modeled on the existing
  `LastSelectionStore` shape (`Packages/GameAppKit/Sources/GameAppKit/LastSelectionStore.swift`)
  — a small `UserDefaults`-backed struct with an injectable `UserDefaults`
  instance for testability — but storing a `Bool` "seen" flag rather than a
  `String` last-selection value. Once set, the sequence never shows again on
  that install (no re-offer, no Settings toggle to replay it in v1 — replay
  is a v-next nice-to-have, not required for acceptance).
- The sequence mounts once the board's real content is already interactive
  underneath it — it is an overlay on a live screen, not a blocking modal
  that must resolve before play starts. A user who taps through the board
  around the coach-marks (rather than using Next/Skip) is allowed to; the
  overlay does not trap input.

### 3.2 Platform behavior

- **iOS/iPad:** overlay renders inside the board's existing `fullScreenCover`
  presentation (`SUD-BOARD`/`MS-BOARD` per `docs/screen-contracts.md`), so it
  is naturally full-bleed with no extra plumbing.
- **macOS:** the board renders pushed into the `NavigationSplitView` detail
  column, clamped to 960pt and centered (`BoardView.swift:198-213`,
  `MinesweeperBoardView.swift:354-374`). The coach-mark overlay must be
  scoped to that same detail-column frame, not the full window — anchoring a
  spotlight to a grid element inside a 960pt-clamped column and then
  painting a full-window scrim would visually mismatch the board's own
  bounds. This mirrors the fix direction in this audit round's M3 finding
  (macOS overlay-mask escape): any new overlay on `BoardView` must be scoped
  to the same container the board itself is scoped to, not assumed to be
  window-wide by default.

### 3.3 States, transitions, tokens

- **Entry:** appears automatically on first mount only if the per-app
  "seen" flag is unset; never appears again after Skip or "Got it."
- **Transition:** point-to-point advance is a simple crossfade/reposition of
  the spotlight + callout, **350ms max**, matching the existing motion budget
  used elsewhere in the design system (e.g. `CompletionView` hero stat
  reveal is 350ms) — no new motion vocabulary introduced.
- **Reduce Motion:** gate the crossfade/reposition behind
  `@Environment(\.accessibilityReduceMotion)` exactly like
  `ReminderPrimerSheet`'s `DeclineButtonStyle` already does
  (`Packages/SettingsKit/Sources/SettingsUI/Reminders/ReminderPrimerSheet.swift:92,104-105`)
  — when true, points advance with no animation, final state only.
- **Tokens:** callout background uses `surface.elevated`; callout text uses
  `text.primary`/`text.secondary`; the spotlight ring uses `accent.primary`
  — **not** any `difficulty.*` token (those are reserved for
  difficulty-signaling only, per `design-system.md` §Color tokens > Difficulty).
  Spacing inside the callout uses the existing 4pt `@ScaledMetric` ladder
  (`spacingMd`/`spacingLg` per `design-system.md` §Spacing scale). Callout
  copy uses `.callout` weight `.medium` for the single sentence (matches the
  design system's "Button label" role, the closest semantic fit for a short
  imperative instruction) and `.caption` for "Skip"/"Next"/"Got it."
- **No confetti, no celebratory motion on "Got it"** — sequence simply
  dismisses; this is onboarding, not an achievement, per the brand's no-
  celebration constraint.

### 3.4 Alternative — Home "How to play" card (not recommended, offered for owner choice)

Instead of (or in addition to) the board overlay, `HOME` could show a
dismissible "How to play" card on first launch that opens a 3-screen sheet
covering the same content as §3.1's points, front-loaded before any play.
This is closer to design-db's Zip precedent in literal screen count but adds
a step before `HOME`'s existing zero-friction cold start, and duplicates
content the board overlay already delivers in-context. Listed as an
alternative per the outline's instruction, not as this spec's recommendation.

## 4. Acceptance checklist

- [ ] First launch of each app → open a board (Daily or Practice) → the
      correct per-app 3-point sequence appears automatically exactly once.
- [ ] Reaching "Got it" or tapping "Skip" at any point dismisses the whole
      sequence and persists the per-app "seen" flag; relaunching the app (or
      opening another board) never shows it again.
- [ ] Skip is reachable from every point in the sequence, not only the first.
- [ ] Completing the full sequence, start to finish, costs no more than 3
      extra taps beyond what starting a board already costs today (one tap
      per coach-mark point to advance, or a single Skip tap).
- [ ] `HOME` renders identically to today — no new step, no new element, no
      layout change — regardless of first-run state.
- [ ] With Reduce Motion on, the sequence advances with no crossfade/
      reposition animation — final state only, each transition instant.
- [ ] VoiceOver can read each coach-mark point in order as a distinct
      element with its instruction text, and can activate Skip/Next/"Got it"
      as ordinary accessible controls.
- [ ] On macOS, the overlay's spotlight and scrim are visually scoped to the
      960pt-clamped detail column, not the full window (sidebar unaffected).
- [ ] Sudoku's and Minesweeper's "seen" flags are independent — completing
      or skipping one app's sequence has no effect on the other app's
      first-run state.

## 5. Prerequisites

- **A per-app persisted boolean flag store is buildable with existing
  infrastructure.** Verified ✓ — `LastSelectionStore`
  (`Packages/GameAppKit/Sources/GameAppKit/LastSelectionStore.swift`) is a
  live, tested precedent for a small `UserDefaults`-backed preference struct
  with an injectable `UserDefaults` instance; a boolean "seen" variant
  follows the identical shape.
- **A reduce-motion gate pattern already exists in the codebase to copy.**
  Verified ✓ — `ReminderPrimerSheet.swift:92,104-105` gates its button-style
  animation behind `@Environment(\.accessibilityReduceMotion)` today.
- **The board can host an overlay without redoing the full-screen-before-
  overlay layout fix.** Verified ✓ — `SUD-BOARD`/`MS-BOARD` already apply
  `.frame(maxWidth:.infinity, maxHeight:.infinity)` before attaching their
  Pause/Completion overlays (#388/#610), which is exactly the same
  full-bleed-then-overlay shape a coach-mark overlay needs.
- **macOS overlay scoping to the detail column is not yet solved in the
  codebase.** Unconfirmed ? — this audit's M3 finding shows the *existing*
  Pause/Completion overlays leak past the detail column on macOS today. This
  proposal's §3.2 macOS behavior assumes that scoping problem gets solved
  (as recommended in M3's fix direction) or is solved consistently for any
  new overlay introduced here. If M3 is deferred, this proposal's macOS
  coach-mark would inherit the same leak — flagged for the owner, not
  silently assumed away.

## 6. Open questions for owner

1. Primary (§3.1, board overlay) vs. alternative (§3.4, Home "How to play"
   sheet) — which should ship? This spec recommends the primary path.
2. Should there be any Settings-level "Replay guide" affordance in v1, or is
   "never shows again after first dismissal" acceptable for the initial
   ship (this spec assumes the latter, but it's a real product choice, not
   a design-forced one)?
3. Confirm the exact coach-mark copy strings above are final, or need a
   copy pass before the seven-locale localization work begins.

---

## 7. Scope note

Per the approved outline's hard constraints, this proposal does not touch
`HOME` layout (N1 in the findings report is a separate, unaddressed finding),
does not introduce any shared Sudoku/Minesweeper onboarding infrastructure
(each app's coach-mark content and flag are implemented per-app, copy-paste-
adapt, matching the settled architecture stance), and introduces no
celebratory motion, subscription gating, or monetization surface of any kind.
