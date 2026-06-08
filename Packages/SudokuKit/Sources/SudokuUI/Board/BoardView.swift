// BoardView — 9×9 grid + digit pad + controls + pause overlay.
//
// Per docs/designs/05-board.md + docs/v1/design.md §How.5.7 (A11y). NO `.glassEffect`
// on the board itself (§How.5.1). Mac keyboard: `.focusable()` + `.onKeyPress`
// for arrows / 1–9 / 0 / delete / `p`; ⌘Z / ⌘⇧Z bound for undo / redo.

public import MonetizationCore
public import SwiftUI
import SudokuEngine

public struct BoardView: View {
    @Bindable private var viewModel: GameViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    /// Host navigation path. Optional so previews / snapshot tests (which mount
    /// `BoardView` directly, with no `NavigationStack`) keep working — `nil`
    /// makes the solve → completion push a graceful no-op.
    private let path: Binding<[AppRoute]>?
    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var keyboardFocus: Bool
    /// One-shot latch: completion is sticky and SwiftUI re-evaluates `body`
    /// freely, so guard the push to fire EXACTLY once.
    @State private var hasNavigatedToCompletion = false

    public init(
        viewModel: GameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        path: Binding<[AppRoute]>? = nil
    ) {
        self.viewModel = viewModel
        self.adProvider = adProvider
        self.adGate = adGate
        self.path = path
    }

    public var body: some View {
        Group {
            if sizeClass == .regular {
                macLayout
            } else {
                compactLayout
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        .focusable()
        .focused($keyboardFocus)
        .onAppear { keyboardFocus = true }
        .onKeyPress(phases: .down, action: handleKeyPress)
        .background(undoRedoShortcuts)
        .task(id: viewModel.identity.puzzleId) {
            // #227 elapsed-mirror ticker: `GameViewModel.elapsedSeconds` is
            // only refreshed via `resyncFromSession()` after a mutation, so
            // between user inputs the header label would stay frozen. Poll
            // the session once per second while the game is live; cancel
            // automatically when paused / finished or when the view goes
            // away (`.task` lifecycle handles both).
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refreshElapsed()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: viewModel.status) {
            // Fires only on the live `.playing → .completed` transition (P0-1).
            // No `initial: true`, so re-opening an already-completed board
            // (mounted directly in `.completed`) does NOT auto-bounce to
            // Completion — the finished board stays viewable.
            pushCompletionIfNeeded()
        }
        // #413: flush the debounced autosave when the board leaves the screen.
        // `scheduleSave()` is debounced (500 ms) and holds `[weak self]`; a
        // Home tap (NavigationStack pop → `.onDisappear`) tears the VM down
        // before the debounce fires, so the pending save sees `self == nil`
        // and the latest moves + elapsed are silently dropped — the next
        // Resume then shows a stale/fresh board and the wrong time. Flushing
        // here persists the live snapshot first. This is the "view dismiss"
        // case the `GameViewModel.flush()` doc already promised.
        // NB: a bare `Task` (NOT `.task {}`) is load-bearing — it captures the
        // VM strongly and must outlive view teardown to complete the write;
        // a structured `.task` would be cancelled on disappear and re-drop it.
        .onDisappear {
            Task { await viewModel.flush() }
        }
        // #413: same hazard on app backgrounding — persist before suspension
        // (the "scenePhase background" case `flush()`'s doc references).
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase != .active {
                Task { await viewModel.flush() }
            }
        }
    }

    /// Push `.completion` onto the host path when the session has reached
    /// `.completed`. Guarded by `hasNavigatedToCompletion` so the sticky
    /// completion state + SwiftUI re-evaluation can only append once.
    /// `path == nil` (previews / tests) → graceful no-op.
    private func pushCompletionIfNeeded() {
        guard !hasNavigatedToCompletion,
              let route = viewModel.completionRoute,
              let path else { return }
        hasNavigatedToCompletion = true
        path.wrappedValue.append(route)
    }

    // MARK: - Compact (iPhone) layout

    private var compactLayout: some View {
        VStack(spacing: 16) {
            header
            boardWithOverlay
            // v2.3.5: banner sits between the grid and the digit pad. It
            // is suppressed while the game is paused — pause is a moment
            // of intentional quiet (PauseOverlayView already dims the
            // grid), and showing an ad on top of that contradicts the
            // calm contract.
            if !viewModel.isPaused, let adProvider, let adGate {
                BannerSlotView(adProvider: adProvider, adGate: adGate)
            }
            digitPad
        }
    }

    // MARK: - Mac (regular) 2-column layout
    //
    // Per docs/designs/05-board.md §b Mac wireframe (locked 2026-05-30):
    //   - outer maxWidth 960 pt, centered
    //   - left: 9×9 board (capped to ≤ 640 pt square)
    //   - right: 260 pt control rail (history / Notes / 3×3 digit / Erase)
    //   - 24 pt gap between board and rail
    private var macLayout: some View {
        VStack(spacing: 16) {
            header
            HStack(alignment: .top, spacing: 24) {
                macBoardColumn
                digitPad
            }
            // Pause-time banner suppression preserved on Mac too.
            if !viewModel.isPaused, let adProvider, let adGate {
                BannerSlotView(adProvider: adProvider, adGate: adGate)
            }
        }
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)  // additive to outer .padding(16) → ≥ 32 pt
    }

    private var macBoardColumn: some View {
        boardWithOverlay
            .frame(maxWidth: 640, maxHeight: 640)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var digitPad: some View {
        DigitPadView(
            pencilMode: viewModel.pencilMode,
            canUndo: viewModel.canUndo,
            canRedo: viewModel.canRedo,
            sizeClass: sizeClass,
            onDigit: { digit in Task { await placeOrToggle(digit) } },
            onErase: { Task { await viewModel.eraseCell() } },
            onTogglePencil: { viewModel.togglePencil() },
            onUndo: { Task { await viewModel.undo() } },
            onRedo: { Task { await viewModel.redo() } }
        )
    }

    // MARK: - Layout

    private var header: some View {
        HStack(spacing: 12) {
            Text(LocalizedStringKey(viewModel.identity.difficulty.rawValue.capitalized))
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)
            // #228 option B: subtle marker when the user opens a past-day
            // daily puzzle. `SubmitGuards` blocks the Game Center submission
            // for these; this affordance lets the player know mid-game that
            // the run won't score.
            if viewModel.isLateCompletion {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(theme.text.secondary.resolved)
                    .accessibilityLabel(
                        Text("Late completion — won't score on leaderboard")
                    )
            }
            Spacer()
            Label(elapsedLabel, systemImage: "timer")
                .monospacedDigit()
                .foregroundStyle(theme.text.secondary.resolved)
                .accessibilityLabel("Elapsed time \(elapsedLabel)")
            Button {
                Task {
                    if viewModel.isPaused {
                        await viewModel.resume()
                    } else {
                        await viewModel.pause()
                    }
                }
            } label: {
                if sizeClass == .regular {
                    // Mac: icon + text label per board-mac-redesign wireframe.
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                } else {
                    // iPhone: icon-only for header compactness.
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                }
            }
            .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")
        }
    }

    private var boardWithOverlay: some View {
        // GeometryReader reports the offered size to its children but takes
        // the full offered frame for its own layout — so we read the offered
        // box here, compute the square `side`, and explicitly size both the
        // grid and the overlay to that square.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cellSide = side / CGFloat(Board.dimension)
            ZStack {
                VStack(spacing: 0) {
                    ForEach(0..<Board.dimension, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<Board.dimension, id: \.self) { col in
                                cell(row: row, column: col, side: cellSide)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)

                if viewModel.isPaused {
                    PauseOverlayView(onResume: {
                        Task { await viewModel.resume() }
                    })
                    .frame(width: side, height: side)
                }
            }
            // Centre the square grid within the GR's offered rectangle so
            // the board sits inline with the surrounding header/digit pad
            // padding instead of sticking to the leading edge.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func cell(row: Int, column: Int, side: CGFloat) -> some View {
        let index = Board.index(row: row, column: column)
        let digit = viewModel.board.digit(atIndex: index)
        let isGiven = viewModel.board.givenMask[index]
        let isSelected = viewModel.selection.map { $0.row == row && $0.column == column } ?? false
        let isError = viewModel.errorIndices.contains(index)
        let noteMask = viewModel.notes.masks[index]
        return Button {
            viewModel.select(row: row, column: column)
        } label: {
            BoardCellView(
                row: row,
                column: column,
                digit: digit,
                isGiven: isGiven,
                isSelected: isSelected,
                isError: isError,
                isPencilNotes: digit == nil,
                noteMask: noteMask,
                side: side
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Keyboard

    private func handleKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        // Arrow keys: move focus.
        switch keyPress.key {
        case .leftArrow:
            viewModel.moveSelection(rowDelta: 0, columnDelta: -1); return .handled
        case .rightArrow:
            viewModel.moveSelection(rowDelta: 0, columnDelta: 1); return .handled
        case .upArrow:
            viewModel.moveSelection(rowDelta: -1, columnDelta: 0); return .handled
        case .downArrow:
            viewModel.moveSelection(rowDelta: 1, columnDelta: 0); return .handled
        case .delete:
            Task { await viewModel.placeDigit(nil) }; return .handled
        default:
            break
        }
        // Character keys.
        let chars = keyPress.characters
        if chars == "p" || chars == "P" {
            viewModel.togglePencil()
            return .handled
        }
        if chars == "0" {
            Task { await viewModel.placeDigit(nil) }
            return .handled
        }
        if let scalar = chars.unicodeScalars.first,
           let digit = Int(String(scalar)),
           (1...9).contains(digit) {
            Task { await placeOrToggle(digit) }
            return .handled
        }
        return .ignored
    }

    private func placeOrToggle(_ digit: Int) async {
        if viewModel.pencilMode {
            await viewModel.toggleNote(digit)
        } else {
            await viewModel.placeDigit(digit)
        }
    }

    @ViewBuilder
    private var undoRedoShortcuts: some View {
        // Hidden buttons that own the ⌘Z / ⌘⇧Z bindings (Mac App menu picks
        // them up automatically; iPad external keyboards inherit).
        Group {
            Button("Undo") { Task { await viewModel.undo() } }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { Task { await viewModel.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .hidden()
        .accessibilityHidden(true)
    }

    private var elapsedLabel: String {
        let total = viewModel.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
