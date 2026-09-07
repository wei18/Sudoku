// SudokuPracticeCardsMapperTests — #1021 Phase C.
//
// Pins the mapper's pure output: 3 cards (one per `Difficulty`), the
// representative givens count per card's `detail`/thumbnail fill ratio, and
// that the fixed per-difficulty seed makes the thumbnail stable across calls
// (no per-render re-roll, no drift toward a real puzzle's actual layout).

import Testing
import GameShellUI
@testable import SudokuUI
import SudokuEngine

@Suite("SudokuPracticeCardsMapper")
struct SudokuPracticeCardsMapperTests {

    @Test("produces exactly 3 cards, one per Difficulty, in Difficulty.allCases order")
    func producesThreeCards() {
        let cards = SudokuPracticeCardsMapper.cards()
        #expect(cards.count == 3)
        #expect(cards.map(\.id) == Difficulty.allCases.map(\.rawValue))
    }

    @Test("pip level increases with difficulty")
    func pipLevelsMatchDifficulty() {
        #expect(SudokuPracticeCardsMapper.card(for: .easy).pipLevel == 1)
        #expect(SudokuPracticeCardsMapper.card(for: .medium).pipLevel == 2)
        #expect(SudokuPracticeCardsMapper.card(for: .hard).pipLevel == 3)
    }

    @Test("detail reports the representative givens count")
    func detailReportsGivens() {
        #expect(SudokuPracticeCardsMapper.card(for: .easy).detail == "~40 givens")
        #expect(SudokuPracticeCardsMapper.card(for: .medium).detail == "~33 givens")
        #expect(SudokuPracticeCardsMapper.card(for: .hard).detail == "~26 givens")
    }

    @Test("preview is a 9×9 board with the given mark")
    func previewIsNineByNineGiven() {
        let card = SudokuPracticeCardsMapper.card(for: .medium)
        #expect(card.preview.columns == 9)
        #expect(card.preview.rows == 9)
        #expect(card.preview.cells.allSatisfy { $0 == .empty || $0 == .given })
    }

    @Test("preview fill count matches the representative givens count")
    func previewFillCountMatchesGivens() {
        let card = SudokuPracticeCardsMapper.card(for: .easy)
        let filled = card.preview.cells.filter { $0 == .given }.count
        #expect(filled == 40)
    }

    @Test("same difficulty's fixed seed produces an identical preview across calls")
    func stableSeedProducesEqualPreviews() {
        let first = SudokuPracticeCardsMapper.card(for: .hard).preview
        let second = SudokuPracticeCardsMapper.card(for: .hard).preview
        #expect(first == second)
    }

    @Test("different difficulties get different fixed seeds (previews differ)")
    func differentDifficultiesDiffer() {
        let easy = SudokuPracticeCardsMapper.card(for: .easy).preview
        let medium = SudokuPracticeCardsMapper.card(for: .medium).preview
        #expect(easy != medium)
    }
}
