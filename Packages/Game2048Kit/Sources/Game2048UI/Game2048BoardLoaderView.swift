// Game2048BoardLoaderView — async restore host for the `.resumeBoard` route.
// Mirrors MinesweeperBoardLoaderView shape:
//   loading → loaded(VM) → failed(UserFacingError)
//
// Restore path: `store.loadInProgress(recordName:)` → decode persisted
// `Game2048SessionSnapshot` → `Game2048Session.restore(from:)` rebuilds the
// exact board. Restored sessions come back `.paused` (actor contract), so
// the board mounts under the pause cover; elapsed never jumps.
//
// Failure honesty: a missing record, schema-version mismatch, or corrupt blob
// all land in `.failed` with a classified `UserFacingError` (+ funnel),
// instead of silently mounting a fresh board.

public import SwiftUI
public import GameCenterClient
internal import Game2048Engine
internal import Game2048GameState
public import Game2048Persistence
public import MonetizationCore
public import Telemetry
internal import GameShellUI

public struct Game2048BoardLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(Game2048GameViewModel)
        case failed(UserFacingError)
    }

    private let recordName: String
    private let mode: GameMode
    private let store: Game2048SavedGameStore
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    private let onNewGame: (() -> Void)?

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme

    public init(
        recordName: String,
        mode: GameMode,
        store: Game2048SavedGameStore,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        onNewGame: (() -> Void)? = nil
    ) {
        self.recordName = recordName
        self.mode = mode
        self.store = store
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
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
            Game2048BoardView(
                viewModel: viewModel,
                adProvider: adProvider,
                adGate: adGate
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
                state = .failed(.unknown)
                return
            }
            let session = await Game2048Session.restore(from: snapshot)
            let viewModel = Game2048GameViewModel(
                session: session,
                mode: mode,
                gameCenter: gameCenter,
                errorReporter: errorReporter,
                store: store,
                recordName: recordName
            )
            state = .loaded(viewModel)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "Game2048BoardLoaderView.load"
            )
            state = .failed(UserFacingError.classify(error))
        }
    }
}

// MARK: - Record-name derivation (in Game2048UI where GameMode is defined)

extension Game2048SavedGameStore {
    /// Derive the save's CloudKit identity from mode + current date.
    /// Daily: `daily-<YYYY-MM-DD>` (one board per UTC day).
    /// Practice: `practice` (singleton slot — overwrites on each new game).
    /// Lives in Game2048UI because `GameMode` is a UI-layer enum
    /// (dependency direction: store speaks modeRaw strings).
    public static func recordName(mode: GameMode, now: Date = Date()) -> String {
        switch mode {
        case .daily: return recordName(dailyDay: UTCDay.string(from: now))
        case .practice: return practiceRecordName
        }
    }
}
