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
        HStack(spacing: 12) {
            difficultyLabel
            lateCompletionBadge  // #228 option B: past-day daily marker
            Spacer()
            timerLabel           // SDD-003: hidden when gameChrome != nil
            pauseButton
        }
    }

    // Two-row fallback for when the enlarged labels can't fit one row:
    // row 1 = difficulty + badge; row 2 = timer (leading) + pause (trailing).
    private var twoRowHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) { difficultyLabel; lateCompletionBadge }
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

    // SDD-003 OQ-001: suppress the in-board timer when the chrome shows it.
    @ViewBuilder private var timerLabel: some View {
        if gameChrome == nil {
            Label(elapsedLabel, systemImage: "timer")
                .monospacedDigit()
                .foregroundStyle(theme.text.secondary.resolved)
                .accessibilityLabel("Elapsed time \(elapsedLabel)")
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
    }

    private var pauseButton: some View {
        Button {
            Task {
                if viewModel.isPaused { await viewModel.resume() } else { await viewModel.pause() }
            }
        } label: {
            if sizeClass == .regular {
                Label(  // Mac: icon + text per board-mac-redesign wireframe.
                    viewModel.isPaused ? "Resume" : "Pause",
                    systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                )
            } else {
                Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
            }
        }
        // Palette sweep (#610 fix *5): replace system-blue default with brand accent.
        .tint(theme.accent.primary.resolved)
        .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")
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
}
