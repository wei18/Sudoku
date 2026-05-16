# Design System — Sudoku v1

Top-level visual + interaction tokens shared by all 8 Views. All per-View files reference token names from this document.

---

## Brand essence

**"Calm graph paper, lit by daylight."**

Sudoku is a focus exercise, not a slot machine. The aesthetic borrows from Japanese puzzle-paper newspapers (`日本パズル雑誌`) — warm off-white surfaces, restrained ink-tone strokes, generous whitespace, one accent color used sparingly to mark intent (the active row/col/box). No celebrations, no confetti, no skeuomorphic shadows. Liquid Glass is reserved for navigation chrome and modal hero areas — it earns its place only where the surface is *above* content, never on the board itself.

Justification: the user spends 5–25 min on a single puzzle. Visual fatigue compounds. HIG (Designing for iOS — "Clarity") and a body of typography research (Lupton, *Thinking with Type*) converge on the same answer: low chroma, high contrast text, restrained accent.

---

## Color tokens

Semantic names. Hex pairs are `light / dark`. All values are sRGB.

### Surfaces

| Token | Light | Dark | Usage |
|---|---|---|---|
| `surface.background` | `#FAF8F3` | `#15171A` | Window / scene root |
| `surface.primary` | `#FFFFFF` | `#1E2024` | Cards, sheets, list rows |
| `surface.elevated` | `#FFFFFF` | `#262A30` | Sheets above other sheets, popovers |
| `surface.glass` | system material | system material | `.glassEffect()` chrome surfaces only |

### Board cells

| Token | Light | Dark | Usage |
|---|---|---|---|
| `cell.base` | `#FFFFFF` | `#1E2024` | Empty / default cell |
| `cell.prefilled` | `#EFEBE2` | `#2A2D33` | Givens (puzzle clues, immutable) |
| `cell.userFilled` | `#FFFFFF` | `#1E2024` | User-entered digit (same as base; differentiated by text color) |
| `cell.highlighted` | `#E8F1FB` | `#1F3145` | Same row / col / box as selected |
| `cell.selected` | `#D6E7F8` | `#2A4868` | The single tapped cell |
| `cell.error` | `#FBE3E1` | `#4A2724` | Conflict highlight (paired with `icon.errorMark`) |
| `cell.errorBorder` | `#C8362B` | `#E66258` | Top-left triangle + thicker border (color-blind dual encoding) |

### Text

| Token | Light | Dark | AA contrast vs `surface.primary` |
|---|---|---|---|
| `text.primary` | `#1A1D21` | `#F2F3F5` | 16.1 / 15.4 — AAA |
| `text.secondary` | `#54595F` | `#A8ADB3` | 7.4 / 7.1 — AAA |
| `text.tertiary` | `#86898E` | `#787C82` | 4.6 / 4.8 — AA (on `surface.primary`) |
| `text.given` | `#1A1D21` | `#F2F3F5` | digits in prefilled cells (bold weight) |
| `text.user` | `#1A6FD1` | `#5BA7F4` | digits user entered (accent-tinted, regular weight). 5.2 / 5.0 — AA |
| `text.errorDigit` | `#A52A20` | `#FF8077` | digit in error cell. 6.1 / 5.4 — AA |

### Accent

| Token | Light | Dark | Usage |
|---|---|---|---|
| `accent.primary` | `#1A6FD1` | `#5BA7F4` | CTAs, selected toggle, focus ring. AA on white: 5.2:1 |
| `accent.muted` | `#D6E7F8` | `#2A4868` | Accent backgrounds (== `cell.selected`) |

### Status

| Token | Light | Dark | Usage |
|---|---|---|---|
| `status.success` | `#1B7A3E` | `#4BC579` | Completion badge, "done today" check |
| `status.warning` | `#A86A0E` | `#E0A95C` | Degraded GC auth, schemaVersion stale |
| `status.error` | `#C8362B` | `#E66258` | Validator error, fetch fail |

**Contrast verification** (key pairings, computed APCA→WCAG fallback):

- `text.primary` / `surface.primary` light: 16.1:1 — AAA
- `text.user` / `cell.base` light: 5.2:1 — AA (normal & large)
- `text.errorDigit` / `cell.error` light: 4.7:1 — AA (normal)
- `accent.primary` / `surface.primary` light: 5.2:1 — AA UI components (≥3:1) ✓
- All dark-mode pairings ≥ 4.5:1 against their cell/surface backgrounds.

> **`text.tertiary` on glass surfaces**: contrast is not guaranteed against `.glassEffect` (translucent material; rear content varies). Treat `text.tertiary` over glass as **decorative-only** and mark with `.accessibilityHidden(true)`. Any non-decorative use over glass must fall back to `text.secondary`.

---

## Typography scale

**Per design.md §How.5.7**: SwiftUI semantic fonts only, except the in-cell digit which is bound to cell size (Dynamic Type would burst the grid).

| Role | SwiftUI | Weight | Use |
|---|---|---|---|
| Screen title | `.largeTitle` | `.semibold` | HomeView, SettingsView title |
| Section header | `.title2` | `.semibold` | Daily Hub day header |
| Card title | `.title3` | `.medium` | Mode cards, puzzle cards |
| Body | `.body` | `.regular` | Default text |
| Button label | `.callout` | `.medium` | CTAs |
| Metadata | `.caption` | `.regular` | "Easy · 5:24" |
| Footnote | `.caption2` | `.regular` | Version, build, GC ID hint |
| **Cell digit** | custom | `.regular` (user) / `.semibold` (given) | `.system(size: cellSide * 0.6, design: .rounded)`. Rounded design reads as friendly without sacrificing legibility; falls back to default if unavailable. |

**Line-height check (zh-TW + ja for longest copy)**:

- "今日のパズル — むずかしい" (DailyHubView header, ja): fits in `.title2` Dynamic Type **xxxLarge** without truncation at 320 pt width ✓
- "排行榜暫時無法載入，請稍後再試。" (zh-TW error banner): wraps cleanly in `.body` at 2 lines ✓

`<USER-INPUT-NEEDED: confirm rounded design preference vs default; rounded reads warmer but some users may want default SF-Pro digits>`

---

## Spacing scale

Base unit: **4 pt**. Steps: `4 / 8 / 12 / 16 / 24 / 32 / 48 / 64`.

All padding / gaps use `@ScaledMetric` to track Dynamic Type:

```swift
@ScaledMetric(relativeTo: .body) private var spacingMd: CGFloat = 16
@ScaledMetric(relativeTo: .body) private var spacingLg: CGFloat = 24
// Inside a View:
VStack(spacing: spacingMd) { … }.padding(spacingLg)
```

> **Preview snippets vs production code**: The SwiftUI preview snippets in `docs/designs/0X-*.md` use **literal** padding/spacing values (e.g. `.padding(16)`) for snapshot-baseline stability — `@ScaledMetric` re-resolves per category and would churn snapshots. Production code MUST wrap these literals in `@ScaledMetric` as shown above. The preview-only literals are not an exemption from the Dynamic Type contract.

**Common pairings**:

- Card internal padding: `16` (md)
- Card-to-card gap: `12`
- Section gap: `24` (lg)
- Screen edge inset (iPhone): `16`
- Screen edge inset (Mac regular): `24`
- BoardView grid-to-edge: `8` (cell breathing room dominates over screen edge)

---

## Liquid Glass usage

Per design.md §How.5.1. iOS 26 / macOS 26 minimum (foundations §1 / §2) — `.glassEffect()` is available everywhere.

| View | Glass used? | Where | Rationale |
|---|---|---|---|
| RootView | No (passthrough) | — | Container only; no chrome of its own |
| HomeView | **Yes** | Mode cards (Daily / Practice / Leaderboard / Settings) | Hero browse surface; depth helps card affordance |
| DailyHubView | **Yes** | Puzzle cards (3 cards for the day) | Same browse pattern; cards feel "pickable" |
| PracticeHubView | **Yes** | Difficulty Picker (segmented, wrapped) + draw button card | Chrome above content; wrapping the Picker too keeps the two surfaces visually cohesive |
| BoardView | **No** | — | §How.5.1 explicit: strong contrast + error highlight legibility. Glass would muddy `cell.error` |
| CompletionView | **Yes** | Hero stats panel (time, rank delta) | Modal hero; glass earns its place over the dismissed BoardView beneath |
| LeaderboardView | Partial | Scope segmented control (top); rows are flat | Avoid 50 stacked glass rows = perf + legibility cost |
| SettingsView | No | — | Standard Form / List; native chrome already correct |

**Implementation**:

```swift
// Apply on the *container* of a logically-grouped chrome surface:
modeCard.glassEffect(.regular, in: .rect(cornerRadius: 16))
// NOT on every leaf — Apple guidance: group then glass once.
```

---

## Touch / mouse targets

Per HIG.

| Surface | iOS minimum | macOS minimum | Notes |
|---|---|---|---|
| Buttons, toggles, list rows | 44 × 44 pt | 28 × 28 pt | Hard minimum |
| BoardView cell | **~36 × 36 pt** on iPhone SE (3rd) | ~40 × 40 pt | **Exception**: 9×9 grid forced to fit 320 pt width minus padding ⇒ 36 pt cell. Mitigation: tap zone extended to cell border (no inter-cell gap that swallows taps); selection ring visible. Acknowledged HIG deviation. |
| GC sign-in CTA | 48 × 48 pt | 32 × 32 pt | Account-action emphasis |

---

## Motion

| Surface | Default | Reduced motion |
|---|---|---|
| Cell tap → selection | 100 ms ease-out | instant |
| Cell digit place | 80 ms scale 0.9→1.0 ease-out | instant |
| Error highlight pulse | 200 ms × 2, ease-in-out | static fill only |
| Sheet / cover present | system default | system default (respects setting automatically) |
| CompletionView hero stat reveal | 350 ms fade + 8 pt rise, stagger 60 ms | instant fade |

Read `@Environment(\.accessibilityReduceMotion)`; gate all transform animations behind it.

---

## SF Symbols (used across Views, listed once)

`gear`, `chart.bar.fill`, `trophy.fill`, `calendar`, `dice`, `dice.fill`, `play.fill`, `pause.fill`, `arrow.uturn.backward`, `arrow.uturn.forward`, `pencil`, `pencil.slash`, `delete.left`, `checkmark.circle.fill`, `xmark.circle.fill`, `exclamationmark.triangle.fill`, `person.crop.circle.badge.questionmark` (GC degraded), `person.crop.circle.badge.checkmark` (GC authenticated), `wifi.slash`, `arrow.clockwise`, `chevron.right`, `square.and.arrow.down`, `lightbulb` (hint — descoped v1 but listed for future), `1.square` through `9.square` (digit pad fallback if numeric glyphs unwanted), `cloud.sun` (DailyHubView empty state), `timer` (BoardView header).

All symbols are SF Symbols 6 stock — no custom symbol set in v1.

---

## Open questions

`<USER-INPUT-NEEDED: rounded-design vs default SF Pro for cell digits>`
`<USER-INPUT-NEEDED: confirm warm off-white surface.background #FAF8F3 vs neutral #F7F7F7 — "graph paper warmth" hinges on this>`
`<USER-INPUT-NEEDED: accent color — current is iOS-system-blue family (#1A6FD1). Brand may want a more unique anchor (teal / indigo / mossy green). Pick one before snapshot baseline freeze>`
