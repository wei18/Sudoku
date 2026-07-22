// MinesweeperBoardLoaderView — async restore host for the `.resumeBoard`
// route (#455 step 4). Mirrors Sudoku's `BoardLoaderView` shape: a small
// loading → loaded(VM) → failed(UserFacingError) state machine in front of
// the real board.
//
// Restore path: `store.loadInProgress(recordName:)` → decode the persisted
// `MinesweeperSessionSnapshot` → `MinesweeperSession.restore(from:)` rebuilds
// the exact seed-derived board with the saved reveal/flag state. The restored
// session comes back `.paused` (step-1 contract), so the board mounts under
// the pause cover and the player taps to resume — elapsed never jumps.
//
// Failure honesty: a missing record (cleared elsewhere / iCloud lag), a
// `schemaVersionTooNew` blob from a newer build, or a corrupt blob all land in
// `.failed` with the classified `UserFacingError` (+ funnel), instead of
// silently mounting a fresh board that would LOOK like the save was lost.
//
// #719: the `.failed` screen used to be a dead end on iOS (fullScreenCover
// has no interactive dismiss) — Retry was the ONLY affordance, and MS resume
// is genuinely reachable here (an offline tap on the Resume pill hits this
// path for real). `failedBlock` now also offers Close, wired to the same
// `@Environment(\.dismiss)` the board's own Leave button uses
// (MinesweeperBoardView.swift), and a DEBUG-only launch hook
// (`UITestLaunchArg.loaderFail`) lets sim E2E drive straight into
// `.failed(.unknown)` without a real CloudKit failure repro.

public import SwiftUI
public import GameCenterClient
public import GameAudio
public import MinesweeperEngine
public import MinesweeperGameState
public import MinesweeperPersistence
public import MonetizationCore
public import Telemetry
// #814: `ReminderPrimerCoordinator` (SettingsUI) appears in the public init's
// `makeDailyReminderPrimer` builder — mirrors Sudoku's BoardLoaderView (#610).
public import SettingsUI
internal import GameShellUI
// #719: `UITestLaunchArg.loaderFail` DEBUG hook.
import GameAppKit

public struct MinesweeperBoardLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(MinesweeperGameViewModel)
        case failed(UserFacingError)
    }

    private let recordName: String
    private let mode: GameMode
    private let store: MinesweeperSavedGameStore
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    private let soundPlayer: any SoundPlaying
    // #699: threaded into the restored VM so a resumed daily board that wins
    // still records the personal best — same seam as `store`.
    private let personalRecordStore: MinesweeperPersonalRecordStore?
    // #814: Daily-win reminder primer builder, forwarded into the restored
    // board so a resumed daily that wins still offers the primer (mirrors
    // Sudoku BoardLoaderView's `makeDailyReminderPrimer`, #610). Defaults nil
    // so existing callsites (tests, previews) compile unchanged.
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    // #719: snapshot/test-only seam — when non-nil, `state` is pre-seeded to
    // `.failed(_)` and the `.task`-driven `load()` is skipped, so a
    // deterministic test can render `failedBlock` without a live persistence
    // fetch racing to overwrite it. `nil` in every production callsite —
    // mirrors this same file's own `completionViewModelForSnapshot`-style seam
    // used elsewhere in MinesweeperUI.
    private let failedForSnapshot: UserFacingError?

    @State private var state: LoadState
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(
        recordName: String,
        mode: GameMode,
        store: MinesweeperSavedGameStore,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        personalRecordStore: MinesweeperPersonalRecordStore? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        failedForSnapshot: UserFacingError? = nil
    ) {
        self.recordName = recordName
        self.mode = mode
        self.store = store
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.personalRecordStore = personalRecordStore
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.failedForSnapshot = failedForSnapshot
        self._state = State(initialValue: failedForSnapshot.map { .failed($0) } ?? .loading)
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: recordName) {
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
            MinesweeperBoardView(
                viewModel: viewModel,
                adProvider: adProvider,
                adGate: adGate,
                gameCenter: gameCenter,
                soundPlayer: soundPlayer,
                // #814: Daily-win reminder primer for the resumed board's
                // completion overlay (the board's own gate keeps it nil on
                // loss / practice).
                makeDailyReminderPrimer: makeDailyReminderPrimer
            )
        case .failed(let userFacing):
            failedBlock(userFacing: userFacing)
        }
    }

    private func failedBlock(userFacing: UserFacingError) -> some View {
        // spacing-exempt: 12pt (icon/text/buttons stack gap) predates the
        // 5-tier `SpacingTokens` scale — no matching tier without snapping
        // and changing this screen's existing layout/snapshot (#762 PR3).
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load saved game.")
                .foregroundStyle(theme.text.primary.resolved)
            Text(LocalizedStringResource(stringLiteral: userFacing.messageKey))
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
                .multilineTextAlignment(.center)
            // #719: on iOS the board's fullScreenCover has no interactive
            // dismiss (see GameRoot.swift), so Retry used to be the ONLY
            // affordance here — a genuine trap for an offline Resume tap.
            // Close mirrors the same `@Environment(\.dismiss)` the board's
            // own Leave button uses (MinesweeperBoardView.swift). Harmless
            // -but-present on macOS too (push nav already has a system back
            // chevron) — consistency over platform-splitting.
            // spacing-exempt: 12pt (button row gap) — same off-scale
            // rationale as the outer VStack above (#762 PR3).
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Label("Close", systemImage: "xmark")
                }
                .buttonStyle(.bordered)
                // #935 N2: stable, non-localized anchor for the host-driven
                // XCUITest E2E flow.
                .accessibilityIdentifier("minesweeper.boardLoader.close")
                Button {
                    Task { await load() }
                } label: {
                    Label("Retry", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("minesweeper.boardLoader.retry")
            }
        }
        // spacing-exempt: 20pt (error card padding) predates the 5-tier
        // `SpacingTokens` scale — no matching tier without snapping and
        // changing this screen's existing layout/snapshot (#762 PR3).
        .padding(20)
    }

    private func load() async {
        state = .loading
        // #719: DEBUG-only sim E2E hook — forces `.failed` immediately,
        // skipping the real persistence fetch, so the Close exit affordance
        // can be verified without a real CloudKit failure repro.
        #if DEBUG
        if Self.isLoaderFailLaunch() {
            state = .failed(.unknown)
            return
        }
        #endif
        do {
            guard let snapshot = try await store.loadInProgress(recordName: recordName) else {
                // Record vanished between fetchResume and the tap (cleared on
                // another device / iCloud lag). Honest failure, not a silent
                // fresh board.
                state = .failed(.unknown)
                return
            }
            let session = await MinesweeperSession.restore(from: snapshot)
            let viewModel = MinesweeperGameViewModel(
                session: session,
                mode: mode,
                gameCenter: gameCenter,
                errorReporter: errorReporter,
                soundPlayer: soundPlayer,
                store: store,
                recordName: recordName,
                personalRecordStore: personalRecordStore
            )
            state = .loaded(viewModel)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperBoardLoaderView.load"
            )
            state = .failed(UserFacingError.classify(error))
        }
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
}

// MARK: - Record-name derivation

extension MinesweeperSavedGameStore {
    /// #455 step 4: the save's CloudKit identity, fixed at board creation —
    /// a daily board reuses `MinesweeperDaily.puzzleId`'s `daily-<day>-<diff>`
    /// shape for TODAY (the hub only routes to today's boards); practice gets
    /// the singleton per-difficulty slot. Lives in MinesweeperUI because the
    /// `GameMode` mapping is a UI-layer concept (the store itself speaks
    /// `modeRaw` strings — dependency direction, see `GameModeRaw`).
    public static func recordName(
        mode: GameMode,
        difficulty: Difficulty,
        now: Date = Date()
    ) -> String {
        switch mode {
        case .daily: recordName(dailyDay: UTCDay.string(from: now), difficulty: difficulty)
        case .practice: recordName(practice: difficulty)
        }
    }
}
