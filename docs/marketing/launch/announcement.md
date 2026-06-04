# Launch Announcement (DRAFT)

> Draft for Leader/user review. Blog/email length, reusable across channels.
> Grounded in `docs/marketing/BRIEF.md` Verified Facts.

---

## Subject line / headline options

- A calm Sudoku for iPhone and Mac — now in App Store submission
- Two private puzzle games, one Swift codebase
- Sudoku, built calm and private

## Body

I'm releasing a Sudoku for iPhone and Mac.

It's a deliberately calm logic game. You can play Daily puzzles ranked on Game Center —
including daily leaderboards — or play untimed Practice rounds when you just want to think.
Your saves and records follow you across devices through your own iCloud, and there's no
account beyond it.

A few things I cared about while building it:

- **No tracking.** There's no third-party analytics SDK in the app. The only outside
  services are Apple's own — App Store Analytics, MetricKit, and Game Center.
- **Fair, simple monetization.** It's free, with a single removable banner. A one-time
  Remove Ads purchase clears the banner permanently. That's the whole story.
- **Native on both screens.** It runs on iPhone and Mac from one SwiftUI codebase, and it's
  localized in seven languages.

Under the surface, it's a single Swift 6 package with complete concurrency checking from the
first line of code, and the game engine is a Foundation-only core with no Apple-UI
dependencies. That same architecture composes a second app, Minesweeper — built from the
same codebase and sharing a common shell, so the two apps differ only where the gameplay
genuinely differs. Minesweeper isn't on the App Store yet; it's in build-out.

The whole project — the spec, the architecture decisions, and the engineering methodology —
has been public since the first commit. If you care about how it's built as much as how it
plays, that's all readable.

Sudoku is in App Store submission prep now.

Links: `[UNVERIFIED — Leader confirm App Store link + repo link + availability date]`

— Wei18
