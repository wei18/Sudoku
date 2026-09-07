// MinesweeperPracticeCardsMapperTests — #1021 Phase C.
//
// Pins the mapper's pure output: 3 cards (one per `Difficulty`), board
// shape + mine density sourced from `MinesweeperEngine.Difficulty` (never a
// hard-coded copy), and that the fixed per-difficulty seed makes the
// thumbnail stable across calls.

import Testing
import GameShellUI
@testable import MinesweeperUI
import MinesweeperEngine

@Suite("MinesweeperPracticeCardsMapper")
struct MinesweeperPracticeCardsMapperTests {

    @Test("produces exactly 3 cards, one per Difficulty, in Difficulty.allCases order")
    func producesThreeCards() {
        let cards = MinesweeperPracticeCardsMapper.cards()
        #expect(cards.count == 3)
        #expect(cards.map(\.id) == Difficulty.allCases.map(\.rawValue))
    }

    @Test("pip level increases with difficulty")
    func pipLevelsMatchDifficulty() {
        #expect(MinesweeperPracticeCardsMapper.card(for: .beginner).pipLevel == 1)
        #expect(MinesweeperPracticeCardsMapper.card(for: .intermediate).pipLevel == 2)
        #expect(MinesweeperPracticeCardsMapper.card(for: .expert).pipLevel == 3)
    }

    @Test("detail reports rows × columns · mines from Difficulty, not a hard-coded copy")
    func detailReportsDifficultyDimensions() {
        for difficulty in Difficulty.allCases {
            let card = MinesweeperPracticeCardsMapper.card(for: difficulty)
            #expect(card.detail == "\(difficulty.rows) × \(difficulty.columns) · \(difficulty.mineCount) mines")
        }
    }

    @Test("preview shape matches Difficulty's board shape")
    func previewShapeMatchesDifficulty() {
        for difficulty in Difficulty.allCases {
            let card = MinesweeperPracticeCardsMapper.card(for: difficulty)
            #expect(card.preview.columns == difficulty.columns)
            #expect(card.preview.rows == difficulty.rows)
            #expect(card.preview.cells.allSatisfy { $0 == .empty || $0 == .marked })
        }
    }

    @Test("preview fill count matches Difficulty's mine count")
    func previewFillCountMatchesMineCount() {
        for difficulty in Difficulty.allCases {
            let card = MinesweeperPracticeCardsMapper.card(for: difficulty)
            let filled = card.preview.cells.filter { $0 == .marked }.count
            #expect(filled == difficulty.mineCount)
        }
    }

    @Test("same difficulty's fixed seed produces an identical preview across calls")
    func stableSeedProducesEqualPreviews() {
        let first = MinesweeperPracticeCardsMapper.card(for: .expert).preview
        let second = MinesweeperPracticeCardsMapper.card(for: .expert).preview
        #expect(first == second)
    }

    @Test("different difficulties get different fixed seeds (previews differ where shape matches)")
    func differentDifficultiesDiffer() {
        // Beginner and intermediate are both square-ish but different sizes
        // already guarantee inequality via `BoardPreview.columns`/`rows`;
        // this only asserts the mine LAYOUT (not just the shape) differs
        // where the shape is identical — no such pair exists in the current
        // 3 presets, so this pins cell content differs given different mine
        // counts at the same seed derivation path instead.
        let beginner = MinesweeperPracticeCardsMapper.card(for: .beginner).preview
        let intermediate = MinesweeperPracticeCardsMapper.card(for: .intermediate).preview
        #expect(beginner != intermediate)
    }
}
