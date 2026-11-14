import Foundation
import Testing
import GameShellUI
import MinesweeperEngine
import MinesweeperUI
@testable import MinesweeperAppComposition

@Suite("LiveRouteFactory.reviewPresentation — #1049")
struct LiveRouteFactoryReviewPageTests {
    @Test("a daily review with its day titles the page")
    func dailyWithDay() {
        #expect(
            LiveRouteFactory.reviewPresentation(difficulty: .intermediate, mode: .daily, day: "2026-11-14")
                == .pushedPage(CompletionPageTitle(difficultyKey: "Intermediate", day: Date(timeIntervalSince1970: 1_794_614_400)))
        )
    }

    @Test("no day, a malformed day, or a non-daily mode keeps the overlay")
    func overlayFallbacks() {
        #expect(LiveRouteFactory.reviewPresentation(difficulty: .expert, mode: .daily, day: nil) == .overlay)
        #expect(LiveRouteFactory.reviewPresentation(difficulty: .expert, mode: .daily, day: "2026-11") == .overlay)
        #expect(LiveRouteFactory.reviewPresentation(difficulty: .expert, mode: .practice, day: "2026-11-14") == .overlay)
    }
}
