# 03 — DailyHubView

> **AS-BUILT NOTE (2026-07-05):** board presentation switched to modal
> fullScreenCover (SDD-003); pause+leave unified (#660); completion = in-board
> overlay (#664/#669); timer in board header (#677). Where this doc says
> "push to BoardView", read "present modally" on iOS. Canonical flow spec:
> `docs/navigation-flows.md`.

## a. View identity

- **Purpose**: Show today's 3 daily puzzles (Easy / Medium / Hard) with completion state. Tap a card → BoardView.
- **Triggers** (per §How.5.1): `PuzzleStore.fetchDailyTrio(date:)`, `Persistence.fetchCompletedDailyIds(date:)`.
- **States**:
  - `loading` — fetching trio
  - `loaded(cards: [DailyCard])` — happy path
  - `error(.exhausted)` — extremely rare; surfaced as an inline empty-state block per §How.6.3 (Generator defect; #768 replaced the prior system alert)
  - `error(reason)` — fetch failed; show retry

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌────────────────────────────────┐
│ < Daily   May 16     │               │ Daily — May 16, 2026           │
│                      │               │                                │
│ ┌──────────────────┐ │               │ ┌──────┐ ┌──────┐ ┌──────┐     │
│ │ Easy        ✓ 4:11│ │               │ │Easy ✓│ │Med   │ │Hard  │     │
│ │ ▱▱▱▱▱▱▱▱▱        │ │               │ │ 4:11 │ │ 12:30│ │  —   │     │
│ └──────────────────┘ │               │ └──────┘ └──────┘ └──────┘     │
│ ┌──────────────────┐ │               │                                │
│ │ Medium      12:30 │ │               │  Tap any card to play.         │
│ │ ▱▱▱▱▱▱▱▱▱        │ │               │                                │
│ └──────────────────┘ │               │                                │
│ ┌──────────────────┐ │               │                                │
│ │ Hard          —   │ │               │                                │
│ │ ▱▱▱▱▱▱▱▱▱        │ │               │                                │
│ └──────────────────┘ │               │                                │
└──────────────────────┘               └────────────────────────────────┘
```

The 9-cell mini-strip below each card title is a visual hint of board density (givens vs blanks) — purely decorative, low contrast.

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/DailyHubView_Designs.swift
import SwiftUI

private struct DailyCardModel: Identifiable {
    let id: String
    let difficultyLabel: String
    let completedTime: String?   // nil = not yet
}

private enum DailyHubState {
    case loaded([DailyCardModel])
    case loading
}

struct DailyHubView_Designs: View {
    var state: DailyHubState = .loaded([
        .init(id: "easy", difficultyLabel: "Easy", completedTime: "4:11"),
        .init(id: "medium", difficultyLabel: "Medium", completedTime: nil),
        .init(id: "hard", difficultyLabel: "Hard", completedTime: nil),
    ])
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        Group {
            switch state {
            case .loaded(let cards): cardList(cards)
            case .loading: ProgressView().controlSize(.large)
            }
        }
        .navigationTitle(Text("Daily"))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func cardList(_ cards: [DailyCardModel]) -> some View {
        let cols: [GridItem] = (hSize == .regular)
            ? [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            : [GridItem(.flexible())]
        ScrollView {
            LazyVGrid(columns: cols, spacing: 12) {
                ForEach(cards) { DailyCard(model: $0) }
            }
            .padding(16)
        }
    }

}

private struct DailyCard: View {
    let model: DailyCardModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(LocalizedStringKey(model.difficultyLabel)).font(.title3.weight(.medium))
                Spacer()
                if let t = model.completedTime {
                    Label(t, systemImage: "checkmark.circle.fill")
                        .font(.callout).foregroundStyle(.green)
                } else {
                    Text("—").font(.callout).foregroundStyle(.secondary)
                }
            }
            MiniBoardStrip()
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

private struct MiniBoardStrip: View {
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<9) { i in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.secondary.opacity(i.isMultiple(of: 2) ? 0.18 : 0.08))
                    .frame(height: 8)
            }
        }
    }
}

#Preview("DailyHub — iPhone, light, en") {
    NavigationStack { DailyHubView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("DailyHub — Mac, dark, ja") {
    NavigationStack { DailyHubView_Designs() }
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 600)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Card background | `surface.glass` | default | `.glassEffect(.regular, in: rect(16))` |
| Difficulty label | `text.primary` | default | `.title3 .medium` |
| Completed time | `status.success` | completed | `.callout` + `checkmark.circle.fill` |
| Em-dash placeholder | `text.tertiary` | not completed | `.callout` |
| Mini strip cell | `text.tertiary` α0.08/0.18 | decorative | 8 pt tall |
| Card tap | — | press | scale 0.98 100 ms |
| Inline empty-state block (.exhausted) | `status.warning` | error | Warning icon; title "Couldn't generate today's puzzle"; message "Try a different difficulty, or come back tomorrow."; actions "Practice" (`.borderedProminent`, routes to Practice hub) / "Cancel" (`.bordered`, pops to Home); #768 replaced the prior system alert, same visual language as `.failed` |

## e. A11y notes

- Each card combined element: `"Easy, completed in 4 minutes 11 seconds"` or `"Medium, not yet played"`
- Mini-strip is `.accessibilityHidden(true)` — decorative
- Dynamic Type acceptance: xxxLarge; difficulty + time wrap to 2 lines if needed
- Color-blind: checkmark icon + visible time encodes completion; never relies on green-only

## f. Design rationale

Three sibling cards rather than a hero "today's hardest" or a stack-by-difficulty list. Daily Trio is **one task with three steps**; ordering them Easy→Medium→Hard matches user mental model (warm up first) and HIG progressive disclosure. Glass effect on cards reinforces "browse and pick" semantics.

Rejected: (1) tab control to switch difficulty — adds a click before play; (2) auto-advance "next puzzle" carousel — coercive; (3) leaderboard preview inline on each card — moved into BoardView/CompletionView per §How.5.1's clear separation.

Daily puzzles are generated locally and deterministically; the only failure path is `GeneratorError.exhausted` (§How.6.3), surfaced via an inline empty-state block (#768; a system alert prior to that).
