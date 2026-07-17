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
    /// `BoardView` directly) keep working. Non-nil exactly when the board is a
    /// macOS NavigationStack push (iOS boards are fullScreenCover modals, so
    /// `path` is nil there). #667 (SDD-003 2B): the completion overlay is now
    /// the ONE completion presentation on every platform — `path` is read only
    /// by `BoardView+Completion.exitToHub` to pop the board's own stack entry
    /// on Close in the push context (there is no separate pushed `.completion`
    /// route to pop anymore). `internal` (not `private`) — `BoardView+Completion`
    /// reads it.
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
    // #823: join point `completionSurface`'s Close/Play Again handlers
    // register the in-flight terminal-persist Task with, right before
    // dismissing — see `GameAppKit.TerminalPersistJoin`.
    @Environment(\.terminalPersistJoin) private var persistJoin
    @FocusState private var keyboardFocus: Bool
    // #610: Completion overlay VM + Daily primer. Both held in @State so they
    // survive body recomputes without resetting fetch / auth-check state.
    @State var completionViewModel: CompletionViewModel?
    @State var completionReminderPrimer: ReminderPrimerCoordinator?
    // #849: mirrors MinesweeperBoardView's `showIdleLeaveOverlay`. Sudoku has
    // no `.idle` board render, so the Ready signal is "no move made yet on a
    // live session" (`leaveOrPauseState` in BoardView+AccessibilityHeader.swift)
    // — pausing an untouched board is meaningless, so this view-local flag
    // shows the Leave Game overlay without touching session state.
    @State var showReadyLeaveOverlay = false
    // Two-row header content gaps (#762 PR2 spacing contract) — content
    // tier; `internal` so BoardView+AccessibilityHeader.swift can read them.
    @ScaledSpacing(.extraSmall) var headerRowGap
    @ScaledSpacing(.small) var headerBadgeGap

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
        // Structural (#762 PR2) — screen margin; fixed because the board's
        // `GeometryReader` sizes cells from the space this padding leaves.
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        // #610: full-cover Completion overlay (MS #292/#518 mirror).
        // fix *2: pass dismiss so Close returns the user to the hub.
        .overlay {
            if let completionViewModel {
                completionSurface(completionViewModel, dismiss: dismiss, persistJoin: persistJoin)
            }
            // Pause menu — full-screen mask + screen-centred card (merged close+pause).
            // #849: also mounted for `showReadyLeaveOverlay` — Resume then just
            // hides the local flag instead of calling `viewModel.resume()`.
            if viewModel.isPaused || showReadyLeaveOverlay {
                PauseOverlayView(
                    onLeave: { dismiss() },
                    onResume: {
                        if viewModel.isPaused {
                            Task { await viewModel.resume() }
                        } else {
                            showReadyLeaveOverlay = false
                        }
                    }
                )
            }
        }
        // #763: publish whether the overlay above is up, so the macOS split-view
        // shell (RootShellView) can also mask + disable the sidebar — this
        // overlay's `.ignoresSafeArea()` only fills the detail column there, not
        // the whole split view. MUST track the exact same condition as `.overlay`
        // above; see `isModalOverlayActive` (BoardView+Completion.swift).
        .preference(key: BoardModalOverlayActivePreferenceKey.self, value: isModalOverlayActive)
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
        .focusable()
        .focused($keyboardFocus)
        .onAppear { keyboardFocus = true }
        .onKeyPress(phases: .down, action: handleKeyPress)
        // #790 fix 2: arming/disarming a digit silently changes what an empty
        // cell's tap does (select → place), but the only prior signal was the
        // keypad button's `.isSelected` trait — inaudible once VO focus moves
        // to the board. Announce the transition explicitly; `onChange` only
        // fires on an actual value change, so this never double-announces.
        .onChange(of: viewModel.armedDigit) { _, newValue in
            AccessibilityNotification.Announcement(Self.armedAnnouncementMessage(for: newValue)).post()
        }
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
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refreshElapsed()
                }
                try? await Task.sleep(for: .seconds(1))
            }
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

    // MARK: - Compact (iPhone) layout

    private var compactLayout: some View {
        // Structural (#762 PR2 two-tier spacing contract) — screen rhythm
        // between header/board/digit pad; fixed because inflating it would
        // shrink the `GeometryReader`-sized board grid below it.
        VStack(spacing: theme.spacing.medium) {
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
        // Structural (#762 PR2 two-tier spacing contract) — same rationale
        // as `compactLayout` above.
        VStack(spacing: theme.spacing.medium) {
            header
            // Structural — 24 pt gap between board and rail (locked in the
            // Mac wireframe comment above); fixed because it governs how
            // much width `macBoardColumn` gets, which drives its cell size.
            HStack(alignment: .top, spacing: theme.spacing.large) {
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
        // Structural (#762 PR2 two-tier spacing contract) — additive to the
        // outer screen-margin padding above (→ ≥ 32 pt combined); fixed for
        // the same board-sizing reason as that outer padding.
        .padding(.horizontal, theme.spacing.medium)
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
            // #688 item 2: was `theme.surface.placeholder.resolved` — mirrors
            // the MS fix in `MinesweeperBoardView`/`GameHomeView` so both
            // apps' banner containers match their own page background
            // instead of a "card" tone that reads as a seam in dark mode.
            backgroundColor: theme.surface.background.resolved,
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
            remainingCounts: (1...9).map { dgt in max(0, 9 - viewModel.board.cells.filter { $0 == UInt8(dgt) }.count) },
            armedDigit: viewModel.armedDigit,
            hasSelection: viewModel.selection != nil,
            // #722: routing (place-into-selection vs arm/disarm) lives on the
            // VM (`keypadDigit`), matching every other mutation on this board.
            onDigit: { digit in Task { await viewModel.keypadDigit(digit) } },
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
                // spacing-exempt: zero-gap — the board grid's own row/column
                // seams are cell geometry, not a spacing decision (#762 PR2).
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
            }
            // Centre the square grid within the GR's offered rectangle so
            // the board sits inline with the surrounding header/digit pad
            // padding instead of sticking to the leading edge.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
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
            Task { await dispatchKeyboardDigit(digit) }
            return .handled
        }
        return .ignored
    }

    /// #790 fix 1: keyboard digits now share the SAME `keypadDigit` arm/place/
    /// pencil-note dispatch as the pointer-driven digit pad (`digitPad`'s
    /// `onDigit:` closure above) — previously this called `placeDigit(_:)`
    /// directly, which silently no-ops when nothing is selected (no way to
    /// arm a digit from the keyboard at all). `internal` (not `private`) so
    /// `BoardViewKeyboardDigitTests` can exercise it directly: SwiftUI's
    /// `KeyPress` has no public initializer (confirmed against Apple's
    /// Accessibility/SwiftUI sample code, which only ever receives one from
    /// `onKeyPress`'s closure, never constructs one), so the full
    /// `onKeyPress` → `handleKeyPress` chain isn't unit-testable — this is
    /// the closest testable proxy for "what a digit key does."
    func dispatchKeyboardDigit(_ digit: Int) async {
        await viewModel.keypadDigit(digit)
    }

    // #823: `elapsedLabel` + `armedAnnouncementMessage` moved to
    // BoardView+AccessibilityHeader.swift (same file-split rationale as that
    // file's header extraction) to keep this file under the 400-line lint
    // ceiling after the terminal-persist join wiring landed.
}
