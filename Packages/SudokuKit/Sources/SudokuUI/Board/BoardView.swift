// BoardView — 9×9 grid + digit pad + controls + pause overlay.
//
// Per docs/designs/05-board.md + docs/v1/design.md §How.5.7 (A11y). NO `.glassEffect`
// on the board itself (§How.5.1). Mac keyboard: `.focusable()` + `.onKeyPress`
// for arrows / 1–9 / 0 / delete / `p`; ⌘Z / ⌘⇧Z bound for undo / redo.

public import MonetizationCore
public import SwiftUI
public import GameCenterClient
internal import GameAppKit
import GameShellUI
import MonetizationUI
public import SudokuEngine
public import SettingsUI

public struct BoardView: View {
    // Several members are `internal` (not `private`) because the header
    // helpers in BoardView+AccessibilityHeader.swift read them across files
    // within the same module.
    @Bindable var viewModel: GameViewModel
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    /// Host navigation path. Optional so previews / snapshot tests (which mount
    /// `BoardView` directly) keep working — `nil` makes the push a graceful no-op.
    /// `internal` (not `private`) — `BoardView+Completion` reads it for the predicate.
    let path: Binding<[AppRoute]>?
    // #610: GC client + daily primer builder — internal for BoardView+Completion.swift.
    let gameCenter: (any GameCenterClient)?
    let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    // #652: Play Again CTA. When wired, the completion overlay shows "Play Again"
    // above Close. The closure receives the current difficulty so the caller can
    // start a fresh game at the same level. `nil` → Close-only (existing behavior).
    // `internal` so BoardView+Completion can read it.
    let onPlayAgain: ((Difficulty) -> Void)?
    @Environment(\.theme) var theme
    @Environment(\.horizontalSizeClass) var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    // #610 fix *2: dismiss the fullScreenCover when Close is tapped on the
    // completion overlay. `DismissAction` is a no-op outside a presented context
    // (previews / snapshot tests / macOS push path — all safe to call).
    @Environment(\.dismiss) private var dismiss
    // SDD-003 OQ-001: when GameRoot injects a GameChromeState into the
    // modal hierarchy, this is non-nil and we (a) push the elapsed label
    // to the chrome on every tick and (b) hide the in-board header timer
    // to avoid showing two clocks on screen.
    @Environment(\.gameChrome) var gameChrome
    @FocusState private var keyboardFocus: Bool
    /// One-shot latch: completion is sticky and SwiftUI re-evaluates `body`
    /// freely, so guard the push to fire EXACTLY once.
    @State private var hasNavigatedToCompletion = false
    // #610: Completion overlay VM + Daily primer. Both held in @State so they
    // survive body recomputes without resetting fetch / auth-check state.
    @State var completionViewModel: CompletionViewModel?
    @State var completionReminderPrimer: ReminderPrimerCoordinator?

    public init(
        viewModel: GameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        path: Binding<[AppRoute]>? = nil
    ) {
        self.viewModel = viewModel
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.onPlayAgain = onPlayAgain
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
        // #610: full-cover Completion overlay (MS #292/#518 mirror).
        // fix *2: pass dismiss so Close returns the user to the hub.
        .overlay {
            if let completionViewModel {
                completionSurface(completionViewModel, dismiss: dismiss)
            }
        }
        // #610: build VM+primer on .completed; clear on Close. CR #518-R2: keyed on
        // overlay presence so Close restores chrome. `shouldPresentCompletionOverlay`
        // gates to path==nil — macOS (path!=nil) uses push path, no double-present.
        .onChange(of: viewModel.status == .completed) { _, isCompleted in
            if isCompleted, completionViewModel == nil, shouldPresentCompletionOverlay {
                completionViewModel = makeCompletionViewModel()
                completionReminderPrimer = makeReminderPrimer()
            } else if !isCompleted {
                completionViewModel = nil
                completionReminderPrimer = nil
            }
        }
        .onChange(of: completionViewModel != nil) { _, overlayPresented in
            gameChrome?.setHidingChrome(overlayPresented)
        }
        .focusable()
        .focused($keyboardFocus)
        .onAppear { keyboardFocus = true }
        .onKeyPress(phases: .down, action: handleKeyPress)
        .background(undoRedoShortcuts)
        .task(id: viewModel.identity.puzzleId) {
            // #330 P2: start the looping gameplay BGM when the board appears.
            // The live player auto-yields if another app is already playing
            // audio; under `NoopSoundPlaying` (previews / tests) it's a no-op.
            viewModel.startMusic()
            // #227 elapsed-mirror ticker: `GameViewModel.elapsedSeconds` is
            // only refreshed via `resyncFromSession()` after a mutation, so
            // between user inputs the header label would stay frozen. Poll
            // the session once per second while the game is live; cancel
            // automatically when paused / finished or when the view goes
            // away (`.task` lifecycle handles both).
            // SDD-003 OQ-001: also push to chrome on every tick so the modal
            // top-chrome timer stays in sync with the board session clock.
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refreshElapsed()
                    gameChrome?.updateElapsed(elapsedLabel)
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
            // #330 P2: stop the BGM when the board leaves the screen.
            viewModel.stopMusic()
            Task { await viewModel.flush() }
        }
        // #413: persist before suspension. #539: also pause so the solve timer
        // doesn't accrue background time. #548: pause ONLY on a real `.background`
        // transition — a transient `.inactive` (Control Center / Notification
        // Center pull-down, app-switcher peek) just flushes, so a momentary
        // glance doesn't force a tap-to-resume. `pause()` flushes internally, so
        // when pausing we skip the redundant flush; already-paused/completed only
        // flushes. Matches the in-app Pause path: player taps Resume on return.
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background:
                Task {
                    if viewModel.status == .playing {
                        await viewModel.pause()
                    } else {
                        await viewModel.flush()
                    }
                }
            case .inactive:
                Task { await viewModel.flush() }
            default:
                break
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
                themedBanner(adProvider: adProvider, adGate: adGate)
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
                themedBanner(adProvider: adProvider, adGate: adGate)
            }
        }
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 16)  // additive to outer .padding(16) → ≥ 32 pt
    }

    /// Themed shared `MonetizationUI.BannerSlotView` (#441). Board never drives
    /// ATT (Home owns the primer), so `onAdContext` stays nil. The live provider
    /// conforms to `BannerViewProviding`; fakes / macOS return nil → honest
    /// fallback. The cast keeps SudokuUI free of an AdsAdMob import (§9.1).
    private func themedBanner(adProvider: any AdProvider, adGate: AdGate) -> some View {
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            backgroundColor: theme.surface.placeholder.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
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
    //
    // The header (incl. the #540 Dynamic Type robustness via ViewThatFits)
    // lives in the sibling file BoardView+AccessibilityHeader.swift.

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

    @ViewBuilder
    private func cell(row: Int, column: Int, side: CGFloat) -> some View {
        let index = Board.index(row: row, column: column)
        let digit = viewModel.board.digit(atIndex: index)
        let isGiven = viewModel.board.givenMask[index]
        let isSelected = viewModel.selection.map { $0.row == row && $0.column == column } ?? false
        let isError = viewModel.errorIndices.contains(index)
        let noteMask = viewModel.notes.masks[index]
        let cellView = BoardCellView(
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
        if cellView.isInteractive {
            Button {
                viewModel.select(row: row, column: column)
            } label: {
                cellView
            }
            .buttonStyle(.plain)
        } else {
            // #473: given (clue) cells are non-interactive — no Button wrapper,
            // so VoiceOver announces them as static text (a given's `select()` is
            // already a no-op, #472). Arrow-key navigation still highlights them.
            cellView
        }
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

    // `internal` (not `private`) — the header's `timerLabel` in
    // BoardView+AccessibilityHeader.swift reads this across files.
    var elapsedLabel: String {
        let total = viewModel.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
