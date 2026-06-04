# Product Hunt Launch — Sudoku (DRAFT)

> Draft for Leader/user review. Grounded in `docs/marketing/BRIEF.md` Verified Facts.
> Launching Sudoku first (v2.3.5, submission prep); Minesweeper not yet submitted.

---

## Tagline (≤60 chars)

`A calm Sudoku for iPhone and Mac, with no tracking`

(49 chars.)

Alternates:
- `Calm Sudoku for iPhone & Mac — private, no accounts` (51 chars)
- `A private, calm Sudoku for iPhone and Mac` (41 chars)

## Name / first line

Sudoku — Daily and Practice logic for iPhone and Mac.

## First comment (maker story)

Hi Product Hunt,

I built this Sudoku solo. The goal was a quiet, native puzzle game that respects your
attention and your data — and a codebase clean enough to stand as a portfolio piece.

A few specifics rather than adjectives:

- It runs natively on iPhone and Mac from one SwiftUI codebase — the Mac build is a real
  SwiftUI app, not Catalyst.
- There's no third-party analytics SDK. The only outside services are Apple's own: App
  Store Analytics, MetricKit, and Game Center. Your saves and records sync through your own
  iCloud; there's no account beyond it.
- It's free, with a single removable banner. A one-time Remove Ads purchase clears the
  banner permanently — that's the whole monetization story.
- Daily mode is ranked on Game Center, including daily leaderboards; Practice is untimed and
  unranked when you just want to think.
- It's localized in seven languages.

Under the hood it's a single Swift 6 package with complete concurrency checking from day
one, and the game engine is a Foundation-only core with no Apple-UI dependencies. The same
codebase composes a second app, Minesweeper, by sharing a common shell — that one isn't
submitted yet.

Happy to answer anything about the architecture, the privacy choices, or building two apps
from one core. Thanks for taking a look.

— Wei18

## Topics / tags

- iOS
- Mac
- Games
- Productivity `[UNVERIFIED — Leader confirm appropriate fit]`
- Privacy

## Gallery shot list (describe shots; do not create images)

1. **Hero — Daily board, iPhone.** A clean in-progress Daily puzzle on iPhone, calm palette,
   tagline overlaid: "A calm Sudoku for iPhone and Mac."
2. **Mac native.** The same app on Mac in a resizable window, showing it is a real SwiftUI
   Mac app rather than a stretched phone layout.
3. **Daily vs Practice.** The mode picker, captioned to explain ranked Daily versus untimed
   Practice.
4. **Game Center leaderboard.** A daily leaderboard view, captioned "Daily leaderboards on
   Game Center."
5. **Privacy panel.** A plain text/graphic slide listing the facts: no third-party tracking;
   Apple-only services; saves in your own iCloud.
6. **Remove Ads.** The banner + the one-time Remove Ads option, captioned "Free, with an
   optional one-tap Remove Ads."
7. **Seven languages.** A montage or list showing the seven supported locales.
8. **Architecture slide (portfolio angle).** A simple module diagram — Foundation-only core,
   shared shell, two apps — captioned "Built solo, Swift 6, source-public."
