// MinesweeperGameViewModel+RevealAudio — the reveal-outcome → audio-event
// classification (#330 P2), moved verbatim out of MinesweeperGameViewModel.swift
// (#1018) to keep that file under the 400-line lint ceiling. No behaviour
// change; `soundPlayer` widened from `private` to internal so this file can
// reach it, the same file-split treatment as `isSeeded`.

public import MinesweeperEngine
public import MinesweeperGameState

extension MinesweeperGameViewModel {
    // MARK: - Audio classification (#330 P2)

    /// Number of currently-revealed cells in a snapshot — used to tell a single
    /// reveal (delta 1) from a flood-clear (delta > 1).
    func revealedCount(in snapshot: MinesweeperSessionSnapshot) -> Int {
        var count = 0
        for cell in snapshot.cells where cell.state == .revealed { count += 1 }
        return count
    }

    /// Map the outcome of a `reveal` onto exactly one audio event:
    ///   - crossed into `.lost`  → explosion (mine hit)
    ///   - crossed into `.won`   → win
    ///   - revealed > 1 new cell → floodClear
    ///   - revealed exactly 1    → reveal (SFX only)
    ///   - revealed 0            → silent (tap on an already-revealed/flagged cell)
    /// Win/lose take precedence over the cell-delta so a winning flood-clear plays
    /// the win cue, not the flood cue.
    func fireRevealAudio(previousStatus: MinesweeperSessionStatus, revealedBefore: Int) {
        let status = snapshot.status
        if status == .lost, previousStatus != .lost {
            soundPlayer.play(.minesweeperExplosion)
            return
        }
        if status == .won, previousStatus != .won {
            soundPlayer.play(.minesweeperWin)
            return
        }
        let delta = revealedCount(in: snapshot) - revealedBefore
        if delta > 1 {
            soundPlayer.play(.minesweeperFloodClear)
        } else if delta == 1 {
            soundPlayer.play(.minesweeperReveal)
        }
    }
}
