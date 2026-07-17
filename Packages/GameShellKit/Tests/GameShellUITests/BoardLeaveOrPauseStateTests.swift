// BoardLeaveOrPauseStateTests — pins the #849 shared state→label/icon
// mapping. Each app derives its own `BoardLeaveOrPauseState` from its own
// session status (see `MinesweeperLeaveOrPauseStateTests` /
// `BoardLeaveOrPauseStateTests` in each app's UI test target); this suite
// pins the mapping itself, independent of either game's state types.

import Testing
@testable import GameShellUI

@Suite("BoardLeaveOrPauseState (#849)")
struct BoardLeaveOrPauseStateTests {

    @Test("leaveReady resolves to the Leave Game label + xmark icon")
    func leaveReadyMapping() {
        #expect(BoardLeaveOrPauseState.leaveReady.labelKey == "leave.game.leave")
        #expect(BoardLeaveOrPauseState.leaveReady.systemImage == "xmark")
    }

    @Test("pause resolves to the Pause label + pause.fill icon")
    func pauseMapping() {
        #expect(BoardLeaveOrPauseState.pause.labelKey == "Pause")
        #expect(BoardLeaveOrPauseState.pause.systemImage == "pause.fill")
    }

    @Test("resume resolves to the Resume label + play.fill icon")
    func resumeMapping() {
        #expect(BoardLeaveOrPauseState.resume.labelKey == "Resume")
        #expect(BoardLeaveOrPauseState.resume.systemImage == "play.fill")
    }

    @Test("the three states are pairwise distinct")
    func statesAreDistinct() {
        let states: [BoardLeaveOrPauseState] = [.leaveReady, .pause, .resume]
        for lhs in states {
            for rhs in states where rhs != lhs {
                #expect(lhs != rhs)
            }
        }
    }
}
