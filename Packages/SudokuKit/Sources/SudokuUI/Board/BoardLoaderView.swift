// BoardLoaderView — async wrapper that resolves a puzzleId into a live
// `BoardView(viewModel:)` mount (issue #45, PROPOSAL shape iii).
//
// `RootView.destination` is `@ViewBuilder`-synchronous, so it cannot `await`
// the puzzle fetch + `GameSession` restore that the live `GameViewModel`
// init demands. This wrapper owns that async bootstrap: it renders a
// `ProgressView` placeholder on first mount, kicks off the fetch in
// `.task`, then swaps to the real `BoardView` once `.loaded`. Errors land
// in `.failed` with a Retry button.
//
// API surface intentionally small (one State enum, no public deps beyond
// what `RootView.destination` already has) so `GameViewModel.swift` and
// `BoardView.swift` stay untouched.
//
// #719: the `.failed` screen used to be a dead end on iOS (fullScreenCover
// has no interactive dismiss) — Retry was the ONLY affordance. `failedBlock`
// now also offers Close, wired to the same `@Environment(\.dismiss)` the
// board's own Leave button uses (BoardView.swift), and a DEBUG-only launch
// hook (`UITestLaunchArg.loaderFail`) lets sim E2E drive straight into
// `.failed(.unknown)` without a real persistence failure.
//
// #842: this is the ONE seam every `.board` mount funnels through regardless
// of caller (a hub card tap, a deep link, a future resume path) — including
// `DailyHubViewModel.cardTapped`'s NOT-completed branch, which never checked
// anything before pushing `.board(puzzleId:)` (the VM's `card.isCompleted` is
// phase-1-stale until the hub's phase-2 overlay fetch lands, #530/#774). A
// fast tap on a card whose REAL daily status was already `.completed`
// therefore used to mount a fully playable board (timer restarts, replayable)
// instead of the Completion re-view. Fix: for a DAILY puzzleId, `load()` now
// re-verifies against the store's truth (`persistence.loadIfExists`, the same
// #830 seam `openCompleted` already uses) BEFORE ever building a `GameViewModel`
// — race-proof by construction, since this loader is unconditionally on the
// path to every daily board mount. A confirmed-`.completed` record renders the
// SAME Completion surface `openCompleted`'s `.completion` route would, just
// inline — the `.completion` AppRoute can't push here: boards mount with
// `path == nil` in the real (modal) presentation context (see `boardDestination`
// below), which is exactly why `BoardView+Completion` (#667) also renders its
// post-solve overlay inline rather than routing. A fetch FAILURE is honest —
// `.failed`, never a silently-minted fresh board — mirroring the #830/#841
// tri-state (existence unknown must not be treated as "confirmed absent").
// Practice puzzles are untouched (`identity.kind != .daily` skips the precheck
// entirely) — Practice never re-opens a previously-completed puzzleId (the
// hub always draws a fresh one), so there is nothing to race here.

public import MonetizationCore
public import SwiftUI
public import Persistence
public import SudokuPersistence
public import Telemetry
// #330 P2: the `SoundPlaying` seam forwarded into the live `GameViewModel`.
public import GameAudio
// #610: GameCenterClient + ReminderPrimerCoordinator forwarded into BoardView
// so the Completion overlay can build its VM and daily reminder primer.
public import GameCenterClient
public import SettingsUI
import SudokuGameState
public import SudokuEngine
// #719: `UITestLaunchArg.loaderFail` DEBUG hook.
import GameAppKit
// #842: `CompletionOverlayScaffold` for the inline completed-daily redirect.
import GameShellUI

@MainActor
public struct BoardLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(GameViewModel)
        /// #842: the daily open-time precheck (`load()`) found the store's
        /// SavedGame record already `.completed` — render the Completion
        /// surface inline instead of ever building a playable `GameViewModel`.
        /// Carries the reminder-primer coordinator built once alongside the VM
        /// (mirrors `BoardView`'s `completionReminderPrimer`, built once on the
        /// terminal transition) so recomputes don't rebuild it.
        case completedRedirect(CompletionViewModel, ReminderPrimerCoordinator?)
        /// M10 (issue #67): carries a `UserFacingError` (typed bucket) instead
        /// of a raw `String(describing: error)`. UI renders localized copy via
        /// the enum's `messageKey`; engineering still sees the underlying
        /// error in OSLog via the error funnel.
        case failed(UserFacingError)
    }

    private let puzzleId: String
    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    private let errorReporter: any ErrorReporter
    // v2.3.5: forwarded to `BoardView` so the banner slot can render
    // between the grid and the digit pad once the puzzle has loaded.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    // #330 P2: gameplay audio seam, forwarded into the live `GameViewModel`.
    // Defaults to `NoopSoundPlaying` so previews / tests stay silent.
    private let soundPlayer: any SoundPlaying
    // Host navigation path, forwarded to `BoardView` so the completion
    // overlay's Close can pop the board's own stack entry in the push context
    // (#667 — the solve no longer pushes a `.completion` route). Optional →
    // previews / tests mount without a stack.
    private let path: Binding<[AppRoute]>?
    // #579 phase 1: Telemetry fan-out for per-session adapter. `nil` (default)
    // → `NoOpGameStateTelemetry` so previews / tests are unaffected.
    private let telemetry: Telemetry?
    // #610: Game Center client + Daily reminder primer builder forwarded into
    // `BoardView` so the Completion overlay can build its VM + primer.
    // Both default to nil so existing callsites (tests, previews) compile unchanged.
    private let gameCenter: (any GameCenterClient)?
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    // #652: Play Again CTA. Forwarded into `BoardView` → `BoardView+Completion`.
    // `nil` (default) → Close-only completion (existing callsites unchanged).
    private let onPlayAgain: ((Difficulty) -> Void)?
    // #719: snapshot/test-only seam — when non-nil, `state` is pre-seeded to
    // `.failed(_)` and the `.task`-driven `load()` is skipped, so a
    // deterministic test can render `failedBlock` without a live (or fake)
    // persistence fetch racing to overwrite it. `nil` in every production
    // callsite — mirrors `MinesweeperBoardView`'s `completionViewModelForSnapshot` seam.
    private let failedForSnapshot: UserFacingError?

    @State private var state: LoadState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(
        puzzleId: String,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        path: Binding<[AppRoute]>? = nil,
        telemetry: Telemetry? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        failedForSnapshot: UserFacingError? = nil
    ) {
        self.puzzleId = puzzleId
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.adProvider = adProvider
        self.adGate = adGate
        self.soundPlayer = soundPlayer
        self.path = path
        self.telemetry = telemetry
        self.gameCenter = gameCenter
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.onPlayAgain = onPlayAgain
        self.failedForSnapshot = failedForSnapshot
        self._state = State(initialValue: failedForSnapshot.map { .failed($0) } ?? .loading)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: puzzleId) {
                guard failedForSnapshot == nil else { return }
                await load()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .loaded(let viewModel):
            BoardView(
                viewModel: viewModel,
                adProvider: adProvider,
                adGate: adGate,
                gameCenter: gameCenter,
                makeDailyReminderPrimer: makeDailyReminderPrimer,
                onPlayAgain: onPlayAgain,
                path: path
            )
        case .completedRedirect(let completionViewModel, let reminderPrimer):
            // #842: same scaffold + card `LiveRouteFactory`'s `.completion`
            // route builds for `openCompleted`'s redirect — byte-identical
            // rendering, just reached from a different (pre-mount) seam, so
            // this introduces no new visual state to snapshot.
            CompletionOverlayScaffold(
                onClose: { exitToHub() },
                card: {
                    CompletionView(
                        viewModel: completionViewModel,
                        reminderPrimer: reminderPrimer,
                        onClose: nil
                    )
                }
            )
        case .failed(let userFacing):
            failedBlock(userFacing: userFacing)
        }
    }

    /// #842: mirrors `BoardView+Completion.exitToHub` exactly — Close on the
    /// redirect surface must land the player back on the hub on every
    /// platform, same as the real post-solve overlay's Close.
    private func exitToHub() {
        guard let path else {
            dismiss()
            return
        }
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    private func failedBlock(userFacing: UserFacingError) -> some View {
        // spacing-exempt: 12pt predates the 5-tier `SpacingTokens` scale —
        // no matching tier without snapping and changing this block's
        // existing layout/snapshot (#762 PR2).
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load puzzle.")
                .foregroundStyle(theme.text.primary.resolved)
            // M10 (issue #67): render localized body for the typed
            // UserFacingError bucket instead of `String(describing: error)`.
            Text(LocalizedStringResource(stringLiteral: userFacing.messageKey))
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
                .multilineTextAlignment(.center)
            // #719: on iOS the board's fullScreenCover has no interactive
            // dismiss (see GameRoot.swift), so Retry used to be the ONLY
            // affordance here — a dead end for a player whose fetch keeps
            // failing (e.g. offline). Close mirrors the same
            // `@Environment(\.dismiss)` the board's own Leave button uses
            // (BoardView.swift) and closes the modal back to the caller.
            // Harmless-but-present on macOS too (push nav already has a
            // system back chevron) — consistency over platform-splitting.
            // spacing-exempt: 12pt predates the 5-tier `SpacingTokens`
            // scale — same rationale as above (#762 PR2).
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                Button {
                    Task { await load() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
        }
        // spacing-exempt: 20pt (card padding) predates the 5-tier
        // `SpacingTokens` scale — no matching tier to route through without
        // snapping to a neighbor and changing this card's existing
        // layout/snapshot. Tracked as a follow-up once the token-scale gap
        // gets an owner decision (#762 PR2).
        .padding(20)
    }

    private func load() async {
        state = .loading
        // #719: DEBUG-only sim E2E hook — forces `.failed` immediately,
        // skipping the real persistence fetch, so the Close exit affordance
        // can be verified without a real CloudKit failure repro (offline
        // Sudoku daily/practice reads are near-unreachable in practice —
        // `SavedGameStore.loadOrCreate` deliberately swallows CK errors).
        #if DEBUG
        if Self.isLoaderFailLaunch() {
            state = .failed(.unknown)
            return
        }
        #endif
        let identity = Self.identity(from: puzzleId)
        do {
            // #842: daily-only open-time precheck. Never throws — a fetch
            // failure degrades to `.absent` internally (see `dailyPrecheck`'s
            // doc: local-first, must never block play, #526).
            if identity.kind == .daily {
                switch await Self.dailyPrecheck(
                    puzzleId: puzzleId,
                    identity: identity,
                    persistence: persistence,
                    errorReporter: errorReporter
                ) {
                case .completed(let completionViewModel):
                    state = .completedRedirect(completionViewModel, makeDailyReminderPrimer?())
                    return
                case .notCompleted(let existing):
                    // Build directly from THIS already-fetched snapshot instead
                    // of re-fetching the same record via `loadOrCreate` below
                    // (pure waste — same recordName, same store).
                    await mountLoaded(from: existing, identity: identity)
                    return
                case .absent:
                    // Confirmed absent OR the precheck's own fetch failed —
                    // both fall through to `loadOrCreate`, which creates the
                    // fresh session (and is itself local-first: its own fetch
                    // failure ALSO degrades to a fresh session, never blocks).
                    break
                }
            }
            let snapshot = try await persistence.loadOrCreate(
                puzzleId: puzzleId,
                mode: identity.kind,
                difficulty: identity.difficulty
            )
            await mountLoaded(from: snapshot, identity: identity)
        } catch {
            // M10 (issue #67): typed bucket + funnel report. The view
            // displays the localized bucket copy; engineering OSLog / the
            // recent-errors buffer carries the underlying error detail.
            let bucket = UserFacingError.classify(error)
            await errorReporter.report(
                bucket,
                underlying: error,
                source: "BoardLoaderView.load"
            )
            state = .failed(bucket)
        }
    }

    /// Builds the live `GameViewModel` from an already-resolved snapshot and
    /// starts/resumes its session. Shared by the fresh-session path
    /// (`loadOrCreate`) and the #842 daily precheck's not-yet-completed
    /// branch (`loadIfExists`) so both mount identically without duplicating
    /// this construction.
    private func mountLoaded(from snapshot: GameSessionSnapshot, identity: PuzzleIdentity) async {
        // #579 phase 1: build a per-session adapter when Telemetry is wired;
        // fall back to NoOp so previews / tests are unaffected.
        let gameTelemetry: any GameStateTelemetry = telemetry.map {
            GameStateTelemetryAdapter(
                telemetry: $0,
                puzzleId: puzzleId,
                mode: identity.kind,
                difficulty: identity.difficulty
            )
        } ?? NoOpGameStateTelemetry()
        let session = await GameSession.restore(from: snapshot, telemetry: gameTelemetry)
        let viewModel = GameViewModel(
            identity: identity,
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            initialMistakeCount: snapshot.mistakeCount,
            // #849 Finding 2: thread the restored undo state in at
            // construction so the leave/pause toolbar never renders a
            // transient wrong label for a resumed mid-game board while
            // `startOrResume()`'s resync is still in flight.
            initialCanUndo: !snapshot.undoMoves.isEmpty,
            persistence: persistence,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer
        )
        state = .loaded(viewModel)
        // #227: kick the session into `.playing` (idle → start, paused →
        // resume). Without this, digit-pad taps fail the `.playing` gate
        // inside `GameSession` and are silently absorbed by `runSession`,
        // and `elapsedSeconds` stays at 0 because `runningSince` is nil.
        await viewModel.startOrResume()
    }

    #if DEBUG
    /// #719 testable core — extracted from `load()` so a unit test can drive
    /// the `-uitest-loader-fail` hook without needing a live process launch
    /// argument. `load()` calls the no-arg overload (real
    /// `ProcessInfo.processInfo.arguments`).
    static func isLoaderFailLaunch(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        arguments.contains(UITestLaunchArg.loaderFail)
    }
    #endif

    /// Derive `PuzzleIdentity` from `puzzleId` string.
    ///
    /// Two formats per `PuzzleIdentity` static factories:
    ///   - daily:    "YYYY-MM-DD-{difficulty}"
    ///   - practice: "practice-{base32}-{difficulty}"
    ///
    /// Difficulty is the suffix after the last `-`. If parsing fails the
    /// difficulty falls back to `.easy` so the load path still progresses;
    /// the snapshot's `puzzle.difficulty` is the authoritative value used
    /// by `BoardView` (this identity only feeds the header label).
    private static func identity(from puzzleId: String) -> PuzzleIdentity {
        let kind: Mode = puzzleId.hasPrefix("practice-") ? .practice : .daily
        let difficultyRaw = puzzleId.split(separator: "-").last.map(String.init) ?? Difficulty.easy.rawValue
        let difficulty = Difficulty(rawValue: difficultyRaw) ?? .easy
        return PuzzleIdentity(puzzleId: puzzleId, kind: kind, difficulty: difficulty)
    }
}
