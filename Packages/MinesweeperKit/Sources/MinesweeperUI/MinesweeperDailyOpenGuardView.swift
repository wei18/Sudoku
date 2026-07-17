// MinesweeperDailyOpenGuardView — open-time re-check for `.board(mode: .daily)`
// (#842).
//
// Root cause: `MinesweeperDailyHubViewModel.cardTapped` decides
// completed/failed/playable from the tapped `MinesweeperDailyCard`'s
// `isCompleted`/`isFailed` flags, which are phase-1-stale (`false`/`false`)
// until `fillCompletionAndFailureOverlay` (phase 2) lands (#530/#774). A fast
// tap on a card whose REAL daily state is already completed or failed during
// that window used to push the scored `.board(mode: .daily)` route
// regardless: a loss there re-derives mine placement from THIS attempt's own
// first click (the engine's deferred/first-click-salted path, #841) —
// OVERWRITING the real Failed record with a DIFFERENT layout — and a win
// double-submits a Game Center score.
//
// Fix (mirrors Sudoku's `BoardLoaderView` daily precheck, the analogous seam
// for the sibling app): `.board(mode: .daily)` is reachable from exactly ONE
// call site (`MinesweeperDailyHubViewModel.cardTapped`, confirmed by grep —
// Practice always constructs `.board(mode: .practice)` instead), so wrapping
// its mount point here — between the tap and the real board — is the ONE
// place every daily-board OPEN funnels through regardless of how stale the
// caller's own card data was. It re-queries `MinesweeperSavedGameStore`'s
// completed/failed ids for TODAY (the store's truth, not the VM's cached
// cards) before ever mounting a playable board:
//   - completed → inline Completion surface (the same rendering the
//     `.completion` route builds — #386).
//   - failed    → delegates to `MinesweeperDailyReplayLoaderView` (#841's
//     fixed-layout replay), NOT a fresh scored board.
//   - neither, OR the fetch itself failed → mounts the ordinary fresh
//     `MinesweeperBoardView`. See `resolve`'s doc for why a fetch failure
//     degrades here instead of blocking (adversarial-CR round-2 adjudication,
//     #526).
//
// Why a VM-level re-query (à la Sudoku's original `cardTapped`) was rejected:
// MS has no async board loader in front of a FRESH `.board(mode: .daily)`
// mount today (only `.resumeBoard` has one) — introducing this guard view at
// the route-factory seam keeps `cardTapped` itself synchronous and fully
// unchanged (every existing routing test stays valid), while still being
// race-proof by construction for the one route it wraps. `LiveRouteFactory`
// only routes through here when `mode == .daily` AND a `savedGameStore` is
// wired; Practice and the no-store preview/test callsite fall straight
// through to the direct `MinesweeperBoardView` construction, byte-identical
// to pre-#842 behavior there.
//
// Known cosmetic accepted trade-off: a `.failed` outcome shows THIS view's
// own `.checking` spinner, then hands off to `MinesweeperDailyReplayLoaderView`,
// which has its own `.loading` spinner — a brief double-spinner rather than
// one continuous one. Not fixed in this round (flagged, accepted on review):
// merging the two loaders' state machines is a larger, non-surgical change
// for a sub-second cosmetic wrinkle on an already-rare path (a failed daily,
// re-tapped inside the phase-2 race window).

public import SwiftUI
public import GameCenterClient
public import GameAudio
public import MinesweeperEngine
public import MinesweeperPersistence
public import MonetizationCore
public import Telemetry
public import SettingsUI
internal import GameShellUI

public struct MinesweeperDailyOpenGuardView: View {

    private enum GuardState {
        case checking
        case resolved(DailyOpenOutcome)
    }

    /// #842 testable core, mirroring `MinesweeperDailyReplayLoaderView
    /// .makeReplaySession`'s pattern: the open-time re-check's decision,
    /// decoupled from `@State`, so a unit test can gate/hang the fetch and
    /// assert the outcome directly without mounting the view tree. No failure
    /// case — see `resolve`'s doc for the round-2 adjudication (a fetch
    /// failure degrades to `.playable`, it never blocks).
    enum DailyOpenOutcome: Equatable {
        case playable
        case completed
        case failed
    }

    private let difficulty: Difficulty
    private let seed: UInt64
    private let store: MinesweeperSavedGameStore
    private let dateProvider: @Sendable () -> Date
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    private let soundPlayer: any SoundPlaying
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    private let personalRecordStore: MinesweeperPersonalRecordStore?
    /// #842 round 2 (low finding): threaded through so the `.completed`
    /// outcome's Close can pop the board's own stack entry in a push context
    /// instead of unconditionally calling `dismiss()` — mirrors Sudoku's
    /// `BoardLoaderView.exitToHub` / `BoardView+Completion`'s #697 dual-context
    /// contract. `nil` in the real (modal, fullScreenCover) presentation —
    /// this is defensive for a future push-context mount, not exercised by
    /// production today (MS boards are always modal, like Sudoku's).
    private let path: Binding<[AppRoute]>?

    @State private var state: GuardState = .checking
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(
        difficulty: Difficulty,
        seed: UInt64,
        store: MinesweeperSavedGameStore,
        dateProvider: @escaping @Sendable () -> Date = { Date() },
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        path: Binding<[AppRoute]>? = nil
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.store = store
        self.dateProvider = dateProvider
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.personalRecordStore = personalRecordStore
        self.path = path
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: recordName) { await check() }
    }

    private var recordName: String {
        MinesweeperSavedGameStore.recordName(mode: .daily, difficulty: difficulty, now: dateProvider())
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .checking:
            ProgressView()
                .controlSize(.large)
        case .resolved(.playable):
            MinesweeperBoardView(
                difficulty: difficulty,
                seed: seed,
                mode: .daily,
                adProvider: adProvider,
                adGate: adGate,
                gameCenter: gameCenter,
                errorReporter: errorReporter,
                soundPlayer: soundPlayer,
                // Daily is one-per-day — no Play Again here, same rationale
                // `LiveRouteFactory`'s direct `.board` construction documents.
                onPlayAgain: nil,
                makeDailyReminderPrimer: makeDailyReminderPrimer,
                store: store,
                recordName: recordName,
                personalRecordStore: personalRecordStore
            )
        case .resolved(.completed):
            // #842: same scaffold + card `LiveRouteFactory`'s `.completion`
            // route builds (#386) — byte-identical rendering, just reached
            // from a different (pre-mount) seam, so this introduces no new
            // visual state to snapshot.
            CompletionOverlayScaffold(
                onClose: { exitToHub() },
                card: {
                    MinesweeperCompletionView(
                        viewModel: MinesweeperCompletionViewModel(
                            didWin: true,
                            elapsedSeconds: 0,
                            leaderboardId: MinesweeperLeaderboardID.daily(for: difficulty)
                        ),
                        reminderPrimer: makeDailyReminderPrimer?(),
                        onClose: nil,
                        showsElapsedTime: false
                    )
                }
            )
        case .resolved(.failed):
            // #841's fixed-layout replay — NOT a fresh scored board.
            MinesweeperDailyReplayLoaderView(
                difficulty: difficulty,
                seed: seed,
                recordName: recordName,
                store: store,
                adProvider: adProvider,
                adGate: adGate,
                errorReporter: errorReporter,
                soundPlayer: soundPlayer
            )
        }
    }

    /// #842 round 2 (low finding): mirrors `BoardView+Completion.exitToHub`
    /// exactly (#697 contract) — Close on the completed-redirect surface must
    /// land the player back on the hub on every presentation context, not
    /// just the modal one `dismiss()` alone handles.
    private func exitToHub() {
        guard let path else {
            dismiss()
            return
        }
        guard !path.wrappedValue.isEmpty else { return }
        path.wrappedValue.removeLast()
    }

    private func check() async {
        state = .checking
        let outcome = await Self.resolve(
            recordName: recordName,
            date: dateProvider(),
            store: store,
            errorReporter: errorReporter
        )
        state = .resolved(outcome)
    }

    /// Testable core — extracted from `check()` so a unit test can gate/hang
    /// the fetch (`store.fetchCompletedDailyIds` / `fetchFailedDailyIds`) and
    /// assert the outcome without mounting the view tree. `internal` (not
    /// `private`), `static` (no `self` capture needed).
    ///
    /// Adversarial-CR adjudication (#842 round 2): a fetch FAILURE here must
    /// never block daily play — degrades to `.playable` (the ordinary fresh
    /// board), after reporting through `errorReporter` (source
    /// `"MinesweeperDailyOpenGuardView.resolve"`) so the occurrence stays
    /// observable. This mirrors Sudoku's `BoardLoaderView.dailyPrecheck`'s
    /// same-round adjudication and the #526 guarantee
    /// `MinesweeperDailyHubViewModelOfflineTests` already pins for the hub's
    /// own phase-2 fetch ("CloudKit unreachable must never block daily play").
    /// An EARLIER version of this resolver instead returned `.checkFailed` (a
    /// blocking error screen) on fetch failure — that inverted the #526
    /// contract for every daily open, not just the #842 race window, and was
    /// rejected on review.
    static func resolve(
        recordName: String,
        date: Date,
        store: MinesweeperSavedGameStore,
        errorReporter: (any ErrorReporter)?
    ) async -> DailyOpenOutcome {
        do {
            let completed = try await store.fetchCompletedDailyIds(for: date)
            if completed.contains(recordName) {
                return .completed
            }
            let failed = try await store.fetchFailedDailyIds(for: date)
            return failed.contains(recordName) ? .failed : .playable
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperDailyOpenGuardView.resolve"
            )
            return .playable
        }
    }
}
