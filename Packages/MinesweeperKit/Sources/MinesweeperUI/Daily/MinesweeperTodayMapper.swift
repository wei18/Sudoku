// MinesweeperTodayMapper — pure (MinesweeperDailyHubState, weekStrip) →
// (TodayPresentation<DailyCardModel>, StreakHeaderModel) mapping (#1021
// Phase B, design.md §3.1). Mirrors `SudokuUI.TodayMapper` — see that file's
// header for the shared rationale, not repeated in full here.
//
// D21 (design.md §3.1): MS has NO `exhausted`/`failed` hub state —
// `dailyTrio(date:)` is synchronous and non-throwing — so `present`'s switch
// over `MinesweeperDailyHubState` is exhaustive with NO `.exhausted` case to
// map at all; `MinesweeperTodayMapperTests` asserts every state × degraded
// combination structurally can never produce `.exhausted`.
//
// #1021 CR2 M7: Sudoku's `TodayMapper` gained a `.failed → .degraded`
// "Not started" skeleton-card render for its phase-1 fetch failure this
// pass. There is NO equivalent here — see the D21 paragraph above: MS's
// phase-1 (`dailyTrio(date:)`) cannot throw, so there is no MS state this
// would ever apply to. Deliberately not inventing one just for parity.
//
// Card status text (spec B): completed → "Solved · m:ss"/"Solved"; failed →
// "Failed"; in progress (matches `inProgress`'s record name, not completed) →
// "In progress · m:ss"/"In progress"; not started → "Not started · R × C ·
// M mines".
//
// #1021 Phase B (Leader ruling — supersedes the original in-progress
// deviation): `MinesweeperDailyOverlayReading` was widened (additively) to
// expose `latestInProgress()` — `MinesweeperSavedGameStore` already
// implemented it for the resume-pill seam, so this is pure exposure, not a
// new capability. `inProgress`'s record name IS the daily puzzleId
// (`MinesweeperSavedGameStore.latestInProgress()`'s daily branch uses
// `daily-<day>-<difficulty>`, byte-identical to `MinesweeperDaily.puzzleId`),
// so matching against `card.id` needs no extra parsing.
//
// KNOWN DEVIATION (solved/failed thumbnails, spec C): `MinesweeperEngine`
// defers mine placement until the FIRST reveal, salted by that reveal's
// (row, col) (`MinesweeperEngine.swift`'s "Mine placement (deferred)"
// section) — there is no seed-only mine layout to reconstruct for a board
// that either hasn't been played yet (not-started, fine — no mines to draw)
// or WAS already played elsewhere (solved/failed, where the real layout
// depends on a first click this mapper never sees). Building one would need
// a persisted per-day layout read this phase's forbidden list rules out (no
// new CloudKit reads beyond `latestInProgress()` + the by-day read, and MS
// gets neither of those for its trio's own solved/failed cards). Per the
// dispatch's own escape hatch ("if it is not pure/cheap, use `.filled` for
// all cells on solved and report the deviation"), solved AND failed both
// render as a uniform `.filled` board at the difficulty's true dimensions —
// density-only (matches the actual mine density visually not at all, but
// never fabricates a layout that didn't happen).

import Foundation
internal import GameShellUI
import MinesweeperEngine
import MinesweeperGameState
import MinesweeperPersistence

enum MinesweeperTodayMapper {

    /// design.md §3.1 "保留格線結構,不是空白方塊" — 3 skeleton cards, one per
    /// daily difficulty, so the `loading:` grid never reflows once real data
    /// lands (dims matter here, unlike Sudoku's uniform 9×9).
    static func skeletonCards() -> [DailyCardModel] {
        MinesweeperDaily.dailyDifficulties.enumerated().map { index, difficulty in
            DailyCardModel(
                id: "today-skeleton-\(index)",
                title: "",
                pipLevel: 0,
                statusText: "",
                preview: BoardPreview(
                    columns: difficulty.columns,
                    rows: difficulty.rows,
                    cells: Array(repeating: .empty, count: difficulty.columns * difficulty.rows)
                ),
                isSkeleton: true,
                isCompleted: false,
                accessibilityIdentifier: nil
            )
        }
    }

    static func present(
        state: MinesweeperDailyHubState,
        inProgress: MinesweeperSavedGameSummary?,
        isPhase2Degraded: Bool
    ) -> TodayPresentation<DailyCardModel> {
        switch state {
        case .idle, .loading:
            return .loading
        case .loaded(let cards):
            let mapped = cards.map { cardModel(card: $0, inProgress: inProgress, forceNotStarted: isPhase2Degraded) }
            if isPhase2Degraded {
                // #1021 CR3: MS only ever produces `.completionStatusUnknown`
                // — `dailyTrio(date:)` is synchronous and non-throwing (D21
                // above), so there is no MS phase-1 failure this mapper could
                // ever map to `.loadFailed`. Not inventing one just for parity
                // with `TodayLoadFailureCaption`; see `TodayPresentation.
                // DegradedReason`'s doc.
                return .degraded(mapped, reason: .completionStatusUnknown)
            }
            if !mapped.isEmpty, mapped.allSatisfy(\.isCompleted) {
                return .allDone(mapped)
            }
            return .loaded(mapped)
        }
    }

    // #1021 CR2 MINOR: `today` is now injected (mirrors Sudoku's
    // `TodayMapper.headerModel(weekStrip:allCompletedDays:today:)`) instead
    // of this mapper calling `Date()` itself — keeps it a pure function of
    // its arguments, testable without a wall-clock dependency.
    static func headerModel(
        weekStrip: MinesweeperDailyStripSnapshot,
        allCompletedDays: Set<DayKey>,
        today: DayKey
    ) -> StreakHeaderModel {
        guard !weekStrip.days.isEmpty else {
            return .skeleton
        }
        let longest = StreakHistory(completedDays: allCompletedDays, today: today).longest
        let tappableIndices = Set(weekStrip.days.enumerated().compactMap { index, day in
            (day.isReviewable && !day.isToday) ? index : nil
        })
        let labels = weekStrip.days.map(pipAccessibilityLabel(for:))
        return StreakHeaderModel(
            current: weekStrip.streak ?? 0,
            longest: longest > 0 ? longest : nil,
            last7: weekStrip.days.map(\.isCompleted),
            isSkeleton: false,
            tappablePipIndices: tappableIndices,
            pipAccessibilityLabels: labels
        )
    }

    private static func pipAccessibilityLabel(for day: MinesweeperDailyStripDay) -> String {
        let weekday = day.date.formatted(.dateTime.weekday(.wide))
        return day.isCompleted
            ? String(localized: "\(weekday), completed", bundle: .main)
            : String(localized: "\(weekday), missed", bundle: .main)
    }

    // MARK: - Card mapping

    private static func cardModel(
        card: MinesweeperDailyCard,
        inProgress: MinesweeperSavedGameSummary?,
        forceNotStarted: Bool
    ) -> DailyCardModel {
        let isCompleted = !forceNotStarted && card.isCompleted
        let isFailed = !forceNotStarted && !isCompleted && card.isFailed
        let matchesInProgress = inProgress?.recordName == card.id
        let isInProgress = !forceNotStarted && !isCompleted && !isFailed && matchesInProgress
        return DailyCardModel(
            id: card.id,
            title: title(for: card.difficulty),
            pipLevel: pipLevel(for: card.difficulty),
            statusText: statusText(card: card, isCompleted: isCompleted, isFailed: isFailed, isInProgress: isInProgress, inProgress: inProgress),
            preview: thumbnail(card: card, isCompleted: isCompleted, isFailed: isFailed, isInProgress: isInProgress, inProgress: inProgress),
            isSkeleton: false,
            isCompleted: isCompleted,
            accessibilityIdentifier: isCompleted ? "minesweeper.dailyHub.card.completed" : nil
        )
    }

    private static func title(for difficulty: Difficulty) -> String {
        let key = nameKey(difficulty)
        return Bundle.main.localizedString(forKey: key, value: key, table: nil)
    }

    private static func nameKey(_ difficulty: Difficulty) -> String {
        switch difficulty {
        case .beginner: return "Beginner"
        case .intermediate: return "Intermediate"
        case .expert: return "Expert"
        }
    }

    private static func pipLevel(for difficulty: Difficulty) -> Int {
        switch difficulty {
        case .beginner: return 1
        case .intermediate: return 2
        case .expert: return 3
        }
    }

    private static func statusText(
        card: MinesweeperDailyCard,
        isCompleted: Bool,
        isFailed: Bool,
        isInProgress: Bool,
        inProgress: MinesweeperSavedGameSummary?
    ) -> String {
        if isCompleted {
            guard let best = card.bestTimeSeconds else {
                return String(localized: "Solved", bundle: .main)
            }
            return String(localized: "Solved · \(timeLabel(best))", bundle: .main)
        }
        if isFailed {
            return String(localized: "Failed", bundle: .main)
        }
        if isInProgress, let inProgress {
            return String(localized: "In progress · \(timeLabel(inProgress.elapsedSeconds))", bundle: .main)
        }
        let difficulty = card.difficulty
        return String(
            localized: "Not started · \(difficulty.rows) × \(difficulty.columns) · \(difficulty.mineCount) mines",
            bundle: .main
        )
    }

    private static func timeLabel(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    // MARK: - Thumbnails (see the file header's "solved/failed" deviation note)

    private static func thumbnail(
        card: MinesweeperDailyCard,
        isCompleted: Bool,
        isFailed: Bool,
        isInProgress: Bool,
        inProgress: MinesweeperSavedGameSummary?
    ) -> BoardPreview? {
        let difficulty = card.difficulty
        if isInProgress, let inProgress, let preview = inProgressPreview(stateBlob: inProgress.stateBlob) {
            return preview
        }
        if isCompleted || isFailed {
            let marks = Array(repeating: CellMark.filled, count: difficulty.rows * difficulty.columns)
            return BoardPreview(columns: difficulty.columns, rows: difficulty.rows, cells: marks)
        }
        let marks = Array(repeating: CellMark.empty, count: difficulty.rows * difficulty.columns)
        return BoardPreview(columns: difficulty.columns, rows: difficulty.rows, cells: marks)
    }

    /// Decodes the in-progress summary's `stateBlob` into a `BoardPreview` —
    /// same mapping `MinesweeperAppComposition.MinesweeperBoardPreviewMapper.
    /// make(stateBlob:)` uses for the resume pill (hidden→empty,
    /// revealed→filled, flagged→marked), but inlined here rather than
    /// imported: `MinesweeperAppComposition` depends on `MinesweeperUI`, not
    /// the reverse, so that mapper can't cross into this target. `nil` on
    /// any decode failure — never blocks the card, just falls back to the
    /// not-started render above.
    private static func inProgressPreview(stateBlob: Data?) -> BoardPreview? {
        guard let stateBlob,
              let snapshot = try? JSONDecoder().decode(MinesweeperSessionSnapshot.self, from: stateBlob)
        else { return nil }
        let marks = snapshot.cells.map { cell -> CellMark in
            switch cell.state {
            case .hidden: return .empty
            case .revealed: return .filled
            case .flagged: return .marked
            }
        }
        return BoardPreview(columns: snapshot.columns, rows: snapshot.rows, cells: marks)
    }
}
