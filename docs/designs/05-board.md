# 05 — BoardView

## a. View identity

- **Purpose**: The core gameplay surface — 9×9 grid, digit pad, undo/redo, pencil mode, pause, timer.
- **Triggers** (per §How.5.1): `Persistence.loadOrCreate`, `Persistence.save` (debounced 500 ms), scenePhase forced flush.
- **States** (per §How.5.3 state machine): `idle` → `playing` ⇄ `paused` → terminal (`completed` | `abandoned`).
  Additionally, transient cell-level states: `selected`, `highlighted` (same row/col/box), `error`, `prefilled`, `userFilled`, `empty`, `withNotes`.
- **Liquid Glass**: **NO** (§How.5.1 explicit). Board is flat.

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌────────────────────────────────────┐
│ < Medium  ⏱ 3:21 ⏸    │               │ < Medium     ⏱ 3:21        ⏸ Pause  │
│                      │               │                                    │
│ ┌──┬──┬──┬──┬──┬──┐ │               │  ┌─────────────────┐ ┌──────────┐  │
│ │5 │  │  │  │8 │  │ │               │  │   9x9 board     │ │ ↶  ↷     │  │
│ ├──┼──┼──┼──┼──┼──┤ │               │  │                 │ │ ✏ pencil │  │
│ │  │3 │  │  │  │  │ │               │  │                 │ │          │  │
│ │ (...9x9 grid...)  │ │               │  │                 │ │ 1 2 3    │  │
│ ├──┼──┼──┼──┼──┼──┤ │               │  │                 │ │ 4 5 6    │  │
│ │  │  │  │  │  │  │ │               │  │                 │ │ 7 8 9    │  │
│ └──┴──┴──┴──┴──┴──┘ │               │  │                 │ │ ⌫       │  │
│                      │               │  └─────────────────┘ └──────────┘  │
│ ↶  ↷  ✏              │               │                                    │
│ ┌─┬─┬─┬─┬─┬─┬─┬─┬─┐ │               │                                    │
│ │1│2│3│4│5│6│7│8│9│ │               │                                    │
│ └─┴─┴─┴─┴─┴─┴─┴─┴─┘ │               │                                    │
│        ⌫             │               │                                    │
└──────────────────────┘               └────────────────────────────────────┘
```

iPhone: board on top, controls + digit pad on bottom. Mac: board left, controls right (more horizontal real estate).

## b.2 Error highlight (zoomed cell detail)

```
┌────────┐
│▲       │   ← color-blind safe: top-left triangle in cell.errorBorder
│        │      AND background tint cell.error
│   5    │      AND digit color text.errorDigit
│        │
└────────┘
```

## b.3 Paused overlay

When `paused`, board blurs (system material) and a centered "Tap to resume" appears. No timer ticking. Per §How.5.5, no auto-resume on scenePhase return.

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/BoardView_Designs.swift
import SwiftUI

private enum CellStatePreview {
    case empty, given(Int), user(Int), error(Int), selected(Int?), highlighted(Int?)
}

private struct BoardStub {
    static let demo: [[CellStatePreview]] = {
        var rows = Array(repeating: Array(repeating: CellStatePreview.empty, count: 9), count: 9)
        rows[0][0] = .given(5); rows[0][4] = .given(8)
        rows[1][1] = .given(3); rows[4][4] = .selected(6); rows[4][2] = .error(6)
        rows[4][0] = .highlighted(nil); rows[4][1] = .highlighted(nil)
        return rows
    }()
}

struct BoardView_Designs: View {
    let isPaused: Bool = false
    @State private var pencil = false
    @FocusState private var focused: Bool
    @Environment(\.horizontalSizeClass) private var hSize

    // Token stubs at this scope removed (unused — CellView declares its own; see below).

    var body: some View {
        VStack(spacing: 16) {
            header
            board
            controls
            digitPad
        }
        .padding(16)
        .background(Color(.systemBackground))
        .overlay { if isPaused { pauseOverlay } }
        // Mac keyboard story (§How.5.7): focusable + arrow/digit/p/0/delete handling.
        .focusable(hSize == .regular)
        .focused($focused)
        .onKeyPress(phases: .down) { keyPress in
            // Arrows move selection; 1-9 places; 0/delete clears; p toggles pencil. No-op stubs.
            _ = keyPress
            return .handled
        }
    }

    private var header: some View {
        HStack {
            Text("Medium").font(.headline)
            Spacer()
            Label("3:21", systemImage: "timer").monospacedDigit()
            Button { } label: { Image(systemName: "pause.fill") }
            if hSize == .regular {
                Menu {
                    Button("Undo") { }.keyboardShortcut("z", modifiers: .command)
                    Button("Redo") { }.keyboardShortcut("z", modifiers: [.command, .shift])
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    private var board: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cell = side / 9
            VStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { r in
                    HStack(spacing: 0) {
                        ForEach(0..<9, id: \.self) { c in
                            CellView(state: BoardStub.demo[r][c], side: cell)
                                .overlay(borderOverlay(row: r, col: c))
                        }
                    }
                }
            }
            .frame(width: side, height: side)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func borderOverlay(row: Int, col: Int) -> some View {
        // Thick borders at 3-box boundaries
        let thickRight = (col % 3 == 2) && col != 8
        let thickBottom = (row % 3 == 2) && row != 8
        return ZStack {
            Rectangle().stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
            if thickRight {
                HStack { Spacer(); Rectangle().fill(.primary).frame(width: 1.5) }
            }
            if thickBottom {
                VStack { Spacer(); Rectangle().fill(.primary).frame(height: 1.5) }
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 24) {
            Button { } label: { Image(systemName: "arrow.uturn.backward") }
            Button { } label: { Image(systemName: "arrow.uturn.forward") }
            Toggle(isOn: $pencil) {
                Image(systemName: pencil ? "pencil" : "pencil.slash")
            }.toggleStyle(.button)
        }
        .font(.title2)
    }

    private var digitPad: some View {
        HStack(spacing: 8) {
            ForEach(1...9, id: \.self) { d in
                Button("\(d)") { }
                    .frame(minWidth: 36, minHeight: 44)
                    .buttonStyle(.bordered)
            }
            Button { } label: { Image(systemName: "delete.left") }
                .frame(minWidth: 36, minHeight: 44)
        }
    }

    private var pauseOverlay: some View {
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            VStack(spacing: 12) {
                Image(systemName: "play.circle.fill").font(.system(size: 64))
                Text("Tap to resume").font(.title3.weight(.medium))
            }
        }
    }
}

private struct CellView: View {
    let state: CellStatePreview
    let side: CGFloat
    var body: some View {
        ZStack {
            background
            content
        }
        .frame(width: side, height: side)
    }

    // Token stub helpers (snapshot stability — production uses design-system tokens).
    // Literal hex sourced from design-system.md.
    private var cellError: Color { Color(red: 0xFB/255, green: 0xE3/255, blue: 0xE1/255) }       // cell.error light
    private var cellPrefilled: Color { Color(red: 0xEF/255, green: 0xEB/255, blue: 0xE2/255) }   // cell.prefilled light
    private var textErrorDigit: Color { Color(red: 0xA5/255, green: 0x2A/255, blue: 0x20/255) }  // text.errorDigit light

    @ViewBuilder private var background: some View {
        switch state {
        case .empty: Color.clear
        case .given: cellPrefilled
        case .user: Color.clear
        case .error: cellError
        case .selected: Color.accentColor.opacity(0.22)
        case .highlighted: Color.accentColor.opacity(0.08)
        }
    }

    @ViewBuilder private var content: some View {
        let digitFont = Font.system(size: side * 0.6, weight: .regular, design: .rounded)
        switch state {
        case .empty, .highlighted(nil), .selected(nil): EmptyView()
        case .given(let d):
            Text("\(d)").font(.system(size: side * 0.6, weight: .semibold, design: .rounded))
        case .user(let d), .selected(.some(let d)), .highlighted(.some(let d)):
            Text("\(d)").font(digitFont).foregroundStyle(.tint)
        case .error(let d):
            ZStack(alignment: .topLeading) {
                Text("\(d)").font(digitFont).foregroundStyle(textErrorDigit).frame(maxWidth: .infinity, maxHeight: .infinity)
                Triangle().fill(textErrorDigit).frame(width: side * 0.18, height: side * 0.18).padding(2)
            }
        }
    }
}

private struct Triangle: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: r.origin); p.addLine(to: .init(x: r.maxX, y: r.minY)); p.addLine(to: .init(x: r.minX, y: r.maxY))
        p.closeSubpath(); return p
    }
}

#Preview("Board — iPhone, light, en") {
    BoardView_Designs()
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Board — Mac, dark, ja") {
    BoardView_Designs()
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 700)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Board background | `surface.background` | — | flat, no glass |
| Cell base | `cell.base` | default | clear / white |
| Cell prefilled (given) | `cell.prefilled` | given | digit `text.given` bold |
| Cell user-filled | `cell.userFilled` | user | digit `text.user` regular |
| Cell highlighted | `cell.highlighted` | row/col/box of selection | bg tint only |
| Cell selected | `cell.selected` | tap | stronger tint than highlighted |
| Cell error | `cell.error` | conflict | bg + `text.errorDigit` + corner triangle in `cell.errorBorder` |
| Box separator | `text.primary` | — | 1.5 pt at every 3rd boundary; 0.5 pt elsewhere |
| Digit font | custom | per cell | `cellSide * 0.6`, `.rounded` design, `.semibold` (given) / `.regular` (user) |
| Timer | `text.secondary` | — | `.body .monospacedDigit()` |
| Pause button | `accent.primary` | default | SF `pause.fill` / `play.fill` |
| Undo/Redo | `text.primary` | enabled; disabled = `text.tertiary` | SF `arrow.uturn.{backward,forward}` |
| Pencil toggle | `accent.primary` when on | toggle | `.button` toggle style |
| Digit pad button | `text.primary` | default | `.bordered`, ≥44 pt height, ≥36 pt width |
| Delete button | `text.primary` | default | `delete.left` SF |
| Pause overlay | `.ultraThinMaterial` | paused only | full-cover blur |

Interaction:
- Tap empty cell → select; same row/col/box highlight
- Tap digit (pencil off) → place; if conflict, cell goes `error` (200 ms pulse — reduce-motion: static)
- Tap digit (pencil on) → toggle note in cell (3×3 mini-grid of digits 1-9 at 22% size)
- Long-press cell → clear digit (alternative to delete button)
- Mac keyboard (§How.5.7): arrows move selection, 1-9 places, 0/delete clears, `p` toggles pencil, ⌘Z / ⌘⇧Z undo/redo

## e. A11y notes

- **VoiceOver per cell**: `"Row R column C, \(stateDescription)"` where state is "empty / given 5 / 7 entered / conflict 7 / pencil notes 1, 4"
- **Custom actions on board**: `.accessibilityCustomActions` — "next error", "next empty cell"
- **Dynamic Type**: cells DON'T scale with Dynamic Type (bound to cellSide). Timer and controls DO scale.
- **Color-blind error encoding**: triple (bg color + corner triangle shape + digit color); never color-only
- **prefersIncreasedContrast**: thicken cell borders to 1 pt (from 0.5 pt); deepen box separator to 2 pt
- **Reduce motion**: pulse animations become static; cell place animation removed

## f. Design rationale

The board is the product. Two non-negotiables drove the design:

1. **Legibility over decoration**. §How.5.1 explicitly forbids glass on the board, and we agree — `cell.error` only reads as urgent against a flat surface. Tinted glass + red overlay = mud.
2. **Color-blind dual encoding** for error state. ~8% of male users have some form of color blindness; relying on red-only would mark our error UI as broken on a meaningful population slice. The corner triangle adds shape to the channel.

Mac layout splits board and controls horizontally because keyboard users rarely tap, and pointer users benefit from larger controls in dedicated real estate. The 9-digit pad on Mac is *retained* (not removed) because new users discover the interaction model from it before learning the keyboard shortcut.

Rejected: (1) "ghost digit" preview when hovering before tap on Mac — adds latency and surprises keyboard users; (2) animated streak / combo counters — gamification anti-pattern for a contemplation puzzle; (3) sound effects for cell taps — descoped to v2 backlog if at all.

`<DESIGNER-DECISION: user-entered digit stays `.regular` weight + `text.user` accent tint. Rationale: color is the natural Sudoku puzzle-paper differentiator from givens; a weight change would be heavier than the user mental model expects (pencil-on-paper convention is the same stroke weight, ink color shifts). Recorded in design-system.md §Decision log.>`
