import Foundation
import Testing
import GameShellUI
@testable import SudokuAppComposition

@Suite("LiveRouteFactory.reviewPresentation — #1049")
struct LiveRouteFactoryReviewPageTests {
    @Test("a daily puzzleId titles the page with its difficulty and UTC day")
    func dailyPuzzleId() {
        #expect(
            LiveRouteFactory.reviewPresentation(puzzleId: "2026-11-14-medium")
                == .pushedPage(CompletionPageTitle(difficultyKey: "Medium", day: Date(timeIntervalSince1970: 1_794_614_400)))
        )
    }

    @Test("ids that are not a valid daily keep the overlay", arguments: [
        "practice-0A1B2C-hard",
        "2026-11-14-bogus",
        "2026-13-01-easy",
        "easy",
    ])
    func notADaily(puzzleId: String) {
        #expect(LiveRouteFactory.reviewPresentation(puzzleId: puzzleId) == .overlay)
    }
}
