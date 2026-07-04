# 02 — HomeView

> **AS-BUILT NOTE (2026-07-05):** board presentation switched to modal
> fullScreenCover (SDD-003); pause+leave unified (#660); completion = in-board
> overlay (#664/#669); timer in board header (#677). Where this doc says
> "push to BoardView", read "present modally" on iOS. Canonical flow spec:
> `docs/navigation-flows.md`.

## a. View identity

- **Purpose**: Top-level mode selector (Daily / Practice / Leaderboard / Settings). Zero network operations.
- **Triggers**: none.
- **States**: single state — `default`. No loading, no error.

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular — detail column)
┌──────────────────────┐               ┌────────────────────────────────┐
│  Sudoku              │               │  Sudoku                        │
│                      │               │                                │
│  ┌────────────────┐  │               │  ┌──────────┐  ┌──────────┐    │
│  │ 📅 Daily       │  │               │  │ 📅 Daily │  │ 🎲 Prac  │    │
│  │ 3 puzzles today│  │               │  │ 3 today  │  │ Mix pool │    │
│  └────────────────┘  │               │  └──────────┘  └──────────┘    │
│  ┌────────────────┐  │               │  ┌──────────┐  ┌──────────┐    │
│  │ 🎲 Practice    │  │               │  │ 🏆 Lead  │  │ ⚙ Setting│    │
│  └────────────────┘  │               │  └──────────┘  └──────────┘    │
│  ┌────────────────┐  │               │                                │
│  │ 🏆 Leaderboard │  │               │                                │
│  └────────────────┘  │               │                                │
│  ┌────────────────┐  │               │                                │
│  │ ⚙ Settings     │  │               │                                │
│  └────────────────┘  │               │                                │
└──────────────────────┘               └────────────────────────────────┘
```

iPhone: vertical stack of 4 cards. Mac: 2×2 grid.

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/HomeView_Designs.swift
import SwiftUI

private enum HomeMode: String, CaseIterable, Identifiable {
    case daily, practice, leaderboard, settings
    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .practice: "Practice"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }
    var subtitleKey: LocalizedStringKey {
        switch self {
        case .daily: "3 puzzles today"
        case .practice: "Mixed difficulty pool"
        case .leaderboard: "Global / friends"
        case .settings: "Account / language"
        }
    }
    var symbol: String {
        switch self {
        case .daily: "calendar"
        case .practice: "dice"
        case .leaderboard: "trophy.fill"
        case .settings: "gear"
        }
    }
}

struct HomeView_Designs: View {
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        ScrollView {
            let columns = (hSize == .regular)
                ? [GridItem(.flexible()), GridItem(.flexible())]
                : [GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(HomeMode.allCases) { mode in
                    ModeCard(mode: mode)
                }
            }
            .padding(16)
        }
        .navigationTitle("Sudoku")
        .background(Color(.systemBackground))
    }
}

private struct ModeCard: View {
    let mode: HomeMode
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.symbol)
                .font(.title2)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.titleKey).font(.title3.weight(.medium))
                Text(mode.subtitleKey).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }
        .padding(16)
        .frame(minHeight: 72)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

#Preview("Home — iPhone, light, en") {
    NavigationStack { HomeView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Home — Mac, dark, ja") {
    NavigationStack { HomeView_Designs() }
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 600)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Mode card background | `surface.glass` | default | `.glassEffect(.regular, in: rect(16))` |
| Mode card title | `text.primary` | default | `.title3 .medium` |
| Mode card subtitle | `text.secondary` | default | `.caption` |
| Mode card icon | `accent.primary` | default | SF Symbol, `.title2` |
| Card min height | — | — | 72 pt (≥ 44 pt target) |
| Card gap | spacing | — | 12 pt |
| Pressed state | — | onTouchDown | scale 0.98, 100 ms; respect reduce-motion |

## e. A11y notes

- Each card: `.accessibilityElement(children: .combine)` → one VO node per card
- Label: "Daily, 3 puzzles today" (title + subtitle joined). Trait: `.isButton`
- Dynamic Type acceptance: must survive `xxxLarge`. At that size, cards expand vertically; subtitle wraps to 2 lines. Tested: still single-column on iPhone, still 2×2 on Mac (cards grow taller).
- Color-blind: card carries icon + text; never color-only

## f. Design rationale

Four cards, equal weight, no ranking. Reason: Daily/Practice/Leaderboard/Settings are different *kinds* of action (today's task / open-ended play / status / config) — visually flattening them respects user intent rather than nudging toward Daily (a monetization-style nudge we don't need; there is no monetization in v1 per §What v1).

Rejected: (1) "Hero Daily card + smaller tiles below" — biases user toward Daily; (2) tab bar — wastes vertical real estate on a screen visited dozens of times per session-day and adds a permanent chrome we don't need; (3) icons on top, text below — Apple News / Reminders pattern, but our subtitles are too long for that layout and need horizontal space.

The horizontal "icon left, text middle, chevron right" pattern is HIG-blessed (Settings.app row) and Dynamic Type-friendly because each row can grow vertically without breaking layout.
