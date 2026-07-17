// MinesweeperDailyReplayLoaderView — async host for the `.replayDailyBoard`
// route (#841: "daily retry after loss generates a different board per first
// click — daily must be one fixed game").
//
// Root cause (#841): `MinesweeperEngine.placeMines` places mines on the
// FIRST REVEAL, seeded `dailySeed &+ firstClickSalt(row,col)` — deliberate
// first-click safety, but it means the layout depends on WHICH cell the
// player taps first. A daily's first-ever attempt (`.board(mode: .daily)`)
// legitimately uses this deferred/salted path once. But a FAILED daily's
// free replay (`.replayDailyBoard`, Epic 8 / SDD-003) used to rebuild a
// brand-new `MinesweeperBoardView(difficulty:seed:)` the exact same way —
// so a different first tap on retry silently produced a different board,
// even though the daily is supposed to be one fixed game.
//
// Fix (issue direction 1, less invasive than re-deriving a canonical
// seed-only layout): the day's first-ever attempt already writes its full
// board — mines included, `Cell.isMine` is not reveal-state-gated — to the
// daily's own `SavedGame` record the moment it goes terminal
// (`MinesweeperGameViewModel.persistCurrentState()`, called from
// `reveal()`'s lost/won branch). That "failed" record is the exact reason
// the hub shows a Failed card in the first place, so it is guaranteed to
// exist whenever this loader runs. This view fetches it (bypassing
// `loadInProgress`'s resumable-only filter via the new
// `MinesweeperSavedGameStore.loadSnapshot`), extracts the mine layout
// (`MinesweeperSessionSnapshot.mineIndices`), and constructs the replay
// session with `MinesweeperSession.init(difficulty:seed:fixedMineIndices:)`
// — mines already placed, decoupled from whatever cell THIS replay's first
// tap lands on. No new CloudKit field: the existing non-queryable
// `stateBlob` payload already carried this data.
//
// Second-attempt semantics (explicit, per dispatch): a fixed replay layout
// has NO first-click safety — the very first tap may hit a mine. That is
// the standard, accepted contract for a fixed board (safety only ever
// applied to the ORIGINAL first-ever attempt, which produced this layout)
// and the loss counts like any other; nothing here special-cases it.
//
// Round 2 (adversarial CR, #841): honest-failure tri-state, mirroring
// `MinesweeperBoardLoaderView` exactly instead of a blanket catch-all.
// `store.loadSnapshot` can resolve three ways, and they are NOT
// interchangeable:
//   1. Returns a snapshot → recover the persisted layout (the golden path).
//   2. Returns `nil` → CONFIRMED ABSENT. Either the record genuinely never
//      existed, or the store's own `fetchPayload` already collapsed an
//      iCloud-signed-out fetch to "no record" (same convention
//      `loadInProgress` / `latestInProgress` already use). Either way there
//      is nothing to recover — falling back to the ordinary deferred/
//      first-click-safe session is correct, not a silent-different-board bug.
//   3. THROWS → existence is UNKNOWN (a network blip, CK service hiccup —
//      anything `fetchPayload` doesn't itself degrade). Falling back here
//      would silently mount a DIFFERENT board than the one the player
//      already lost on — reintroducing the exact #841 bug behind a transient
//      network error. So this case does NOT fall back: it propagates,
//      `load()` classifies it and lands the view in `.failed`, same honest
//      contract `MinesweeperBoardLoaderView` documents ("instead of silently
//      mounting a fresh board that would LOOK like the save was lost").
//
// Practice mode and the day's ORIGINAL first-ever attempt
// (`.board(mode: .daily)` → deferred placement, unchanged) are untouched by
// this file — see `MinesweeperEngine.placeMines(firstClickRow:col:)`, still
// exercised verbatim.

public import SwiftUI
public import GameAudio
public import MinesweeperEngine
internal import MinesweeperGameState
public import MinesweeperPersistence
public import MonetizationCore
public import Telemetry
internal import GameShellUI

public struct MinesweeperDailyReplayLoaderView: View {

    private enum LoadState {
        case loading
        case loaded(MinesweeperGameViewModel)
        case failed(UserFacingError)
    }

    private let difficulty: Difficulty
    private let seed: UInt64
    private let recordName: String
    private let store: MinesweeperSavedGameStore
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let errorReporter: (any ErrorReporter)?
    private let soundPlayer: any SoundPlaying

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss

    public init(
        difficulty: Difficulty,
        seed: UInt64,
        recordName: String,
        store: MinesweeperSavedGameStore,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying()
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.recordName = recordName
        self.store = store
        self.adProvider = adProvider
        self.adGate = adGate
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
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
            // gameCenter: nil, store: nil / recordName: nil below — a replay
            // is never scored, never submitted, never persisted (unchanged
            // Epic 8 / SDD-003 contract; see MinesweeperGameCenterSubmitTests).
            MinesweeperBoardView(
                viewModel: viewModel,
                adProvider: adProvider,
                adGate: adGate,
                gameCenter: nil,
                soundPlayer: soundPlayer
            )
        case .failed(let userFacing):
            failedBlock(userFacing: userFacing)
        }
    }

    /// Mirrors `MinesweeperBoardLoaderView.failedBlock` exactly (#719's Close
    /// + Retry shape) — same reasoning applies here: on iOS the board's
    /// `fullScreenCover` has no interactive dismiss, so Retry alone would be
    /// a dead end for a failed replay-record fetch.
    private func failedBlock(userFacing: UserFacingError) -> some View {
        // spacing-exempt: 12pt — matches MinesweeperBoardLoaderView's
        // off-scale rationale (#762 PR3); this block is a verbatim mirror.
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
        .padding(20)
    }

    private func load() async {
        state = .loading
        do {
            let session = try await Self.makeReplaySession(
                difficulty: difficulty,
                seed: seed,
                recordName: recordName,
                store: store,
                errorReporter: errorReporter
            )
            let viewModel = MinesweeperGameViewModel(
                session: session,
                mode: .practice,
                gameCenter: nil,
                errorReporter: errorReporter,
                soundPlayer: soundPlayer,
                store: nil,
                recordName: nil,
                personalRecordStore: nil
            )
            state = .loaded(viewModel)
        } catch {
            // `makeReplaySession` already funneled the specific `loadSnapshot`
            // failure (distinct source, see below) — `UserFacingError.classify`
            // is a no-op pass-through on an already-classified error, so this
            // does not double-report; it only decides the view's state.
            state = .failed(UserFacingError.classify(error))
        }
    }

    /// #841 (round 2, adversarial CR): recover the persisted canonical layout
    /// from the daily's own "failed" `SavedGame` record and build a
    /// fixed-layout session from it.
    ///
    /// - `loadSnapshot` returns `nil` (confirmed absent, or a corrupt/legacy
    ///   blob whose mine count doesn't match the difficulty) → falls back to
    ///   the ordinary deferred/first-click-salted session
    ///   (`MinesweeperSession(difficulty:seed:)` — pre-#841 behavior).
    ///   Nothing usable exists; a fresh first-click-safe board is correct.
    /// - `loadSnapshot` THROWS (fetch failed — existence unknown, e.g. a
    ///   network blip) → reports through `errorReporter` with a source
    ///   distinct from the view-level `load()` catch, then RE-THROWS. Must
    ///   NOT fall back here: silently building a different board on a
    ///   transient network error is the exact #841 bug reintroduced.
    ///
    /// `internal` (not `private`) + `static` so a unit test can drive it
    /// without mounting the SwiftUI view tree.
    static func makeReplaySession(
        difficulty: Difficulty,
        seed: UInt64,
        recordName: String,
        store: MinesweeperSavedGameStore,
        errorReporter: (any ErrorReporter)?
    ) async throws -> MinesweeperSession {
        let snapshot: MinesweeperSessionSnapshot?
        do {
            snapshot = try await store.loadSnapshot(recordName: recordName)
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "MinesweeperDailyReplayLoaderView.loadSnapshot"
            )
            throw error
        }
        guard let snapshot, snapshot.mineIndices.count == difficulty.mineCount else {
            // Confirmed absent, or an unusable (corrupt/legacy) blob — both
            // are "nothing to recover", not a fetch failure.
            return MinesweeperSession(difficulty: difficulty, seed: seed)
        }
        return try MinesweeperSession(difficulty: difficulty, seed: seed, fixedMineIndices: snapshot.mineIndices)
    }
}
