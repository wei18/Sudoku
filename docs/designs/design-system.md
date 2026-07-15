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
| `surface.placeholder` | `#EDEAE3` | `#2A2D33` | Neutral fill behind shimmer placeholder (see §Loading & Placeholder) |

### Board cells

| Token | Light | Dark | Usage |
|---|---|---|---|
| `cell.base` | `#FFFFFF` | `#1E2024` | Empty / default cell |
| `cell.prefilled` | `#EFEBE2` | `#2A2D33` | Givens (puzzle clues, immutable) |
| `cell.userFilled` | `#FFFFFF` | `#1E2024` | User-entered digit (same as base; differentiated by text color) |
| `cell.highlighted` | `#EBF0E2` | `#252D1F` | Same row / col / box as selected |
| `cell.selected` | `#DCE6D0` | `#3A4A30` | The single tapped cell |
| `cell.error` | `#FBE3E1` | `#4A2724` | Conflict highlight (paired with `icon.errorMark`) |
| `cell.errorBorder` | `#C8362B` | `#E66258` | Top-left triangle + thicker border (color-blind dual encoding) |

### Text

| Token | Light | Dark | AA contrast vs `surface.primary` |
|---|---|---|---|
| `text.primary` | `#1A1D21` | `#F2F3F5` | 16.1 / 15.4 — AAA |
| `text.secondary` | `#54595F` | `#A8ADB3` | 7.4 / 7.1 — AAA |
| `text.tertiary` | `#86898E` | `#787C82` | 4.6 / 4.8 — AA (on `surface.primary`) |
| `text.given` | `#1A1D21` | `#F2F3F5` | digits in prefilled cells (bold weight) |
| `text.user` | `#5C7A4F` | `#9BB87E` | digits user entered (accent-tinted, regular weight). 4.8 / 7.5 — AA |
| `text.errorDigit` | `#A52A20` | `#FF8077` | digit in error cell. 6.1 / 5.4 — AA |

### Accent

| Token | Light | Dark | Usage |
|---|---|---|---|
| `accent.primary` | `#5C7A4F` | `#9BB87E` | CTAs, selected toggle, focus ring. AA on white: 4.8:1 |
| `accent.muted` | `#DCE6D0` | `#3A4A30` | Accent backgrounds (== `cell.selected`) |

### Status

| Token | Light | Dark | Usage |
|---|---|---|---|
| `status.success` | `#1B7A3E` | `#4BC579` | Completion badge, "done today" check |
| `status.warning` | `#A86A0E` | `#E0A95C` | Degraded GC auth, schemaVersion stale |
| `status.error` | `#C8362B` | `#E66258` | Validator error, fetch fail |

### Difficulty (v2+)

Restrained-saturation warm trio used **only for difficulty signaling** — DailyHubView puzzle-card tints and PracticeHubView Picker chip tints. The calmness contract of the brand is preserved by limiting their footprint to this signaling role; do NOT promote these tokens to general accent / CTA use.

| Token | Light | Dark | Use |
|---|---|---|---|
| `difficulty.easy` | `#5C7A4F` (sage) | `#9BB87E` (lighter sage) | Easy puzzles — matches `accent.primary` |
| `difficulty.medium` | `#C97D5F` (clay) | `#D89A82` (lighter clay) | Medium puzzles — warm terracotta, new in v2 |
| `difficulty.hard` | `#E6A857` (amber) | `#EFC07F` (lighter amber) | Hard puzzles — warm amber, new in v2 |

**Canonical example**: `docs/app-store/icons/sudoku/light.svg` (AppIcon 07) uses these exact three hexes. Canonized as a brand vocabulary after AppIcon Round 2 adoption (see #63). Each app ships a light/dark/tinted icon set (`docs/app-store/icons/<app>/{light,dark,tinted}.svg`); `dark.svg` is the same composition tuned for the dark appearance, `tinted.svg` is the monochrome tintable variant used for Minesweeper (see `meetings/2026-06-01_minesweeper-icon-design.md`).

**Contrast verification** (key pairings, computed APCA→WCAG fallback):

- `text.primary` / `surface.primary` light: 16.1:1 — AAA
- `text.user` (`#5C7A4F`) / `cell.base` (`#FFFFFF`) light: 4.84:1 — AA (normal & large) ✓
- `text.user` (`#9BB87E`) / `cell.base` (`#1E2024`) dark: 7.52:1 — AAA ✓
- `text.errorDigit` / `cell.error` light: 4.7:1 — AA (normal)
- `accent.primary` (`#5C7A4F`) / `surface.primary` (`#FFFFFF`) light: 4.84:1 — AA normal text ✓; AA UI components (≥3:1) ✓
- `accent.primary` (`#9BB87E`) / `surface.primary` (`#1E2024`) dark: 7.52:1 — AAA ✓
- `accent.muted` is a background token only (text on top is `text.primary`, which retains 14–16:1)
- All dark-mode pairings ≥ 4.5:1 against their cell/surface backgrounds.

> **`text.tertiary` on glass surfaces**: contrast is not guaranteed against `.glassEffect` (translucent material; rear content varies). Treat `text.tertiary` over glass as **decorative-only** and mark with `.accessibilityHidden(true)`. Any non-decorative use over glass must fall back to `text.secondary`.

---

## Typography scale

**Per docs/v1/design.md §How.5.7**: SwiftUI semantic fonts only, except the in-cell digit which is bound to cell size (Dynamic Type would burst the grid).

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

---

## Spacing scale

Base unit: **4 pt**. `SpacingTokens` (`GameShellUI/Theme/Theme.swift`) exposes
five named tiers: `extraSmall / small / medium / large / extraLarge` =
`4 / 8 / 16 / 24 / 32`.

**Two-tier contract** (#762, owner adjudication 2026-07-13 — supersedes the
former blanket "all padding/gaps scale" rule):

- **Content spacing** — padding / stack gaps adjacent to text or icons —
  scales with Dynamic Type via `ScaledSpacing`, a custom `DynamicProperty` in
  `GameShellUI/Theme/ScaledSpacing.swift`:

  ```swift
  @ScaledSpacing(.medium) private var cardPadding
  @ScaledSpacing(.large) private var contentGap
  // Inside a View:
  VStack(spacing: contentGap) { … }.padding(cardPadding)
  ```

  `ScaledSpacing` resolves `theme.spacing.<tier>` multiplied by a Dynamic
  Type curve read directly from `@Environment(\.dynamicTypeSize)` — **not**
  `@ScaledMetric`. PR1's prerequisite gate caught `@ScaledMetric` not
  responding to `dynamicTypeSize` environment overrides in this repo's
  headless `swift test` environment (canary-confirmed; see the PIVOT note in
  `ScaledSpacing.swift`), so the mechanism reads the environment directly and
  applies its own monotonic multiplier table (`1.0` through `.large`, rising
  to `1.65` at `.accessibility5` — deliberately far below the ~3× a
  body-text glyph grows at that size). At the default type size the
  multiplier is exactly `1.0`, so this is pixel-identical to the raw
  token — zero snapshot churn for anything recorded at default size.

- **Structural spacing** — screen margins, card outer gaps, hit-target
  minimums, board-cell geometry — stays **fixed** (does not scale with
  Dynamic Type: these values encode layout geometry that would overflow or
  break if inflated) but still MUST route through `theme.spacing.*` tokens
  or a named constant — never a bare literal:

  ```swift
  .padding(.horizontal, theme.spacing.large)
  private let cardGridGap: CGFloat = 12   // no matching SpacingTokens tier
  ```

- Values that predate this contract and don't match one of the five
  `SpacingTokens` tiers (legacy literals like `12` / `14` / `20`) are marked
  `// spacing-exempt: <reason>` at the call site instead of being silently
  snapped to a neighboring tier, which would change existing pixel output.
  These are tracked as follow-up cleanup once the token-scale gap (the
  5-tier scale doesn't cover every value in use) gets an owner decision.

> **Preview snippets vs production code**: The SwiftUI preview snippets in `docs/designs/0X-*.md` use **literal** padding/spacing values (e.g. `.padding(16)`) for snapshot-baseline stability — `ScaledSpacing` re-resolves per category and would churn snapshots. Production code MUST wrap content-tier literals in `ScaledSpacing` and structural-tier literals in `theme.spacing.*` (or a named constant) as shown above. The preview-only literals are not an exemption from the Dynamic Type contract.

**Common pairings** (tier in parens):

- Card internal padding: `16` (md, content)
- Card-to-card gap: `12` (structural — no matching tier, named constant)
- Section gap: `24` (lg, structural)
- Screen edge inset (iPhone): `16` (structural)
- Screen edge inset (Mac regular): `24` (structural)
- BoardView grid-to-edge: `8` (structural — cell breathing room dominates over screen edge)

---

## Liquid Glass usage

Per docs/v1/design.md §How.5.1. iOS 26 / macOS 26 minimum (foundations §1 / §2) — `.glassEffect()` is available everywhere.

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
| MS BoardView cell — Intermediate (16×16) / Expert (16×30) | **44 × 44 pt**, meets HIG | n/a — Mac windows resize freely and the pointer needs no 44 pt floor; the fitted branch governs there | #764: previously inherited Beginner's 32 pt scroll-fallback floor (below the 44 pt minimum, undocumented). The per-difficulty floor is now 44 pt on these two boards; on narrow phones they were already in the pinned-floor scroll fallback, so raising the floor only lengthens the scroll — cells now meet the HIG minimum instead of falling below it. Beginner's 36 pt exception above is unaffected (its floor stays 32 pt; it never reached that floor to begin with). #815: this 44 pt floor is the DEFAULT presentation only — pinch-to-zoom (two-finger on iOS/iPadOS, trackpad pinch on macOS) lets the player deliberately zoom out to 0.5× (≈22 pt cells, a whole-board overview) or in to 2× (≈88 pt cells) on the two scroll branches; zoom is a session-only, user-initiated escape hatch and never changes the default floor a fresh board opens at. |
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

`gear`, `chart.bar.fill`, `trophy.fill`, `calendar`, `dice`, `dice.fill`, `play.fill`, `pause.fill`, `arrow.uturn.backward`, `arrow.uturn.forward`, `pencil`, `pencil.slash`, `delete.left`, `checkmark.circle.fill`, `xmark.circle.fill`, `exclamationmark.triangle.fill`, `person.crop.circle.badge.questionmark` (GC degraded), `person.crop.circle.badge.checkmark` (GC authenticated), `wifi.slash`, `arrow.clockwise`, `chevron.right`, `square.and.arrow.down`, `lightbulb` (hint — descoped v1 but listed for future), `1.square` through `9.square` (digit pad fallback if numeric glyphs unwanted), `timer` (BoardView header).

All symbols are SF Symbols 6 stock — no custom symbol set in v1.

---

## Loading & Placeholder

Apple HIG: spinners signal *long, indefinite* work. For short, deterministic operations (< 500 ms), use a placeholder shimmer; for very short (< 100 ms), skip animation entirely.

### Thresholds

| Duration | Indicator |
|---|---|
| 0 – 100 ms | None (operation completes before user could perceive a transition) |
| 100 – 500 ms | SwiftUI `.redacted(reason: .placeholder)` — system shimmer on the affected surface |
| > 500 ms | `ProgressView` (indefinite spinner) |

### Tokens

- `motion.shimmer.delay = 100ms` — delay before shimmer starts (avoid flash on sub-threshold ops)
- `motion.shimmer.crossover = 500ms` — switch to ProgressView at this threshold
- `surface.placeholder` — neutral fill behind shimmer (light: `#EDEAE3`; dark: `#2A2D33`)

### Reduce-motion

Under `@Environment(\.accessibilityReduceMotion) == true`, shimmer becomes a static `surface.placeholder` fill (no animation).

### A11y

Shimmer placeholder must carry `.accessibilityLabel("Loading")` and `.accessibilityAddTraits(.updatesFrequently)`.

---

## Theming

### Goal

v1 ships with a single `DefaultTheme`. The token system is structured to allow alternate themes (e.g. high-contrast, sepia, dark-with-warm-accent) without touching any View code. Views consume tokens through `@Environment(\.theme)`; swapping the environment value re-themes the entire tree.

### Code-level abstraction

```swift
public protocol Theme: Sendable {
    var surface: SurfaceTokens { get }
    var cell: CellTokens { get }
    var text: TextTokens { get }
    var accent: AccentTokens { get }
    var status: StatusTokens { get }
}

public struct SurfaceTokens: Sendable {
    public let background: Color
    public let primary: Color
    public let elevated: Color
    // `surface.glass` is a `.glassEffect` material, not a Color — applied via view modifier, not stored.
}

public struct CellTokens: Sendable {
    public let base: Color
    public let prefilled: Color
    public let userFilled: Color
    public let highlighted: Color
    public let selected: Color
    public let error: Color
    public let errorBorder: Color
}

public struct TextTokens: Sendable {
    public let primary: Color
    public let secondary: Color
    public let tertiary: Color
    public let given: Color
    public let user: Color
    public let errorDigit: Color
}

public struct AccentTokens: Sendable {
    public let primary: Color
    public let muted: Color
}

public struct StatusTokens: Sendable {
    public let success: Color
    public let warning: Color
    public let error: Color
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: any Theme = DefaultTheme()
}

public extension EnvironmentValues {
    var theme: any Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
```

### Usage in Views

```swift
struct BoardView: View {
    @Environment(\.theme) private var theme

    var body: some View {
        Rectangle()
            .fill(theme.cell.error)
            .overlay(Text("5").foregroundStyle(theme.text.errorDigit))
    }
}
```

### v1 — only one theme

- `DefaultTheme` is the only concrete impl in v1. It maps to the hex values in §Color tokens.
- Theme switching at runtime is **not** a v1 feature (no Settings toggle). Architecture is in place for v2; UI to choose lives in §Backlog of `docs/v1/design.md`.

### Switching mechanics (for future contributors)

- Inject at root: `RootView().environment(\.theme, currentTheme)`
- `currentTheme` is stored in UserDefaults / CloudKit Private DB at the App composition root (not in `SudokuUI` target — keeps the design system platform-agnostic).
- Light/dark variants of each theme are still resolved through SwiftUI's `colorScheme`. A `Theme` provides the **pair** per token; each `Color` is constructed with light/dark variants (e.g. `Color(light: "#FAF8F3", dark: "#15171A")`) so SwiftUI's `@Environment(\.colorScheme)` continues to drive the resolution. Themes do not need to branch on color scheme themselves.

---

## Dynamic Type policy

Consolidated reference. Cross-link: `docs/v1/design.md` §How.5.7.

1. **All non-cell text uses SwiftUI semantic fonts** (`.body`, `.title2`, `.callout`, …) — auto-scales with Dynamic Type.
2. **Spacing / padding follows the two-tier contract** (see §Spacing scale): content-tier spacing (adjacent to text/icons) scales with Dynamic Type via `ScaledSpacing`; structural-tier spacing (screen margins, card outer gaps, hit-target minimums, board-cell geometry) stays fixed but still routes through `theme.spacing.*` or a named constant.
3. **Cell digit is the documented exception** — `.system(size: cellSide * 0.6, design: .rounded)`. Reason: the 9×9 grid is geometrically fixed; if cell digits Dynamic-Type'd, they would burst the cell. Mitigation: cell size scales with **screen width** (not Dynamic Type), so larger devices yield larger digits.
4. **Acceptance test**: every View must look usable at `.accessibility3` size. The snapshot suite covers BoardView + DailyHubView + CompletionView at `.accessibility3` minimum.
5. **`@Environment(\.dynamicTypeSize)` triggers in v1**:
   - `PracticeHubView` switches Picker → Menu at `.accessibility2+` (see `04-practice-hub.md`).
   - `LeaderboardView` switches row layout to vertical-stacked at `.accessibility3+` (see `07-leaderboard.md` §e).
   - No other Views need explicit `dynamicTypeSize` branches in v1.

---

## Decision log (resolved)

- **Cell digit design** — `.rounded`. Reads as friendly without sacrificing legibility; pairs with the warm Japanese-puzzle-paper aesthetic.
- **`surface.background`** — `#FAF8F3` warm off-white. Anchors the "graph paper warmth" brand essence (see §Brand essence); neutral `#F7F7F7` would read as generic system chrome.
- **Accent color** — sage / mossy green `#5C7A4F` (light) / `#9BB87E` (dark). Differentiates from iOS-system-blue, fits the calm puzzle-paper aesthetic, and meets WCAG AA (4.84:1 light, 7.52:1 dark) against `surface.primary`. Derived tokens (`text.user`, `accent.muted`, `cell.selected`, `cell.highlighted`) recomputed consistently.
- **User-digit weight** — `.regular` + `text.user` tint. Color is the natural Sudoku puzzle-paper differentiator from givens; a weight change would be heavier than the user mental model expects.
