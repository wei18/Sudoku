// BoardView — 9×9 grid + control cluster + pause overlay.
//
// Per docs/designs/05-board.md + docs/v1/design.md §How.5.7 (A11y). The board
// GRID itself still carries no glass (§How.5.1, design.md §3.4 "盤面(內容層)
// …不用玻璃"); #1022's G4 glass lives only in the control cluster around it.
// Mac keyboard: `.focusable()` + `.onKeyPress` for arrows / 1–9 / 0 / delete /
// `p`; ⌘Z / ⌘⇧Z bound for undo / redo.

public import SwiftUI
public import GameCenterClient
internal import GameAppKit
// #1023 Phase B: `public` — `fetchStreakAdvance`'s public init param exposes
// GameShellUI's `CompletionStreakAdvance` in this view's public API.
public import GameShellUI
import MonetizationUI
public import SudokuEngine
public import SettingsUI

public struct BoardView: View {
    // Several members are `internal` (not `private`) because the header
    // helpers in BoardView+AccessibilityHeader.swift read them across files
    // within the same module.
    @Bindable var viewModel: GameViewModel
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
    // #1023: resolves the post-Daily-solve CTA row (§3.5); see BoardView+Completion.
    let fetchDailyProgress: (@MainActor () async -> DailyCompletionProgress)?
    let onDailyNext: ((String) -> Void)?
    // #1023 Phase B: resolves the M3/M4 streak-ritual pre/post state on a
    // Daily solve; see BoardView+Completion.kickOffDailyProgressFetch.
    let fetchStreakAdvance: (@MainActor () async -> CompletionStreakAdvance?)?
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
    // #1023: `.allDone` default — never claims a "Next" mid-fetch.
    @State var dailyCompletionProgress: DailyCompletionProgress = .allDone
    // #1023 Phase B: `nil` default — no streak section renders until (and
    // unless) `fetchStreakAdvance` resolves a value.
    @State var streakAdvance: CompletionStreakAdvance?
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
        gameCenter: (any GameCenterClient)? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        fetchDailyProgress: (@MainActor () async -> DailyCompletionProgress)? = nil,
        onDailyNext: ((String) -> Void)? = nil,
        fetchStreakAdvance: (@MainActor () async -> CompletionStreakAdvance?)? = nil,
        path: Binding<[AppRoute]>? = nil
    ) {
        self.viewModel = viewModel
        self.gameCenter = gameCenter
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.onPlayAgain = onPlayAgain
        self.fetchDailyProgress = fetchDailyProgress
        self.onDailyNext = onDailyNext
        self.fetchStreakAdvance = fetchStreakAdvance
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
        // #1022: the blanket screen margin is GONE from here — design.md §3.4
        // puts the board edge-to-edge, and a padding here would inset it by
        // definition. Each layout owns its own margins instead.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.surface.background.resolved)
        // #610: full-cover Completion overlay (MS #292/#518 mirror).
        // fix *2: pass dismiss so Close returns the user to the hub.
        // #763/#1019/#1020: one key drives both this rendering and the hoisted
        // copy the shell shows when the board is pushed inside a tab — see
        // `BoardModalOverlayHoist.swift` for the in-place vs. hoisted split.
        .boardModalOverlay(presentation: modalOverlayPresentation) {
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
        // #610: build VM+primer on .completed; clear on Close. CR #518-R2: keyed on
        // overlay presence so Close restores chrome. `shouldPresentCompletionOverlay`
        // gates to path==nil — macOS (path!=nil) uses push path, no double-present.
        .onChange(of: viewModel.status == .completed) { _, isCompleted in
            if isCompleted, completionViewModel == nil, shouldPresentCompletionOverlay {
                completionViewModel = makeCompletionViewModel()
                completionReminderPrimer = makeReminderPrimer()
                kickOffDailyProgressFetch()
                kickOffStreakAdvanceFetch()
            } else if !isCompleted {
                completionViewModel = nil
                completionReminderPrimer = nil
                dailyCompletionProgress = .allDone
                streakAdvance = nil
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

    // #823: `elapsedLabel` + `armedAnnouncementMessage` moved to
    // BoardView+AccessibilityHeader.swift (same file-split rationale as that
    // file's header extraction); keyboard handling (`handleKeyPress` /
    // `dispatchKeyboardDigit`) moved to BoardView+Keyboard.swift (#1023), and
    // both layouts to BoardView+Layout.swift (#1022) — all to keep this file
    // under the 400-line lint ceiling.
}
