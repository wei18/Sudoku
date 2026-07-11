// GameViewModel — owns one in-flight game session for BoardView.
//
// Per docs/v1/design.md §How.5.3 (state machine) + §How.5.4 (VM ownership) +
// §How.5.5 (debounce flush).
//
// Implementation choice: the VM mirrors `GameSession` state into observable
// properties (`board`, `notes`, `elapsedSeconds`, etc.) so SwiftUI can read
// them synchronously. Every user mutation (place / pencil / undo / redo)
// dispatches to the `GameSession` actor, then re-syncs the cached state.
// Snapshot tests bypass the live session via `setStateForTesting(...)` so
// they can render deterministic boards without spinning up generators.

// swiftlint:disable file_length
// 648 lines vs 400 limit. The class is cohesive (one in-flight game session,
// all mutation handlers + state-machine + debounced save + #330 P2 audio cues
// live together by design). Splitting would push private state across files and
// hurt readability. Tracked for proper refactor in a follow-up backlog issue.

public import Foundation
import IssueReporting
public import GameAudio
public import SudokuGameState
public import Persistence
public import SudokuPersistence
public import SudokuEngine
public import Telemetry

@MainActor
@Observable
public final class GameViewModel {

    // MARK: - Identity

    public let identity: PuzzleIdentity

    // MARK: - Observable view state (kept in sync with GameSession)

    public private(set) var board: Board
    public private(set) var notes: NotesGrid
    public private(set) var status: GameSessionStatus
    public private(set) var elapsedSeconds: Int
    /// Cumulative count of conflicting digit placements (AC-3.4 / SDD-003
    /// Epic 3). Restored from the saved game snapshot so Resume shows the
    /// same value the player had when they left.
    public private(set) var mistakeCount: Int
    public private(set) var canUndo: Bool = false
    public private(set) var canRedo: Bool = false

    /// Currently-focused cell. UI selection drives both tap and keyboard
    /// arrows; `nil` means no cell focused (legal initial state).
    public var selection: GridCoordinate?

    /// Digit armed for digit-first placement (#722): tapping a keypad digit
    /// with no cell selected arms it here instead of placing; a subsequent
    /// empty-cell tap places it (see `tapCell(row:column:)`) and the digit
    /// stays armed for consecutive placements. `nil` = today's cell-first
    /// flow. Invariant: `armedDigit != nil ⟺ selection == nil` — `select()`
    /// is the one place that disarms, `armDigit(_:)` the one place that arms
    /// (and clears `selection`).
    public private(set) var armedDigit: Int?

    /// Whether digit input writes pencil notes (`true`) or values (`false`).
    public var pencilMode: Bool = false

    /// Set of board indices currently flagged as conflicting. Computed by
    /// `recomputeErrors()` after each placement.
    public private(set) var errorIndices: Set<Int> = []

    /// `true` while the session is paused; UI overlays a "Tap to resume" pane.
    public var isPaused: Bool { status == .paused }

    // MARK: - Collaborators

    private let session: GameSession?
    private let persistence: (any PersistenceProtocol)?
    /// M10 (issue #67): unified error funnel. Routes session / persistence
    /// failures into Telemetry + recent-errors buffer instead of silent
    /// `try?` swallowing. Default `NoopErrorReporter` keeps the snapshot /
    /// preview init paths zero-IO.
    private let errorReporter: any ErrorReporter

    /// #330 P2: audio/haptic seam. Plays the Sudoku gameplay cues (place /
    /// section-cleared / mistake / win) + the looping BGM. Defaults to
    /// `NoopSoundPlaying` so snapshot tests + Previews stay silent and the
    /// live `LiveSoundPlayer` is injected only by the composition root. The VM
    /// holds the protocol ONLY — AVFoundation never leaks in here.
    private let soundPlayer: any SoundPlaying

    /// Debounce interval for the save task; injectable so tests can shrink it.
    private let saveDebounceNanos: UInt64
    private var pendingSaveTask: Task<Void, Never>?

    /// Injectable "now" — used by `isLateCompletion` to detect daily puzzles
    /// from a past UTC day. Defaults to `Date()`; tests fast-forward.
    private let clock: @Sendable () -> Date

    // MARK: - Init

    /// Live init — bind to a real `GameSession` + `Persistence`.
    public init(
        identity: PuzzleIdentity,
        session: GameSession,
        initialBoard: Board,
        initialNotes: NotesGrid = NotesGrid(),
        initialStatus: GameSessionStatus = .idle,
        initialElapsedSeconds: Int = 0,
        initialMistakeCount: Int = 0,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        saveDebounceNanos: UInt64 = 500_000_000,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identity = identity
        self.session = session
        self.board = initialBoard
        self.notes = initialNotes
        self.status = initialStatus
        self.elapsedSeconds = initialElapsedSeconds
        self.mistakeCount = initialMistakeCount
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.saveDebounceNanos = saveDebounceNanos
        self.clock = clock
    }

    /// Snapshot / preview init — no live `GameSession`, no persistence.
    /// All mutators that would hit the actor become no-ops. Used by snapshot
    /// tests + SwiftUI previews to render deterministic board states.
    public init(
        identity: PuzzleIdentity,
        board: Board,
        notes: NotesGrid = NotesGrid(),
        status: GameSessionStatus = .playing,
        elapsedSeconds: Int = 0,
        mistakeCount: Int = 0,
        errorIndices: Set<Int> = [],
        selection: GridCoordinate? = nil,
        armedDigit: Int? = nil,
        pencilMode: Bool = false,
        canUndo: Bool = false,
        canRedo: Bool = false,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.identity = identity
        self.session = nil
        self.persistence = nil
        self.errorReporter = NoopErrorReporter()
        self.soundPlayer = NoopSoundPlaying()
        self.saveDebounceNanos = 0
        self.board = board
        self.notes = notes
        self.status = status
        self.elapsedSeconds = elapsedSeconds
        self.mistakeCount = mistakeCount
        self.errorIndices = errorIndices
        // #722 invariant, asserted at construction so test/preview fixtures
        // can't drift into a state the two runtime mutators (select() /
        // armDigit()) make unreachable.
        assert(selection == nil || armedDigit == nil,
               "armedDigit != nil requires selection == nil (#722 invariant)")
        self.selection = selection
        self.armedDigit = armedDigit
        self.pencilMode = pencilMode
        self.canUndo = canUndo
        self.canRedo = canRedo
        self.clock = clock
    }

    // MARK: - Late-completion marker (issue #228 option B)

    /// `true` iff this is a daily puzzle whose embedded UTC day is strictly
    /// before today — i.e. completing it will NOT submit to the Game Center
    /// leaderboard (per `SubmitGuards`). The board header surfaces this so
    /// the user knows mid-game that the run won't score.
    public var isLateCompletion: Bool {
        guard identity.kind == .daily else { return false }
        guard let day = Self.extractDailyDay(from: identity.puzzleId) else { return false }
        return day < UTCDay.string(from: clock())
    }

    /// Pull the `YYYY-MM-DD` prefix from a daily puzzleId. Mirrors the
    /// helper in `SavedGameStore` (issue #228 option E) and `SubmitGuards`.
    private static func extractDailyDay(from puzzleId: String) -> String? {
        let prefix = puzzleId.prefix(10)
        guard prefix.count == 10,
              prefix[prefix.index(prefix.startIndex, offsetBy: 4)] == "-",
              prefix[prefix.index(prefix.startIndex, offsetBy: 7)] == "-"
        else { return nil }
        return String(prefix)
    }

    // MARK: - Test seam

    /// Test seam: install a fully-formed view state without going through
    /// the GameSession actor. Used by snapshot tests + behavior tests for
    /// keyboard input.
    public func setStateForTesting(
        board: Board? = nil,
        notes: NotesGrid? = nil,
        status: GameSessionStatus? = nil,
        elapsedSeconds: Int? = nil,
        mistakeCount: Int? = nil,
        errorIndices: Set<Int>? = nil,
        selection: GridCoordinate? = nil,
        armedDigit: Int? = nil,
        pencilMode: Bool? = nil,
        canUndo: Bool? = nil,
        canRedo: Bool? = nil
    ) {
        if let board { self.board = board }
        if let notes { self.notes = notes }
        if let status { self.status = status }
        if let elapsedSeconds { self.elapsedSeconds = elapsedSeconds }
        if let mistakeCount { self.mistakeCount = mistakeCount }
        if let errorIndices { self.errorIndices = errorIndices }
        assert((selection ?? self.selection) == nil || (armedDigit ?? self.armedDigit) == nil,
               "armedDigit != nil requires selection == nil (#722 invariant)")
        if let selection { self.selection = selection }
        applyTestArmedDigit(armedDigit)
        if let pencilMode { self.pencilMode = pencilMode }
        if let canUndo { self.canUndo = canUndo }
        if let canRedo { self.canRedo = canRedo }
    }

    /// #722: split out of `setStateForTesting` to keep that function's
    /// cyclomatic complexity under the lint ceiling — one more `if let`
    /// there tipped it from 10 to 11.
    private func applyTestArmedDigit(_ armedDigit: Int?) {
        if let armedDigit { self.armedDigit = armedDigit }
    }

    // MARK: - Mutations (UI-facing)

    /// Place a digit (1...9) or clear (`nil`) into the currently-selected
    /// cell. No-op if no cell is selected or the cell is a given. Routes
    /// through `GameSession` when one is bound, then re-syncs view state.
    public func placeDigit(_ digit: Int?) async {
        guard let selection else { return }
        await placeDigit(digit, at: selection)
    }

    public func placeDigit(_ digit: Int?, at coord: GridCoordinate) async {
        let index = Board.index(row: coord.row, column: coord.column)
        if board.givenMask[index] { return }

        if let session {
            // #330 P2: capture pre-mutation state so we can fire the right audio
            // cue after the re-sync (which is the authoritative post-state).
            let wasCompleted = status == .completed
            let unitsCompleteBefore = digit == nil ? 0 : completedUnitCount(touching: coord)

            if let digit {
                await runSession("placeDigit") {
                    try await session.placeDigit(row: coord.row, col: coord.column, digit: digit)
                }
            } else {
                // Per impl-notes 2026-05-20_wave-2-blocker-fixes §B1: clear
                // routes through the actor like place. The actor records a
                // `.clearDigit` undo move and updates `currentBoard`, so the
                // subsequent `resyncFromSession()` keeps the cell cleared.
                await runSession("clearDigit") {
                    try await session.clearDigit(row: coord.row, col: coord.column)
                }
            }
            await resyncFromSession()

            if let digit {
                fireAudio(forDigit: digit, at: coord, wasCompleted: wasCompleted, unitsCompleteBefore: unitsCompleteBefore)
                // #610 fix *3: clear the save's inProgress status so the hub stops
                // offering a resume for a completed game.
                await markCompletedIfNeeded(wasCompleted: wasCompleted)
            }
        } else {
            // Preview / test path: poke the mirror without crossing actor.
            // An invalid coord here is a programmer error in fixture wiring,
            // never a runtime user path — make it loud in DEBUG.
            do {
                try board.setDigit(digit, atRow: coord.row, column: coord.column)
            } catch {
                reportIssue("preview fixture wiring bug: \(error)")
            }
            recomputeErrors()
        }
        scheduleSave()
    }

    /// Erase the currently-selected cell — clears digit AND notes in one
    /// gesture. The digit clear participates in undo; the notes clear does
    /// not (see meetings/2026-05-30_board-mac-redesign.impl-notes.md §偏離).
    /// No-op if no cell is selected or the cell is a given.
    public func eraseCell() async {
        guard let selection else { return }
        let index = Board.index(row: selection.row, column: selection.column)
        if board.givenMask[index] { return }

        if let session {
            await runSession("eraseCell") {
                try await session.clearDigit(row: selection.row, col: selection.column)
                try await session.clearNotes(row: selection.row, col: selection.column)
            }
            await resyncFromSession()
        } else {
            // Preview / test path.
            do {
                try board.setDigit(nil, atRow: selection.row, column: selection.column)
            } catch {
                reportIssue("preview fixture wiring bug: \(error)")
            }
            notes.clear(row: selection.row, col: selection.column)
            recomputeErrors()
        }
        scheduleSave()
    }

    public func toggleNote(_ digit: Int) async {
        guard let selection else { return }
        await toggleNote(digit, at: selection)
    }

    /// #722: coord-taking overload so digit-first placement (`tapCell`) can
    /// toggle a note on an arbitrary cell without going through `selection`.
    public func toggleNote(_ digit: Int, at coord: GridCoordinate) async {
        let index = Board.index(row: coord.row, column: coord.column)
        if board.givenMask[index] { return }

        if let session {
            await runSession("toggleNote") {
                try await session.toggleNote(row: coord.row, col: coord.column, digit: digit)
            }
            await resyncFromSession()
        } else {
            _ = notes.toggle(digit: digit, row: coord.row, col: coord.column)
        }
        scheduleSave()
    }

    public func undo() async {
        guard let session else { return }
        await runSession("undo") { try await session.undo() }
        await resyncFromSession()
        scheduleSave()
    }

    public func redo() async {
        guard let session else { return }
        await runSession("redo") { try await session.redo() }
        await resyncFromSession()
        scheduleSave()
    }

    public func pause() async {
        guard let session else {
            status = .paused
            return
        }
        await runSession("pause") { try await session.pause() }
        await resyncFromSession()
        // #330 P2: silence BGM while paused.
        stopMusic()
        await flush()
    }

    public func resume() async {
        guard let session else {
            status = .playing
            return
        }
        await runSession("resume") { try await session.resume() }
        await resyncFromSession()
        // #330 P2: resume BGM (player auto-yields if other audio is playing).
        startMusic()
    }

    /// Idempotent "boot the session into a state where mutations land".
    /// Fixes #227: `BoardLoaderView` constructed a `GameSession` and left it
    /// in `.idle`; every digit-pad tap then failed the `.playing` gate inside
    /// the actor and was silently absorbed by `runSession`, so the user saw
    /// a dead board + a frozen 0:00 timer.
    ///
    /// - `.idle`     → `session.start()`
    /// - `.paused`   → `session.resume()`
    /// - else        → no-op (already playing / finished)
    public func startOrResume() async {
        guard let session else { return }
        let current = await session.status
        switch current {
        case .idle:
            await runSession("startOrResume.start") { try await session.start() }
        case .paused:
            await runSession("startOrResume.resume") { try await session.resume() }
        case .playing, .completed, .abandoned:
            return
        }
        await resyncFromSession()
    }

    /// Refresh the observable `elapsedSeconds` mirror from the actor without
    /// triggering a mutation. Driven by `BoardView`'s 1-Hz `.task` ticker so
    /// the timer label advances between user inputs (without this, only
    /// `resyncFromSession()` after a mutation would update it).
    public func refreshElapsed() async {
        guard let session else { return }
        let next = await session.elapsedSeconds
        if next != elapsedSeconds {
            elapsedSeconds = next
        }
    }

    /// M10 (issue #67): unified session-call helper. Catches the throw,
    /// routes it through the error funnel, and absorbs locally so the
    /// VM can re-sync state instead of propagating up to SwiftUI (which
    /// has no recovery surface for these failures — see design.md §How.5.4
    /// + §How.6.1 principle 1: in-flight game must never crash on save
    /// failures). Source string identifies the specific actor method.
    private func runSession(
        _ method: String,
        _ body: () async throws -> Void
    ) async {
        do {
            try await body()
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameViewModel.\(method)"
            )
        }
    }

    public func togglePencil() {
        pencilMode.toggle()
    }

    public func select(row: Int, column: Int) {
        // #722: any cell-first selection disarms digit-first mode. This is
        // the single enforcement point for the invariant `armedDigit != nil
        // ⟺ selection == nil` on the "selecting" side — unconditional (even
        // when the guards below no-op the actual selection change) so a tap
        // on a given/out-of-bounds cell while armed still exits armed mode.
        armedDigit = nil
        guard (0..<Board.dimension).contains(row),
              (0..<Board.dimension).contains(column) else { return }
        // Epic 9 (SDD-003): given (prefilled) cells are not selectable —
        // tapping them does nothing, produces no highlight.
        let index = Board.index(row: row, column: column)
        guard !board.givenMask[index] else { return }
        selection = GridCoordinate(row: row, column: column)
    }

    /// Move focus by a delta (used by Mac arrow keys). Clamps to board bounds.
    /// Given cells are intentionally reachable here (no `givenMask` guard):
    /// SDD-003 Epic 9 targets tap interaction only, and skipping givens would
    /// make arrow navigation jump non-linearly. The guard lives in `select()`.
    public func moveSelection(rowDelta: Int, columnDelta: Int) {
        armedDigit = nil  // #722: keyboard navigation also disarms.
        let current = selection ?? GridCoordinate(row: 0, column: 0)
        let nextRow = max(0, min(Board.dimension - 1, current.row + rowDelta))
        let nextCol = max(0, min(Board.dimension - 1, current.column + columnDelta))
        selection = GridCoordinate(row: nextRow, column: nextCol)
    }

    /// Arm/disarm a digit for digit-first placement (#722). Tapping the
    /// keypad with no cell selected calls this; tapping the SAME armed digit
    /// again disarms. Arming clears `selection` — the invariant's other
    /// enforcement point (paired with `select()`, which clears `armedDigit`).
    public func armDigit(_ digit: Int) {
        guard (1...9).contains(digit) else { return }
        armedDigit = (armedDigit == digit) ? nil : digit
        if armedDigit != nil { selection = nil }
    }

    // MARK: - Audio (#330 P2)

    /// Start the looping gameplay BGM. The live player auto-yields when another
    /// app is already playing audio, so this is safe to call unconditionally.
    /// No-op on the snapshot / preview path (`NoopSoundPlaying`).
    public func startMusic() {
        soundPlayer.playMusic(key: SudokuAudioMusic.gameplay)
    }

    /// Stop the looping gameplay BGM (board dismissed). No-op under Noop.
    public func stopMusic() {
        soundPlayer.stopMusic()
    }

    /// Decide which gameplay cue to fire after a digit placement, in priority
    /// order: a solve (win) trumps everything; otherwise a mistake (the placed
    /// cell now conflicts); otherwise a plain placement, optionally followed by
    /// a section-cleared cue when this move newly completed a row / column / box.
    private func fireAudio(forDigit digit: Int, at coord: GridCoordinate, wasCompleted: Bool, unitsCompleteBefore: Int) {
        // Win: the live `.playing → .completed` transition. Fires exactly once
        // (a re-placed digit on an already-completed board won't re-transition).
        if status == .completed, !wasCompleted {
            soundPlayer.play(.sudokuWin)
            return
        }

        // Mistake: the placed cell is now flagged as conflicting.
        let index = Board.index(row: coord.row, column: coord.column)
        if errorIndices.contains(index) {
            soundPlayer.play(.sudokuMistake)
            return
        }

        // Plain placement (sound only, no haptic).
        soundPlayer.play(.sudokuPlace)

        // Section cleared: this move newly completed at least one of the three
        // units (row / column / box) that contain the cell.
        if completedUnitCount(touching: coord) > unitsCompleteBefore {
            soundPlayer.play(.sudokuSectionCleared)
        }
    }

    /// Count how many of the three units (row, column, box) containing `coord`
    /// are fully filled with NO conflict — i.e. correctly completed. Compared
    /// before vs after a placement to detect a NEWLY completed section.
    private func completedUnitCount(touching coord: GridCoordinate) -> Int {
        var count = 0
        if isUnitComplete(rowIndices(coord.row)) { count += 1 }
        if isUnitComplete(columnIndices(coord.column)) { count += 1 }
        if isUnitComplete(boxIndices(row: coord.row, column: coord.column)) { count += 1 }
        return count
    }

    /// A unit is "complete" when every cell holds a digit and none is flagged as
    /// an error (a fully-filled-but-conflicting unit is not a real completion).
    private func isUnitComplete(_ indices: [Int]) -> Bool {
        for index in indices {
            guard board.digit(atIndex: index) != nil else { return false }
            if errorIndices.contains(index) { return false }
        }
        return true
    }

    private func rowIndices(_ row: Int) -> [Int] {
        (0..<Board.dimension).map { Board.index(row: row, column: $0) }
    }

    private func columnIndices(_ column: Int) -> [Int] {
        (0..<Board.dimension).map { Board.index(row: $0, column: column) }
    }

    private func boxIndices(row: Int, column: Int) -> [Int] {
        let boxRow = (row / 3) * 3
        let boxCol = (column / 3) * 3
        var indices: [Int] = []
        for boxR in boxRow..<boxRow + 3 {
            for boxC in boxCol..<boxCol + 3 {
                indices.append(Board.index(row: boxR, column: boxC))
            }
        }
        return indices
    }

    // MARK: - Completion side-effect

    /// Call `persistence.markCompleted` exactly once on the `.playing → .completed`
    /// edge (#610 fix *3). Gated on `wasCompleted` captured before `resyncFromSession`.
    ///
    /// `SavedGameStore.recordName(for:mode:)` is internal; we mirror the same
    /// `"\(mode.rawValue)-\(puzzleId)"` formula here since `GameViewModel` owns both
    /// halves via `identity`. Only the `recordName` field is read by the store's
    /// `markCompleted` implementation (it fetches by name, then flips `status`).
    private func markCompletedIfNeeded(wasCompleted: Bool) async {
        guard status == .completed, !wasCompleted, let persistence else { return }
        // `SavedGameStore.markCompleted` reads ONLY `summary.recordName` (it fetches
        // the live CloudKit record by name and flips its `status` field). The other
        // fields below are inert for this call — they satisfy the struct's memberwise
        // init without requiring a separate query for the stored summary.
        let summary = SavedGameSummary(
            recordName: "\(identity.kind.rawValue)-\(identity.puzzleId)",
            puzzleId: identity.puzzleId,
            mode: identity.kind,
            difficulty: identity.difficulty,
            lastModifiedAt: clock(),
            elapsedSeconds: elapsedSeconds,
            status: "completed",
            generatorVersion: 1
        )
        do {
            try await persistence.markCompleted(summary)
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameViewModel.markCompletedIfNeeded"
            )
        }
    }

    // MARK: - Persistence

    /// Debounced save — cancels prior pending task, then queues a fresh one.
    /// Per §How.5.5; debounce window is `saveDebounceNanos` (default 500 ms).
    private func scheduleSave() {
        guard let persistence, let session else { return }
        pendingSaveTask?.cancel()
        let delay = saveDebounceNanos
        // Capture identity primitives at scheduling time — they cannot
        // change for a given VM instance, and capturing them here keeps the
        // Task body off `self`'s isolation domain. Per impl-notes
        // 2026-05-20_wave-2-blocker-fixes §B2.
        let puzzleId = identity.puzzleId
        let mode = identity.kind
        let difficulty = identity.difficulty
        let reporter = errorReporter
        pendingSaveTask = Task { [weak self] in
            // try?: Task.sleep cancellation is normal control flow (debounce
            // window was re-armed by the next user input).
            try? await Task.sleep(nanoseconds: delay)
            if Task.isCancelled { return }
            guard let snapshot = await self?.captureSnapshot() else { return }
            do {
                try await persistence.save(
                    snapshot,
                    puzzleId: puzzleId,
                    mode: mode,
                    difficulty: difficulty
                )
            } catch {
                await reporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "GameViewModel.debouncedSave"
                )
            }
        }
        _ = session  // silence unused-capture warning
    }

    private func captureSnapshot() async -> GameSessionSnapshot? {
        guard let session else { return nil }
        return await session.snapshot()
    }

    /// Force-flush any pending debounced save. Awaits the actual write.
    /// Per §How.5.5 — called on pause / scenePhase background / view dismiss.
    public func flush() async {
        pendingSaveTask?.cancel()
        guard let snapshot = await captureSnapshot(),
              let persistence else { return }
        do {
            try await persistence.save(
                snapshot,
                puzzleId: identity.puzzleId,
                mode: identity.kind,
                difficulty: identity.difficulty
            )
        } catch {
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "GameViewModel.flush"
            )
        }
    }

    // MARK: - Internal helpers

    private func resyncFromSession() async {
        guard let session else { return }
        let snap = await session.snapshot()
        self.board = snap.currentBoard
        self.notes = snap.notes
        self.status = snap.status
        self.elapsedSeconds = snap.elapsedSeconds
        self.mistakeCount = snap.mistakeCount
        self.canUndo = !snap.undoMoves.isEmpty
        self.canRedo = !snap.redoMoves.isEmpty
        recomputeErrors()
    }

    /// Mark every user-filled cell whose digit conflicts (row/col/box) with
    /// another cell as an error. Givens are excluded since they're trusted.
    private func recomputeErrors() {
        var errors: Set<Int> = []
        for row in 0..<Board.dimension {
            for col in 0..<Board.dimension {
                let index = Board.index(row: row, column: col)
                guard !board.givenMask[index],
                      let digit = board.digit(atIndex: index) else { continue }
                if hasConflict(digit: digit, row: row, col: col) {
                    errors.insert(index)
                }
            }
        }
        self.errorIndices = errors
    }

    private func hasConflict(digit: Int, row: Int, col: Int) -> Bool {
        for col2 in 0..<Board.dimension where col2 != col {
            if board.digit(atRow: row, column: col2) == digit { return true }
        }
        for row2 in 0..<Board.dimension where row2 != row {
            if board.digit(atRow: row2, column: col) == digit { return true }
        }
        let boxRowOrigin = (row / 3) * 3
        let boxColOrigin = (col / 3) * 3
        for row2 in boxRowOrigin..<boxRowOrigin + 3 {
            for col2 in boxColOrigin..<boxColOrigin + 3 where !(row2 == row && col2 == col) {
                if board.digit(atRow: row2, column: col2) == digit { return true }
            }
        }
        return false
    }
}

// MARK: - Value types

public struct GridCoordinate: Sendable, Equatable, Hashable {
    public let row: Int
    public let column: Int
    public init(row: Int, column: Int) {
        self.row = row
        self.column = column
    }
}
// swiftlint:enable file_length
