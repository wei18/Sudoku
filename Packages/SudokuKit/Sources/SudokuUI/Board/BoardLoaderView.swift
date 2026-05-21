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
public import PuzzleStore
import GameState
import SudokuEngine

@MainActor
public struct BoardLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(GameViewModel)
        case failed(String)
    }

    private let puzzleId: String
    private let puzzleProvider: any PuzzleProviderProtocol
    private let persistence: any PersistenceProtocol
    // v2.3.5: forwarded to `BoardView` so the banner slot can render
    // between the grid and the digit pad once the puzzle has loaded.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme

    public init(
        puzzleId: String,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self.puzzleId = puzzleId
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.adProvider = adProvider
        self.adGate = adGate
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
            BoardView(viewModel: viewModel, adProvider: adProvider, adGate: adGate)
        case .failed(let reason):
            failedBlock(reason: reason)
        }
    }

    private func failedBlock(reason: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundStyle(theme.status.warning.resolved)
            Text("Couldn't load puzzle.")
                .foregroundStyle(theme.text.primary.resolved)
            Text(reason)
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
                mode: identity.kind.rawValue,
                difficulty: identity.difficulty
            )
            let session = await GameSession.restore(from: snapshot)
            let viewModel = GameViewModel(
                identity: identity,
                session: session,
                initialBoard: snapshot.currentBoard,
                initialNotes: snapshot.notes,
                initialStatus: snapshot.status,
                initialElapsedSeconds: snapshot.elapsedSeconds,
                persistence: persistence
            )
            state = .loaded(viewModel)
        } catch {
            state = .failed(String(describing: error))
        }
    }

    /// Derive `PuzzleIdentity` from `puzzleId` string.
    ///
    /// Two formats per `PuzzleIdentity` static factories:
    ///   - daily:    "YYYY-MM-DD-{difficulty}"
    ///   - practice: "practice-{base32}-{difficulty}"
    ///
    /// Difficulty is the suffix after the last `-`. If parsing fails the
    /// difficulty falls back to `"easy"` so the load path still progresses;
    /// the snapshot's `puzzle.difficulty` is the authoritative value used
    /// by `BoardView` (this identity only feeds the header label).
    private static func identity(from puzzleId: String) -> PuzzleIdentity {
        let kind: PuzzleKind = puzzleId.hasPrefix("practice-") ? .practice : .daily
        let difficulty = puzzleId.split(separator: "-").last.map(String.init) ?? "easy"
        return PuzzleIdentity(puzzleId: puzzleId, kind: kind, difficulty: difficulty)
    }
}
