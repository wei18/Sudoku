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

public import MonetizationCore
public import SwiftUI
public import Persistence
public import SudokuPersistence
public import Telemetry
// #330 P2: the `SoundPlaying` seam forwarded into the live `GameViewModel`.
public import GameAudio
import SudokuGameState
import SudokuEngine

@MainActor
public struct BoardLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(GameViewModel)
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
    // Host navigation path, forwarded to `BoardView` so a solve can push the
    // `.completion` route. Optional → previews / tests mount without a stack.
    private let path: Binding<[AppRoute]>?
    // #579 phase 1: Telemetry fan-out for per-session adapter. `nil` (default)
    // → `NoOpGameStateTelemetry` so previews / tests are unaffected.
    private let telemetry: Telemetry?

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme

    public init(
        puzzleId: String,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        path: Binding<[AppRoute]>? = nil,
        telemetry: Telemetry? = nil
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
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: puzzleId) { await load() }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .loaded(let viewModel):
            BoardView(viewModel: viewModel, adProvider: adProvider, adGate: adGate, path: path)
        case .failed(let userFacing):
            failedBlock(userFacing: userFacing)
        }
    }

    private func failedBlock(userFacing: UserFacingError) -> some View {
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
        let identity = Self.identity(from: puzzleId)
        do {
            let snapshot = try await persistence.loadOrCreate(
                puzzleId: puzzleId,
                mode: identity.kind,
                difficulty: identity.difficulty
            )
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
