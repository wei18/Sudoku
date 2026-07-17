// BoardLeaveOrPauseControl — shared state→label/icon mapping for the board
// header's single leave/pause toggle button (#849).
//
// Minesweeper's board header was already state-aware: before the first
// reveal/flag (`.idle`), the control reads "Leave" + ✕ and opens the Leave
// Game confirm directly (an untouched board has nothing to pause); once a
// move has been made it flips to the familiar Pause/Resume + bars toggle.
// Sudoku's board header never grew that first branch — it showed "Pause"
// unconditionally, even before any digit was placed, which still led to the
// SAME "Leave Game?" sheet (Sudoku has no real pause feature yet either) but
// under a mismatched label/icon. #849 adjudicated: adopt MS's state-aware
// mapping in Sudoku via this shared, pure presentation type — no new pause
// feature, just killing the drift.
//
// Pure data + a small SwiftUI button — no game-state types, so this lives in
// the zero-dependency GameShellUI (not GameAppKit). Each app derives its own
// `BoardLeaveOrPauseState` from its own session status + "has the player
// made a move yet" signal (MS: `status == .idle`; Sudoku: `status ==
// .playing && !canUndo` — see `GameViewModel.canUndo`, Sudoku has no `.idle`
// board render since `startOrResume()` fires on load, before the toolbar
// mounts, so "no move made" is the semantically equivalent Ready signal).

public import SwiftUI

/// What the shared leave/pause toggle should show right now.
public enum BoardLeaveOrPauseState: Equatable, Sendable {
    /// No move has been made yet on this board — pausing is meaningless (there
    /// is nothing to freeze), so tapping should go straight to the Leave Game
    /// confirm instead of a real pause.
    case leaveReady
    /// A move has been made and the session is live — tapping pauses.
    case pause
    /// The session is paused — tapping resumes.
    case resume

    /// Catalog key for both the visible label (Mac/regular) and the
    /// accessibility label. Reuses existing keys already localized in both
    /// apps' catalogs (`leave.game.leave` from the shared Leave Game sheet,
    /// `Pause`/`Resume` from the pre-#849 per-app toggles) — no new strings.
    public var labelKey: LocalizedStringKey {
        switch self {
        case .leaveReady: "leave.game.leave"
        case .pause: "Pause"
        case .resume: "Resume"
        }
    }

    /// SF Symbol shown icon-only on compact (iPhone) width.
    public var systemImage: String {
        switch self {
        case .leaveReady: "xmark"
        case .pause: "pause.fill"
        case .resume: "play.fill"
        }
    }
}

/// The board header's single leave/pause toggle. Icon + text on regular
/// (Mac/iPad) width, icon-only on compact (iPhone) width — matches the
/// pre-#849 per-app buttons' sizing contract exactly, so this is a
/// pixel-identical swap wherever the resolved `state` is unchanged.
public struct BoardLeaveOrPauseButton: View {
    private let state: BoardLeaveOrPauseState
    private let sizeClass: UserInterfaceSizeClass?
    private let accessibilityIdentifier: String
    private let action: () -> Void

    public init(
        state: BoardLeaveOrPauseState,
        sizeClass: UserInterfaceSizeClass?,
        accessibilityIdentifier: String,
        action: @escaping () -> Void
    ) {
        self.state = state
        self.sizeClass = sizeClass
        self.accessibilityIdentifier = accessibilityIdentifier
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            if sizeClass == .regular {
                Label(state.labelKey, systemImage: state.systemImage)
            } else {
                Image(systemName: state.systemImage)
            }
        }
        // #647/#688 parity: ≥44×44 pt tap target without enlarging the glyph,
        // stable per-app accessibility identifier for UI-test hooks.
        .frame(minWidth: 44, minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityLabel(Text(state.labelKey))
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
