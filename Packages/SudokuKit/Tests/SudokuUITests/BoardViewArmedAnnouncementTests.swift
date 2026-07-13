// BoardViewArmedAnnouncementTests — #790 fix 2: the VoiceOver announcement
// posted when a digit-first digit arms/disarms (BoardView's
// `.onChange(of: viewModel.armedDigit)`, wired in BoardView.swift body).
//
// `AccessibilityNotification.Announcement.post()` itself has no mock point
// and requires a live VoiceOver session to observe, so this locks the
// extracted, pure `armedAnnouncementMessage(for:)` — the message text is the
// only part of this side effect that can be verified headlessly.

import Testing
@testable import SudokuUI

@Suite("BoardView — armed-digit announcement message (#790 fix 2)")
struct BoardViewArmedAnnouncementTests {

    @Test func armed_announcesTheDigit() {
        #expect(BoardView.armedAnnouncementMessage(for: 5) == "Digit 5 armed")
    }

    @Test func disarmed_announcesUnarmed() {
        #expect(BoardView.armedAnnouncementMessage(for: nil) == "Digit unarmed")
    }
}
