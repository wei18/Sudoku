// DailyHubStoreFrameSnapshotTests — #1021 Phase H: STORE-ONLY marketing-frame
// fixture helpers for `DailyHubViewTests`'s `snapshotAllCompletedIPhoneLight`
// / `snapshotUnfinishedIPadLight` (`scripts/build-ascspec-screenshots.py`'s
// `02-daily` `Slot(...)` entries name those two `@Test` functions directly —
// they feed the App-Store `docs/app-store/screenshots-ascspec/sudoku/.../
// 02-daily.png` frames). Pure `extension DailyHubViewTests` holding fixture
// builders only (no `@Test`s) — split out purely to keep `DailyHubViewTests.
// swift` under the 400-line `file_length` lint ceiling (same rationale as
// `DailyHubViewModel+BestTime.swift` on the production side). The `@Test`s
// themselves stay in `DailyHubViewTests.swift` so swift-snapshot-testing's
// `#filePath`-derived baseline lookup keeps resolving to THAT file's
// `__Snapshots__/DailyHubViewTests/` directory — the marketing script's
// literal path — rather than a directory named after this file.
//
// Their baseline PNGs already existed on disk (orphaned since the Phase B
// `DailyCardContent` rewrite deleted the test functions that used to produce
// them but not the files themselves), frozen on the OLD `PuzzleFixtures.
// latinSquarePuzzle()` fixture: an 80-given near-full grid with no
// completions scripted at all, rendering "0 day streak" and "Not started ·
// 80 givens" under marketing copy that promises a streak (the repo's known
// "marketing assets inherit empty-state fixtures" trap). These fixtures
// replace that stale content with a populated, realistic Today.
//
// Distinct from `snapshotAllDoneIPhoneLight`/`snapshotLoadedAX3IPadLight` in
// `DailyHubViewTests.swift` (the ordinary Phase B state-coverage suite,
// driven by the shared 80-given `makeViewModel` fixture) — those stay
// untouched; only the two store-fed baselines get the richer fixture below.

import Foundation
import SudokuEngine
import SudokuPersistence
import SudokuKitTesting

extension DailyHubViewTests {

    /// A real subset of a known-valid, fully-solved Sudoku grid (Wikipedia's
    /// canonical 9×9 example) kept as clues — unlike `PuzzleFixtures.
    /// latinSquarePuzzle()` (a row-shifted grid satisfying no Sudoku
    /// constraint), every clue here is consistent with actual row/column/box
    /// rules. `(index * 41) % 81` is a fixed bijection over the 81 cells (41
    /// is coprime with 81 = 3^4), so the kept clues spread evenly across the
    /// grid instead of clustering in the first rows — a marketing-frame
    /// thumbnail needs its "solved" vs. "not started" density to look
    /// plausible at a glance, not just be technically well-formed.
    static let storeSolvedGridString =
        "534678912672195348198342567859761423426853791713924856961537284287419635345286179"

    static func storePuzzle(difficulty: Difficulty, givenCount: Int) -> Puzzle {
        let solutionChars = Array(storeSolvedGridString)
        // swiftlint:disable:next force_try
        let solution = try! Board(clues: storeSolvedGridString)
        var cluesChars = Array(repeating: Character("."), count: solutionChars.count)
        for index in solutionChars.indices where (index * 41) % 81 < givenCount {
            cluesChars[index] = solutionChars[index]
        }
        // swiftlint:disable:next force_try
        let clues = try! Board(clues: String(cluesChars))
        return Puzzle(clues: clues, solution: solution, difficulty: difficulty, generatorVersion: .v1, seed: 0)
    }

    /// ~42/32/26 givens (easy/medium/hard) — realistic clue density, not the
    /// 80-given near-full grid the orphaned baselines inherited.
    static func storeDailyTrio(date: Date) -> [PuzzleEnvelope] {
        let givenCounts: [Difficulty: Int] = [.easy: 42, .medium: 32, .hard: 26]
        return Difficulty.allCases.map { difficulty in
            PuzzleEnvelope(
                puzzle: storePuzzle(difficulty: difficulty, givenCount: givenCounts[difficulty] ?? 30),
                identity: PuzzleIdentity.daily(date: date, difficulty: difficulty)
            )
        }
    }

    /// A believable 6-day streak ending today (`offset 0`) — `offset 6` is
    /// left un-scripted so the chain actually breaks there (`current` reads
    /// 6, not the window-capped "7+"), and since `allCompletedDays` only ever
    /// sees these 6 days, `longest` also lands at 6 — non-nil, so the header's
    /// "Best 6" caption renders (design.md §3.1/§4.2, `StreakHeaderView`).
    /// `todayCompletedIds` scripts ONLY today (`offset 0`); the other 5 days
    /// just need any non-empty set to read as completed for the pip/streak
    /// math, so they use throwaway placeholder ids.
    static func seedStoreStreak(persistence: FakePersistence, todayCompletedIds: Set<String>) async {
        for offset in 0...5 {
            let date = Self.fixedDate.addingTimeInterval(-Double(offset) * 86_400)
            let ids = offset == 0 ? todayCompletedIds : ["store-streak-day-\(offset)"]
            await persistence.setCompletedDailyIds(ids, for: date)
        }
    }

    /// A partially-filled `boardState` for the "in progress" card thumbnail
    /// — every OTHER non-given cell is filled with its correct solution
    /// digit, the rest stay blank, so `TodayMapper.inProgressPreview` renders
    /// a genuinely mixed given/filled/empty grid instead of an all-or-nothing
    /// one.
    static func storePartialBoardState(givenMask: [Bool]) -> String {
        let solutionChars = Array(storeSolvedGridString)
        var chars: [Character] = []
        chars.reserveCapacity(solutionChars.count)
        for index in solutionChars.indices {
            if givenMask[index] || index.isMultiple(of: 2) {
                chars.append(solutionChars[index])
            } else {
                chars.append(".")
            }
        }
        return String(chars)
    }
}
