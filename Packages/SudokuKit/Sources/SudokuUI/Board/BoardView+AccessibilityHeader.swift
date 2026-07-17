// BoardView+AccessibilityHeader — header layout + Dynamic Type robustness.
//
// Extracted from BoardView.swift to keep that file under SwiftLint's
// file_length ceiling (repo convention: extract a `+Feature.swift` sibling
// rather than disabling the rule).
//
// #540: the header must not clip the difficulty / timer labels off the
// leading edge at ANY text size. An earlier attempt gated a two-row reflow
// on `@Environment(\.dynamicTypeSize).isAccessibilitySize`, but that was
// UNRELIABLE at runtime: when BoardView is presented inside a fullScreenCover
// modal (via GameRoot), the environment value can read a stale `.large` even
// while the Text views are actually scaling via UIFont metrics — so the gate
// never fired and the label still clipped to a negative-x frame.
//
// This version reads NO environment value:
//   1. `ViewThatFits(in: .horizontal)` lets SwiftUI choose the single-row
//      HStack when it fits the ACTUAL offered width, and fall back to a
//      two-row VStack when the enlarged labels would overflow. At default
//      text sizes the HStack always fits → the snapshot baseline is unchanged.
//   2. Belt-and-suspenders: the difficulty + timer labels carry
//      `.lineLimit(1).minimumScaleFactor(0.6)` so the chosen layout shrinks
//      text to fit rather than pushing it off-screen. At default sizes the
//      text already fits, so nothing scales and the pixels are unchanged.

import GameShellUI
import SwiftUI

extension BoardView {
    var header: some View {
        // ViewThatFits proposes each candidate the offered width and renders
        // the FIRST that fits without overflow. Order matters: single-row
        // first (preferred + matches existing baseline), two-row fallback.
        //
        // #540: cap the chrome's Dynamic Type at `.xLarge` so the difficulty /
        // timer labels can't scale tall enough to clip off the leading edge at
        // accessibility sizes (the same compact-control cap the digit pad uses).
        // The cap only clamps sizes ABOVE `.xLarge`, so default `.large` — and
        // every committed snapshot — is byte-identical. The board CELLS keep
        // scaling for puzzle readability; only this compact header is capped.
        ViewThatFits(in: .horizontal) {
            singleRowHeader
            twoRowHeader
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
    }

    // Single-row layout — identical structure to the pre-#540 header, so when
    // ViewThatFits picks this (always true at default text sizes) the snapshot
    // baseline is unchanged.
    private var singleRowHeader: some View {
        // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
        // no matching tier without snapping and changing this header's
        // existing layout/snapshot (#762 PR2).
        HStack(spacing: 12) {
            difficultyLabel
            lateCompletionBadge  // #228 option B: past-day daily marker
            Spacer()
            timerLabel           // #674: always shown here (moved off the modal chrome)
            pauseButton
        }
    }

    // Two-row fallback for when the enlarged labels can't fit one row:
    // row 1 = difficulty + badge; row 2 = timer (leading) + pause (trailing).
    private var twoRowHeader: some View {
        VStack(alignment: .leading, spacing: headerRowGap) {
            HStack(spacing: headerBadgeGap) { difficultyLabel; lateCompletionBadge }
            // spacing-exempt: 12pt predates the 5-tier `SpacingTokens`
            // scale — no matching tier without snapping and changing this
            // header's existing layout/snapshot (#762 PR2).
            HStack(spacing: 12) { timerLabel; Spacer(); pauseButton }
        }
    }

    private var difficultyLabel: some View {
        Text(LocalizedStringKey(viewModel.identity.difficulty.rawValue.capitalized))
            .font(.headline)
            .foregroundStyle(theme.text.primary.resolved)
            // Shrink-to-fit guard: at huge text sizes the label scales down
            // within its slot instead of overflowing off-screen. No effect at
            // default sizes (text already fits → no scaling, same pixels).
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    @ViewBuilder private var lateCompletionBadge: some View {
        if viewModel.isLateCompletion {
            Image(systemName: "clock.badge.exclamationmark")
                .foregroundStyle(theme.text.secondary.resolved)
                .accessibilityLabel(Text("Late completion — won't score on leaderboard"))
        }
    }

    // #674: the modal's separate floating chrome-timer capsule (SDD-003
    // OQ-001) overlapped the board's first grid row on some devices — its
    // `.padding(.top, 56)` was a fixed offset independent of where this
    // header actually landed. The timer now always renders here instead,
    // mirroring Minesweeper's in-status-bar `clockLabel` (#663).
    private var timerLabel: some View {
        Label(elapsedLabel, systemImage: "timer")
            .monospacedDigit()
            .foregroundStyle(theme.text.secondary.resolved)
            .accessibilityLabel("Elapsed time \(elapsedLabel)")
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    // #849 (CR round 2, Finding 1): Sudoku's clock model is NOT the same as
    // MS's, so this is not a straight parity claim — document the asymmetry
    // honestly. MS's `.idle` means "no reveal/flag yet AND the clock hasn't
    // started" (mines aren't even placed). Sudoku's clock starts at
    // `GameSession.start()`, which `BoardLoaderView` calls while the board is
    // still loading — BEFORE this header ever mounts — so by the time a
    // player can see the toolbar, `status` is already `.playing` and the
    // clock is already running (`GameSessionElapsedTests.startAtZero`
    // empirically confirms `elapsedSeconds == 0` at the instant `start()`
    // returns; it only advances once real wall-clock time passes via the
    // 1 Hz ticker in `BoardView`'s `.task`, or a mutation resyncs it).
    //
    // So Sudoku's Ready window is real but much narrower than MS's: only
    // while BOTH `elapsedSeconds == 0` (no wall-clock time has ticked past
    // yet) AND `!canUndo` (no digit placed/erased — `canUndo` mirrors the
    // undo stack, see `GameViewModel.resyncFromSession()`) is pausing
    // genuinely meaningless (nothing accrued to freeze). The instant either
    // condition flips — a second ticks by, or a move is made — Pause must be
    // offered and must actually freeze the clock (`GameSession.pause()`
    // stops `runningSince` accruing into `elapsedSeconds`, verified by
    // `GameSessionElapsedTests.pauseFreezes`). `internal` (not `private`) so
    // `BoardLeaveOrPauseStateTests` can pin the mapping directly, matching
    // this file's existing internal-for-testability convention (see
    // `elapsedLabel` above).
    var leaveOrPauseState: BoardLeaveOrPauseState {
        if viewModel.status == .playing, viewModel.elapsedSeconds == 0, !viewModel.canUndo {
            return .leaveReady
        }
        return viewModel.isPaused ? .resume : .pause
    }

    // #667 (SDD-003 2B, audit P2): hidden at terminal status, mirroring
    // Minesweeper's `pauseToggle` guard. The completion overlay already covers
    // the whole board once solved, so this is defense-in-depth (a stray
    // pre-overlay frame, or the header being inspected directly in a test)
    // rather than new chrome — without it the button stayed visible but dead
    // (pause/resume both no-op on a `.completed` session).
    @ViewBuilder
    private var pauseButton: some View {
        if viewModel.status == .playing || viewModel.isPaused {
            BoardLeaveOrPauseButton(
                state: leaveOrPauseState,
                sizeClass: sizeClass,
                accessibilityIdentifier: "sudoku.board.pauseToggle"
            ) {
                switch leaveOrPauseState {
                case .leaveReady:
                    showReadyLeaveOverlay = true
                case .pause:
                    Task { await viewModel.pause() }
                case .resume:
                    Task { await viewModel.resume() }
                }
            }
            // Palette sweep (#610 fix *5): replace system-blue default with brand accent.
            .tint(theme.accent.primary.resolved)
        }
    }

    // MARK: - Keyboard shortcuts (⌘Z / ⌘⇧Z)

    // Hidden buttons that own the ⌘Z / ⌘⇧Z bindings (Mac App menu picks
    // them up automatically; iPad external keyboards inherit).
    // Moved here from BoardView.swift to keep that file under the 400-line ceiling.
    @ViewBuilder
    var undoRedoShortcuts: some View {
        Group {
            Button("Undo") { Task { await viewModel.undo() } }
                .keyboardShortcut("z", modifiers: .command)
            Button("Redo") { Task { await viewModel.redo() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
        .hidden()
        .accessibilityHidden(true)
    }

    // MARK: - Elapsed label + armed-digit announcement
    //
    // #823: moved here from BoardView.swift (same "keep that file under the
    // 400-line ceiling" rationale as `undoRedoShortcuts` above) after the
    // terminal-persist join wiring pushed it over.

    // `internal` (not `private`) — the header's `timerLabel` above reads
    // this across files (both live in this file now).
    var elapsedLabel: String {
        let total = viewModel.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// #790 fix 2: message posted via `AccessibilityNotification.Announcement`
    /// when `armedDigit` changes. Extracted as a pure `static func` (not
    /// inlined in the `.onChange` closure in BoardView.swift) so the message
    /// text is unit-testable without posting a real accessibility
    /// notification — `AccessibilityNotification.Announcement.post()` itself
    /// has no mock point and requires a live VoiceOver session to observe.
    static func armedAnnouncementMessage(for armedDigit: Int?) -> String {
        if let armedDigit {
            return String(localized: "Digit \(armedDigit) armed", bundle: .main)
        }
        return String(localized: "Digit unarmed", bundle: .main)
    }
}
