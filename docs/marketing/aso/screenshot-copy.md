# Screenshot Caption Copy (DRAFT)

**Status:** Caption + frame-direction drafts only. No images produced. Captions ground in
BRIEF Verified Facts (privacy framing = Path B); nothing claims a feature the BRIEF forbids.
Tone: calm, understated, no superlatives, no emoji (brand contract). Each caption is a short
overlay headline + an optional one-line subhead, sized for legibility on a phone screenshot.

**How to read each frame:** *Frame* = what the device screenshot shows. *Overlay* = the
caption text rendered on the marketing background. *Backs* = the Verified Fact it relies on.

**Caption length guidance:** overlay headline ≤ ~5 words so it reads at thumbnail size;
subhead ≤ ~8 words. These are caption text, not ASC fields — no hard char cap, but shorter
wins on conversion.

---

## SUDOKU — 6-frame story
Narrative arc: hook (Daily) → core loop → the calm/feature payoff → privacy → Mac → close.

### Frame 1 — Hero / Daily (the hook)
- **Frame:** Home screen showing the three Daily puzzles (Easy / Medium / Hard) with the
  "today" date, clean sage-and-warm-paper UI.
- **Overlay headline:** `Three new puzzles. Every day.`
- **Subhead:** `Same three for everyone — then the leaderboard.`
- **Backs:** Daily leaderboards live (Verified); description "three new puzzles… same three
  for every player."

### Frame 2 — Daily board in play (core loop + live errors)
- **Frame:** An active Daily board mid-solve, one cell showing a live red error highlight,
  pencil notes visible in another cell.
- **Overlay headline:** `Catch mistakes as you make them.`
- **Subhead:** `Pencil notes and live error highlighting.`
- **Backs:** Verified features — pencil notes (9 candidates), live error highlighting.

### Frame 3 — Practice mode (no-pressure payoff)
- **Frame:** Practice mode picker / a practice board with no clock chrome.
- **Overlay headline:** `Or just practice. No clock.`
- **Subhead:** `Unlimited boards. Nothing to live up to.`
- **Backs:** Verified — Practice mode: random boards, no scoring, no ranking.

### Frame 4 — Privacy (the differentiator)
- **Frame:** A calm graphic — an iCloud lock over the app UI — plus a short, honest line of
  text (the caption below), NOT a "no tracking" badge.
- **Overlay headline:** `Private by design.`
- **Subhead:** `No account beyond your iCloud. Tailored ads are opt-in.`
- **Backs:** Verified (Path B) — no first-party analytics SDK profiling you; saves in your own
  iCloud Private Database; ads may use an ad identifier for relevance only with permission
  (decline → ads still serve), or remove ads entirely.
- **Guard:** Do NOT say "No tracking" / "ad-free" — Sudoku has a removable banner and uses
  the ad identifier (with permission) for ad relevance. The honest hooks are "no account
  beyond your iCloud" and "tailored ads are opt-in (and removable)."

### Frame 5 — Mac-native (cross-platform)
- **Frame:** The Mac app in a resizable window, menu bar visible, a board mid-solve;
  optionally a small inset of the same board on iPhone.
- **Overlay headline:** `A real Mac app. Not Catalyst.`
- **Subhead:** `Keyboard, menus, windows — and your board follows.`
- **Backs:** Verified — iOS + macOS SwiftUI; listing's "real SwiftUI Mac app, not Catalyst";
  iCloud save sync (Sudoku).

### Frame 6 — Close / Remove Ads + languages
- **Frame:** Clean home screen, small Remove Ads affordance, a row of 7 language flags or
  the localized word for "Sudoku."
- **Overlay headline:** `Free. One-tap Remove Ads.`
- **Subhead:** `Seven languages. Family Sharing included.`
- **Backs:** Verified — free; one-time non-consumable Remove Ads (Family Sharing); 7 locales.
- **Guard:** Frame Remove Ads as optional, never imply the app is paid or ad-free by default.

---

## MINESWEEPER — 5-frame story
Narrative arc: hook (first-tap-safe) → the three classics → daily/ranking → privacy → Mac.
**No continuity/resume frame** (no saved-game flow). **No game-sync frame** (only
monetization state syncs).

### Frame 1 — Hero / First-click safety (the hook)
- **Frame:** A board just after the opening tap — a large safe opened region, no explosion;
  calm UI.
- **Overlay headline:** `The first tap is always safe.`
- **Subhead:** `Mines are placed after you open. No move-one losses.`
- **Backs:** Verified — "the first tap is always safe; mines placed after first reveal."

### Frame 2 — Three classic difficulties (core)
- **Frame:** Difficulty picker or a side-by-side of Beginner / Intermediate / Expert boards.
- **Overlay headline:** `Beginner to Expert.`
- **Subhead:** `9×9 · 16×16 · 16×30. The classics, exactly.`
- **Backs:** Verified — three classic difficulties with those grid/mine specs.

### Frame 3 — Daily + Game Center (the differentiator)
- **Frame:** A daily board, with a Game Center per-difficulty daily leaderboard panel.
- **Overlay headline:** `A daily board. A daily rank.`
- **Subhead:** `Per-difficulty daily leaderboards.`
- **Backs:** Verified — per-difficulty daily leaderboards live; "a daily set of boards."

### Frame 4 — Privacy
- **Frame:** Calm iCloud-lock / privacy graphic over the board, with the honest line below.
- **Overlay headline:** `Private by design.`
- **Subhead:** `No first-party analytics profiling you.`
- **Backs:** Verified (Path B) — no first-party analytics SDK profiling you; "no CRM, no
  backend of our own." (MS ads not yet live, so no ad-identifier line is needed here yet.)
- **Guard:** Do NOT claim "syncs your games" (only monetization state syncs for MS); do NOT
  say "No tracking" / "ad-free" as an absolute — see flag on MS ad status below.

### Frame 5 — Mac-native + close
- **Frame:** Mac app in a resizable window, right-click flagging shown; 7-language hint.
- **Overlay headline:** `A real Mac app. Right-click to flag.`
- **Subhead:** `Tap to reveal, long-press to flag. Seven languages.`
- **Backs:** Verified — macOS SwiftUI, not Catalyst; flag via long-press / right-click;
  7 locales.

---

## Cross-cutting notes
- **Localization:** the en captions above are the source; zh-TW (and the other 5 locales)
  should be hand/reviewed-translated per the localization convention, NOT machine-dumped —
  the calm tone must survive translation. The `九宮格`/`掃雷` register matters.
- **Frame 1 carries the most conversion weight** — it is what shows in search results. Both
  hooks (Sudoku "three new puzzles every day"; MS "first tap always safe") are Verified and
  category-rare. Good first frames.
- **No metrics on any frame** — no "millions of players," no ratings, no awards (none to cite).

## Flags
- `[UNVERIFIED — Leader confirm]` Minesweeper monetization state on screenshots: BRIEF says MS
  ads are "planned, not yet live," but the MS listing copy already describes a removable
  banner + Remove Ads IAP. The privacy frame avoids the banner question; confirm whether a
  Remove Ads frame should appear for MS v1.0 at all (consistency with the live monetization
  state at submission).
- `[UNVERIFIED — Leader confirm]` exact Game Center daily-leaderboard UI for the MS Frame 3
  panel (visual reference, not a copy claim).
