// MinesweeperGameViewModel — @MainActor @Observable bridge between the
// `MinesweeperSession` actor and SwiftUI's `MinesweeperBoardView`.
//
// Pattern mirrors Sudoku's GameViewModel: the actor is the source of truth;
// the ViewModel caches the most recent snapshot and republishes it to the
// view tree after every `await` round-trip.
//
// Scope: no telemetry, no undo. Persistence landed in #455 step 4 — the
// optional `store`/`recordName` seam below; nil keeps the original MVP shape.

import IssueReporting
public import GameAudio
public import GameCenterClient
public import MinesweeperEngine
public import MinesweeperGameState
public import MinesweeperPersistence
public import Observation
public import Telemetry

@MainActor
@Observable
public final class MinesweeperGameViewModel {

    // MARK: - Session

    public let session: MinesweeperSession

    // MARK: - Game Center (#291)

    /// Best-time leaderboard submit seam. `nil` in MVP / preview callsites
    /// (no-op); production wires the shared `LiveGameCenterClient`. Submit is
    /// best-effort and never blocks or crashes gameplay (mirrors Sudoku's
    /// `GameCenterSink` no-retry, swallowed-error policy). Internal (not
    /// private) so the `submitWinIfWon()` extension (separate file,
    /// keeps this file under the 400-line lint ceiling) can read it.
    let gameCenter: (any GameCenterClient)?
    /// Funnel for swallowed submit failures, so a failed leaderboard write is
    /// observable in OSLog instead of silent. `nil` → fully silent.
    /// Internal (not private) so `MinesweeperBoardView.onRetry` can re-thread
    /// it into the rebuilt VM — same treatment as `mode` (#465 CR).
    let errorReporter: (any ErrorReporter)?
    /// #329: gates the GC daily-board submit to daily-mode wins. Mirrors
    /// Sudoku's `GameCenterSink` (`guard mode == .daily`) — a Practice win is a
    /// valid current-cycle board but must NOT inflate the recurring daily
    /// ranking. Defaults to `.practice` so the most cautious behaviour (no
    /// submit) is the default for any callsite that doesn't thread a mode.
    /// Exposed read-only so `MinesweeperBoardView`'s Retry can rebuild the VM
    /// at the same mode (preserving the daily/practice submit gate).
    public let mode: GameMode
    /// Guards against a double-submit if the snapshot re-publishes `.won`.
    /// Internal — see `gameCenter` above for why.
    var didSubmitWin = false
    /// Best-effort one-shot auth so an unauthenticated player's first win
    /// still has a chance to land server-side. Mirrors Sudoku, where the
    /// native dashboard / `RootView.task` performs the handshake.
    var didAttemptAuth = false

    // MARK: - Achievements (#700)

    /// Device-local cumulative win tally backing the "Volume" achievements.
    /// Internal (not private) so `evaluateAchievementsIfWon()` (separate file,
    /// same rationale as `submitWinIfWon`) can read it.
    let winCountStore: MinesweeperWinCountStore
    /// Guards against re-evaluating achievements if the snapshot re-publishes
    /// `.won`. A SEPARATE latch from `didSubmitWin`: achievement evaluation is
    /// gated to the LIVE `reveal()` win transition only (not `refresh()`, see
    /// its comment below), because it increments a non-idempotent cumulative
    /// win tally — `submitWinIfWon()`'s downstream writes are idempotent and
    /// safe to re-run from `refresh()`.
    var didEvaluateAchievements = false

    // MARK: - Audio (#330 P2)

    /// Gameplay-audio seam. Fires an `AudioEvent` (sfx + paired haptic) at each
    /// meaningful moment — reveal, flag, flood-clear, mine-hit, win. Defaults to
    /// `NoopSoundPlaying` so MVP / preview / test callsites that don't thread a
    /// player stay silent. `AVFoundation` never reaches this layer — the VM holds
    /// only the protocol. Production wires `LiveSoundPlayer` via the composition
    /// root.
    private let soundPlayer: any SoundPlaying

    // MARK: - Persistence (#455 step 4)

    /// Saved-game store seam. `nil` (MVP / preview / test callsites) → no
    /// persistence side-effects. Production threads the composition-root
    /// `MinesweeperSavedGameStore`. Internal so `onRetry` re-threads it
    /// (#465 CR — same as `soundPlayer`).
    let store: MinesweeperSavedGameStore?
    /// The save's CloudKit identity, derived ONCE at board construction via
    /// `MinesweeperSavedGameStore.recordName(dailyDay:difficulty:)` /
    /// `.recordName(practice:)` — never re-derived, so a daily board
    /// backgrounded across midnight still upserts its own record. Internal
    /// so `onRetry` re-threads it (same save slot; fresh state overwrites).
    let recordName: String?

    // MARK: - Personal record (#699)

    /// Per-(mode × difficulty) best-time store. `nil` → no-op. Best-effort,
    /// funnels through `errorReporter` — same posture as the GC submit right
    /// beside it. MS-specific (owner decision, #699); not the shared sink.
    let personalRecordStore: MinesweeperPersonalRecordStore?

    // MARK: - Snapshot / preview seam (#297)

    /// When `true`, `refresh()` and the GC submit funnel become no-ops: the
    /// cached `snapshot` is a fixed, externally-seeded value and the actor is
    /// never consulted. Used ONLY by the snapshot-test / preview init below so
    /// deterministic mid-reveal / mineHit / flagged boards survive
    /// `MinesweeperBoardView`'s in-body `.task { refresh() }` (which would
    /// otherwise overwrite the seed with the actor's idle snapshot). Production
    /// callsites never set this — it defaults to `false`, preserving the live
    /// actor-backed refresh path verbatim.
    private let isSeeded: Bool

    // MARK: - Cached snapshot

    public private(set) var snapshot: MinesweeperSessionSnapshot

    // MARK: - Convenience accessors (read-only projections of snapshot)

    public var rows: Int { snapshot.rows }
    public var columns: Int { snapshot.columns }
    public var cells: [Cell] { snapshot.cells }
    public var status: MinesweeperSessionStatus { snapshot.status }
    public var mineCount: Int { snapshot.mineCount }
    public var flagCount: Int { snapshot.flagCount }
    public var elapsedSeconds: Int { snapshot.elapsedSeconds }
    public var remainingMineCount: Int { max(0, mineCount - flagCount) }

    public var isTerminal: Bool { status == .won || status == .lost }

    /// #434: mirrors Sudoku's `GameViewModel.isPaused` (`status == .paused`).
    /// Drives the toolbar Pause/Resume toggle + the board-cover overlay.
    public var isPaused: Bool { status == .paused }

    // MARK: - Init

    /// Construct a fresh session from a difficulty + seed. Use this for
    /// most cases; the underlying actor is created internally.
    public convenience init(
        difficulty: Difficulty = .beginner,
        seed: UInt64 = 0,
        mode: GameMode = .practice,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        store: MinesweeperSavedGameStore? = nil,
        recordName: String? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        winCountStore: MinesweeperWinCountStore = MinesweeperWinCountStore()
    ) {
        self.init(
            session: MinesweeperSession(difficulty: difficulty, seed: seed),
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer,
            store: store,
            recordName: recordName,
            personalRecordStore: personalRecordStore,
            winCountStore: winCountStore
        )
    }

    /// Construct from an existing session. The view model derives its
    /// `difficulty` from `session.difficulty` so the two cannot disagree.
    public init(
        session: MinesweeperSession,
        mode: GameMode = .practice,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        store: MinesweeperSavedGameStore? = nil,
        recordName: String? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        winCountStore: MinesweeperWinCountStore = MinesweeperWinCountStore()
    ) {
        self.session = session
        self.mode = mode
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.store = store
        self.recordName = recordName
        self.personalRecordStore = personalRecordStore
        self.winCountStore = winCountStore
        self.isSeeded = false
        let difficulty = session.difficulty
        // Synchronous bootstrap: snapshot before any action is just the
        // immutable initial state — we mirror it locally so SwiftUI has
        // something to render before the first action.
        self.snapshot = MinesweeperSessionSnapshot(
            difficulty: difficulty,
            cells: Array(repeating: Cell(), count: difficulty.cellCount),
            status: .idle,
            elapsedSeconds: 0,
            mineCount: difficulty.mineCount,
            flagCount: 0
        )
    }

    /// Snapshot / preview seam (#297). Installs a fixed, fully-formed
    /// `MinesweeperSessionSnapshot` and marks the view model as seeded, so
    /// `refresh()` no-ops and the seeded board survives `MinesweeperBoardView`'s
    /// in-body `.task { refresh() }`. The backing `session` is a throwaway
    /// actor at the snapshot's difficulty — it is never consulted (every
    /// mutator path is gated by `isSeeded`). Used only by snapshot tests +
    /// SwiftUI previews to render deterministic revealed / mineHit / flagged
    /// states; production callsites use the actor-backed inits above.
    public init(seeded snapshot: MinesweeperSessionSnapshot) {
        self.session = MinesweeperSession(difficulty: snapshot.difficulty, seed: 0)
        self.mode = .practice
        self.gameCenter = nil
        self.errorReporter = nil
        // Seeded boards never mutate, so no audio ever fires; a Noop keeps the
        // seam non-optional without any preview/snapshot side-effect.
        self.soundPlayer = NoopSoundPlaying()
        self.store = nil
        self.recordName = nil
        self.personalRecordStore = nil
        self.winCountStore = MinesweeperWinCountStore()
        self.snapshot = snapshot
        self.isSeeded = true
    }

    // MARK: - Refresh

    /// Pull the latest snapshot from the actor (e.g. for elapsed-time ticks).
    /// No-op when seeded (#297): the cached snapshot is a fixed fixture and the
    /// actor must never overwrite it.
    public func refresh() async {
        guard !isSeeded else { return }
        snapshot = await session.snapshot()
        await submitWinIfWon()
        // #700: deliberately NOT calling evaluateAchievementsIfWon() here.
        // `submitWinIfWon()` is idempotent downstream (CK dedups by
        // puzzleId, GC keeps the best time), so re-firing on a refresh over an
        // already-won board is harmless. Achievement evaluation is NOT: it
        // increments the cumulative win tally (`MinesweeperWinCountStore`),
        // so it must only run on the live win transition in `reveal()` —
        // re-opening/refreshing a terminal board must not inflate the count.
    }

    // MARK: - Actions

    public func cell(row: Int, col: Int) -> Cell {
        snapshot.cell(row: row, col: col)
    }

    public func reveal(row: Int, col: Int) async {
        // #330 P2: snapshot the prior status + revealed-count so we can classify
        // the outcome of this reveal into the right audio event.
        let previousStatus = snapshot.status
        let revealedBefore = revealedCount(in: snapshot)
        do {
            snapshot = try await session.reveal(row: row, col: col)
        } catch {
            // MVP: out-of-bounds shouldn't happen from a well-formed grid view.
            // Swallow — the ViewModel state stays consistent with the last
            // successful snapshot. #178: surface the invariant violation in
            // test / #Preview (non-fatal in release).
            reportIssue("reveal out-of-bounds from well-formed grid: \(error)")
        }
        fireRevealAudio(previousStatus: previousStatus, revealedBefore: revealedBefore)
        // #291: a reveal is the only action that can transition to `.won`
        // (flagging never wins). Submit the best time once we cross into the
        // won state.
        await submitWinIfWon()
        // #700: achievement evaluation is NOT daily-gated (unlike the Game
        // Center submit above; the personal-record write is no longer
        // daily-gated either, #705). Gated on the LIVE transition (pre-reveal
        // status was not already .won): a
        // no-op reveal on a restored already-won board returns the same .won
        // snapshot, and re-evaluating it would inflate the non-idempotent
        // cumulative win tally (that win was counted when it happened live).
        if previousStatus != .won {
            await evaluateAchievementsIfWon()
        }
        // #455: a terminal board persists immediately — `wireStatus` maps
        // won/lost → "completed", which removes it from the resume-candidate
        // set (the upsert also covers a board that was never saved mid-play).
        if snapshot.status == .won || snapshot.status == .lost {
            await persistCurrentState()
        }
    }

    // MARK: - Persistence (#455 step 4)

    /// Persist the current board through the saved-game store. Trigger points:
    /// pause, terminal reveal (above), and the view-lifecycle hooks
    /// (`scenePhase == .background`, `onDisappear`) in `MinesweeperBoardView`.
    /// No-ops when the persistence seam isn't threaded (MVP/preview/tests),
    /// when seeded (#297 fixtures must stay side-effect-free), or while the
    /// board is still `.idle` (a zero-information pre-first-reveal save would
    /// occupy the resume pill for nothing). Failures funnel — a failed save
    /// never interrupts gameplay (mirrors Sudoku's flush; conflict policy is
    /// the documented MVP bare-throw → funnel, #463 CR).
    public func persistCurrentState() async {
        guard !isSeeded, let store, let recordName else { return }
        guard snapshot.status != .idle else { return }
        do {
            try await store.save(snapshot, modeRaw: mode.rawValue, recordName: recordName)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperGameViewModel.persistCurrentState"
            )
        }
    }

    public func toggleFlag(row: Int, col: Int) async {
        let flagsBefore = snapshot.flagCount
        do {
            snapshot = try await session.toggleFlag(row: row, col: col)
        } catch {
            // See `reveal`. #178: surface the invariant violation.
            reportIssue("toggleFlag out-of-bounds from well-formed grid: \(error)")
        }
        // #330 P2: fire the flag sfx only when the toggle actually changed the
        // flag count (an attempt to flag a revealed cell is a no-op in the engine
        // and shouldn't click). SFX only — no haptic on a routine tap.
        if snapshot.flagCount != flagsBefore {
            soundPlayer.play(.minesweeperFlag)
        }
        // #700: the "a flag was ever placed" fact (backs "No Flags Needed")
        // is tracked by the session and rides `snapshot.everFlagged` — no
        // ViewModel-instance latch, so it survives save/resume.
    }

    // MARK: - Audio classification (#330 P2)

    /// Number of currently-revealed cells in a snapshot — used to tell a single
    /// reveal (delta 1) from a flood-clear (delta > 1).
    private func revealedCount(in snapshot: MinesweeperSessionSnapshot) -> Int {
        var count = 0
        for cell in snapshot.cells where cell.state == .revealed { count += 1 }
        return count
    }

    /// Map the outcome of a `reveal` onto exactly one audio event:
    ///   - crossed into `.lost`  → explosion (mine hit)
    ///   - crossed into `.won`   → win
    ///   - revealed > 1 new cell → floodClear
    ///   - revealed exactly 1    → reveal (SFX only, no haptic)
    ///   - revealed 0            → silent (tap on an already-revealed/flagged cell)
    /// Win/lose take precedence over the cell-delta so a winning flood-clear plays
    /// the win cue, not the flood cue.
    private func fireRevealAudio(previousStatus: MinesweeperSessionStatus, revealedBefore: Int) {
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

    // MARK: - Pause / resume (#434)

    /// Pause the game: freeze the elapsed clock + flip to `.paused`. No-op when
    /// seeded (preview/snapshot) or when the actor isn't `.playing` (the actor
    /// itself guards the transition). Mirrors Sudoku's `GameViewModel.pause()`.
    public func pause() async {
        guard !isSeeded else { return }
        snapshot = await session.pause()
        // #455: a pause is a natural save point (mirrors Sudoku's
        // pause-triggered flush, §How.5.5).
        await persistCurrentState()
    }

    /// Resume the game: restart the clock + flip back to `.playing`. No-op when
    /// seeded or when the actor isn't `.paused`. Mirrors Sudoku's
    /// `GameViewModel.resume()`.
    public func resume() async {
        guard !isSeeded else { return }
        snapshot = await session.resume()
    }

    // Game Center + personal-record submit-on-win (#291, #329, #699, #705):
    // `submitWinIfWon()` lives in MinesweeperGameViewModel+SubmitOnWin.swift
    // — a separate file (not this class body) keeps this file under the
    // 400-line lint ceiling; see that file for the full contract.
    //
    // Achievement evaluation + reporting (#700): `evaluateAchievementsIfWon()`
    // lives in MinesweeperGameViewModel+EvaluateAchievements.swift — same
    // file-split rationale, own latch (most achievements are NOT daily-gated).
}
