# 04 — PracticeHubView

## a. View identity

- **Purpose**: Pick a difficulty, generate a fresh puzzle locally via the deterministic generator. Open-ended play, no pool, no Starter Pack.
- **Triggers** (per §How.5.1): `PuzzleStore.fetchPracticePool(difficulty:)`.
- **States**:
  - `idle` — difficulty picker shown, no puzzle drawn yet
  - `drawing` — fetching
  - `drawing(>100ms)` — shimmer placeholder on the "Ready to play" card while generator runs (typical < 100 ms, p95 < 300 ms per §How.6.4)
  - `drawn(puzzleId)` — show preview + "Play" CTA (or auto-push to BoardView, see rationale)
  - `error(reason)` — fetch failed

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌────────────────────────────────┐
│ < Practice           │               │ Practice                       │
│                      │               │                                │
│  Difficulty          │               │  Difficulty                    │
│  ┌──┬──┬──┬──┐       │               │  [Easy][Med][Hard][Expert]     │
│  │E │M │H │X │       │               │                                │
│  └──┴──┴──┴──┘       │               │  ┌──────────────────────────┐  │
│                      │               │  │  Ready to play           │  │
│  ┌──────────────────┐│               │  │  Medium · puzzleId 24c8  │  │
│  │ Ready to play    ││               │  │  [ ▶ Draw new puzzle ]   │  │
│  │ Medium · 24c8    ││               │  └──────────────────────────┘  │
│  │ [▶ Draw new]     ││               │                                │
│  └──────────────────┘│               │                                │
└──────────────────────┘               └────────────────────────────────┘
```

### b.2 Drawing state (shimmer, > 100 ms)

```
┌──────────────────────┐
│ < Practice           │
│                      │
│  Difficulty          │
│  ┌──┬──┬──┬──┐       │
│  │E │M │H │X │       │
│  └──┴──┴──┴──┘       │
│                      │
│  ┌──────────────────┐│
│  │ ░░░░░░░░░░░░░░░  ││  ← shimmer (.redacted)
│  │ ░░░░░░░░          ││
│  │ [ ▶ Draw new ]   ││  ← disabled
│  └──────────────────┘│
└──────────────────────┘
```

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/PracticeHubView_Designs.swift
import SwiftUI

private enum DifficultyPreview: String, CaseIterable, Identifiable {
    case easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert"
    var id: String { rawValue }
    var shortKey: LocalizedStringKey { LocalizedStringKey(rawValue) }
}

private enum PracticeHubState { case drawn(String), drawing }

struct PracticeHubView_Designs: View {
    @State private var difficulty: DifficultyPreview = .medium
    var state: PracticeHubState = .drawn("24c8")

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Difficulty").font(.title3.weight(.semibold))
            Picker("Difficulty", selection: $difficulty) {
                ForEach(DifficultyPreview.allCases) { d in
                    Text(d.shortKey).tag(d)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 12) {
                Text("Ready to play").font(.headline)
                switch state {
                case .drawn(let id):
                    Text("\(difficulty.rawValue) · puzzleId \(id)")
                        .font(.caption).foregroundStyle(.secondary)
                    Button {
                    } label: {
                        Label("Draw new puzzle", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                case .drawing:
                    Text("placeholder placeholder placeholder")
                        .font(.caption)
                        .redacted(reason: .placeholder)
                        .accessibilityLabel("Loading")
                        .accessibilityAddTraits(.updatesFrequently)
                    Button { } label: {
                        Label("Draw new puzzle", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(true)
                }
            }
            .padding(16)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))

            Spacer()
        }
        .padding(16)
        .navigationTitle("Practice")
    }
}

#Preview("Practice — iPhone, light, en") {
    NavigationStack { PracticeHubView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Practice — Mac, dark, ja") {
    NavigationStack { PracticeHubView_Designs() }
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 600)
}

#Preview("Practice — drawing (shimmer)") {
    NavigationStack { PracticeHubView_Designs(state: .drawing) }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Section header | `text.primary` | default | `.title3 .semibold` |
| Segmented control | system | default | `.tint(accent.primary)`; wrapped in `.glassEffect(.regular, in: rect(12))` for visual cohesion with the draw-button card (matches design-system.md Liquid Glass table: "segmented Picker + draw button card") |
| Card | `surface.glass` | default | `.glassEffect(.regular, in: rect(16))` |
| "Ready to play" label | `text.primary` | default | `.headline` |
| Puzzle id hint | `text.secondary` | default | `.caption` |
| Draw CTA | `accent.primary` | default | `.borderedProminent`, `.controlSize(.large)`, min height 44 pt |
| CTA pressed | — | press | system feedback; reduce-motion respected |
| Card (drawing) | `surface.glass` | drawing | SwiftUI `.redacted(reason: .placeholder)` for system shimmer; appears only after 100 ms delay (do NOT show for sub-100 ms typical operations — avoids flash) |
| Alert (.exhausted) | system | error | Title "Couldn't generate today's puzzle"; message "Try a different difficulty, or come back tomorrow."; primary CTA "Try again" (re-roll with fresh salt; will almost always succeed); secondary "Switch difficulty"; VoiceOver = `.assertive` |

Interaction:
- Tap segment → state moves to `idle` for that difficulty; drawn puzzleId clears (we don't retain across difficulty changes — fresh intent)
- Tap "Draw new puzzle" → BoardView pushed; puzzleId chosen randomly from pool

## e. A11y notes

- Segmented Picker: native VO reads each segment label
- Draw button: label `"Draw new \(difficulty) puzzle"` (composite). Trait: `.isButton`. Hint: `"Opens the board"`
- Dynamic Type: segmented control truncates at xxxLarge. `<DESIGNER-DECISION: Fall back to `Menu` (vertical Picker) at `.accessibility2` and larger via `@Environment(\.dynamicTypeSize)`. Rationale: HIG bias for AX sizes favors vertically-stacked, non-truncating controls; segmented controls at AX2+ lose their label even with allows-truncation. Implementation: branch on `dynamicTypeSize >= .accessibility2` → `Menu` with `Picker(.menu)` style; otherwise segmented as today.>`
- Color-blind: no color-only encoding

## f. Design rationale

A picker + a big CTA. We keep this screen deliberately empty because the user's intent is "give me something to do, now"; the longer they linger here, the worse the design. The puzzleId hint (a 4-char hex) exists for one purpose only: lets the user verify "draw new" actually changed the puzzle (otherwise the button feels broken when they replay the same difficulty back-to-back and get UI that looks identical for 200 ms before push).

Rejected: (1) thumbnail preview of the puzzle board — wastes attention, doesn't help decide; (2) "estimated time" hint — §How.4.3 explicitly descopes difficulty calibration in v1, so we can't truthfully label "≈12 min"; (3) skip-the-hub auto-route from Home → Practice straight to a Board — removes user agency over difficulty.

Note: this is the simplest View. Most of its complexity is hidden in `PracticeHubViewModel`'s generator-draw logic (salt → seed → puzzle, per `design.md §How.4`). UI does its job by being almost invisible.

Sub-300 ms generation budget means we deliberately avoid a `ProgressView` spinner (Apple HIG: spinners signal long indefinite work). Shimmer at 100 ms threshold is the lighter affordance; below threshold we skip animation entirely to avoid flash.
