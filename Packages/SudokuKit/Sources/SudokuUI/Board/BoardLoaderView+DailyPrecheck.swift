// BoardLoaderView+DailyPrecheck — #842 daily open-time precheck.
//
// Extracted from BoardLoaderView.swift purely to keep that file under
// SwiftLint's 400-line `file_length` ceiling (repo convention: extract a
// `+Feature.swift` sibling rather than disabling the rule) — this is the same
// loader, not a separate concern. See `BoardLoaderView.swift`'s header
// comment for the full #842 rationale (why this seam, why `loadIfExists`, why
// the redirect is inline rather than a pushed `.completion` route).

public import Persistence
import SudokuGameState
import SudokuPersistence
import Telemetry

extension BoardLoaderView {

    /// #842 testable core, mirroring `MinesweeperDailyReplayLoaderView
    /// .makeReplaySession`'s pattern: the daily precheck's decision, decoupled
    /// from `@State`, so a unit test can gate/hang the fetch and assert the
    /// outcome directly without mounting the view tree. `internal` (not
    /// `private`), `static` (no `self` capture needed).
    enum DailyPrecheckOutcome {
        /// The store's SavedGame record is already `.completed` — carries the
        /// ready-to-render `CompletionViewModel`.
        case completed(CompletionViewModel)
        /// The record exists but is not yet completed (in-progress) — carries
        /// the already-fetched snapshot so the caller can mount it without a
        /// second fetch.
        case notCompleted(GameSessionSnapshot)
        /// Confirmed absent (never played), OR the fetch itself failed
        /// (existence unknown) — the caller falls through to `loadOrCreate`
        /// either way. See `dailyPrecheck`'s doc for why these two cases are
        /// deliberately NOT distinguished here.
        case absent
    }

    /// Adversarial-CR adjudication (#842 round 2): a fetch failure during
    /// THIS precheck must never block daily play — degrades to `.absent`
    /// exactly like confirmed absence, after reporting through
    /// `errorReporter` (source `"BoardLoaderView.dailyPrecheck"`) so the
    /// occurrence stays observable. This mirrors `SavedGameStore.loadOrCreate`'s
    /// own documented local-first contract ("iCloud unavailability must never
    /// prevent puzzle load" — any fetch error there is already treated as
    /// "could not confirm an existing save", never a blocking error) and the
    /// #526 guarantee `DailyHubViewModelOfflineTests` pins for the hub's own
    /// phase-2 fetch. An EARLIER version of this precheck instead THREW on
    /// fetch failure so `load()` would land on `.failed` — that inverted the
    /// #526 contract for every daily open, not just the #842 race window, and
    /// was rejected on review. Contrast with `openCompleted`'s catch (#830):
    /// that path only runs when the CALLER already has strong evidence
    /// (`card.isCompleted == true`) the daily is done, so falling back to
    /// `.board` there is a narrower, already-reviewed exception — not a
    /// precedent for blocking a precheck that runs unconditionally on every
    /// daily open.
    static func dailyPrecheck(
        puzzleId: String,
        identity: PuzzleIdentity,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter
    ) async -> DailyPrecheckOutcome {
        let existing: GameSessionSnapshot?
        do {
            existing = try await persistence.loadIfExists(
                puzzleId: puzzleId,
                mode: identity.kind,
                difficulty: identity.difficulty
            )
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "BoardLoaderView.dailyPrecheck"
            )
            return .absent
        }
        guard let existing else {
            return .absent
        }
        guard existing.status == .completed else {
            return .notCompleted(existing)
        }
        let completionViewModel = CompletionViewModel(
            puzzleId: puzzleId,
            elapsedSeconds: existing.elapsedSeconds,
            mistakeCount: existing.mistakeCount,
            leaderboardId: SudokuLeaderboardRouting.leaderboardId(forPuzzleId: puzzleId)
        )
        return .completed(completionViewModel)
    }
}
