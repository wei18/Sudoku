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

public import SwiftUI
public import GameCenterClient
public import GameAudio
public import MinesweeperEngine
public import MinesweeperGameState
public import MinesweeperPersistence
public import MonetizationCore
public import Telemetry
internal import GameShellUI

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
    private let onNewGame: (() -> Void)?

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme

    public init(
        recordName: String,
        mode: GameMode,
        store: MinesweeperSavedGameStore,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        onNewGame: (() -> Void)? = nil
    ) {
        self.recordName = recordName
        self.mode = mode
        self.store = store
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.onNewGame = onNewGame
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: recordName) { await load() }
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
                onNewGame: onNewGame
            )
        case .failed(let userFacing):
            failedBlock(userFacing: userFacing)
        }
    }

    private func failedBlock(userFacing: UserFacingError) -> some View {
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
            Button {
                Task { await load() }
            } label: {
                Label("Retry", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
    }

    private func load() async {
        state = .loading
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
                recordName: recordName
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
