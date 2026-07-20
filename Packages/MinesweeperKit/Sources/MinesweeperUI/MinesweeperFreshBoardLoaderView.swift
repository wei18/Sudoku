// MinesweeperFreshBoardLoaderView — identity-reset host for a fresh
// difficulty+seed board (#910: Practice "Play Again" left the exploded board
// frozen).
//
// `MinesweeperBoardView`'s `difficulty:seed:mode:` init builds its
// `MinesweeperGameViewModel` once, via `@State private var viewModel =
// State(initialValue: …)`. `@State`'s `initialValue` is honored only the
// FIRST time SwiftUI creates a view at a given position in the tree. Play
// Again's `onPlayAgain` closure (`MinesweeperBoardView.completionSurface`)
// clears the completion VM, dismisses the presenting fullScreenCover, and
// immediately re-presents a new `.board` route at a fresh seed — all inside
// the same closure, with no `await` between dismiss and re-present. SwiftUI
// can coalesce that into a single update pass, so the re-presented board
// keeps the SAME structural identity (same view type, same tree position)
// instead of tearing down and remounting. The new seed is then silently
// discarded and the just-exploded board survives on screen.
//
// Fix mirrors the existing `MinesweeperBoardLoaderView` (the `.resumeBoard`
// loader, keyed on `recordName`) and Sudoku's `SudokuUI.BoardLoaderView`
// (keyed on `puzzleId`): own the `MinesweeperGameViewModel` behind a
// `LoadState` `@State` that `.task(id:)` explicitly REASSIGNS whenever the
// (difficulty, seed) key changes — `.task(id:)` re-fires on an id change
// independent of the view's structural identity, so even a same-tick
// dismiss+represent still rebuilds a fresh view model.
//
// #910 round 2 (code review + sim repro caught a bug ONE LEVEL DEEPER than
// the above): reassigning `state` from `.loaded(vm1)` straight to
// `.loaded(vm2)` is NOT enough by itself. Both `content`'s `.loading` and
// `.loaded` cases render at the SAME position in the view tree, so if the
// switch stays in `.loaded` across the reassignment, the nested
// `MinesweeperBoardView(viewModel: vm2)` is treated as an UPDATE of the
// SAME structural identity that was already showing vm1 — and
// `MinesweeperBoardView` has this exact same `@State`'s `initialValue`
// pitfall one level down (`@State private var viewModel = State(
// initialValue:)`, only honored on first creation), so vm2 is silently
// discarded and the stale, already-lost vm1 keeps driving the board. The
// bug reproduces again, just nested.
//
// Both sibling loaders this file mirrors (`MinesweeperBoardLoaderView.swift`,
// Sudoku's `BoardLoaderView.swift`) dodge this because their `load()` sets
// `state = .loading` and THEN does a REAL `await` (a persistence/CloudKit
// fetch) before `.loaded` — that suspension point gives SwiftUI an actual
// render pass showing `.loading` (tearing the old board down) before
// `.loaded` mounts a fresh one. `MinesweeperGameViewModel.init(difficulty:
// seed:mode:…)` has NO async work — it is fully synchronous — so setting
// `state = .loading` immediately followed by `state = .loaded(vm2)` in the
// same task, with no suspension between them, risks SwiftUI coalescing both
// mutations into a single update that never actually renders `.loading`.
// Relying on that render would make the fix depend on scheduling behavior
// this file has no control over.
//
// Fix: attach `.id(BoardKey(difficulty:seed:))` directly to the rendered
// `MinesweeperBoardView` (see `boardContent(viewModel:)` below) instead of
// depending on a rendered `.loading` frame. `.id()` is SwiftUI's documented,
// deterministic identity override — a changed id forces a teardown+remount
// of that subtree regardless of which switch case rendered the previous
// frame, so `MinesweeperBoardView`'s own `@State` is guaranteed to see vm2
// as a genuinely first creation. This is a deliberate mirror ASYMMETRY vs.
// the two sibling loaders (justified above, not an oversight): they can
// lean on their async gap; this loader cannot, so it uses the stronger,
// timing-independent primitive instead.
public import SwiftUI
public import GameAudio
public import GameCenterClient
public import MinesweeperEngine
public import MinesweeperPersistence
public import MonetizationCore
public import Telemetry
// #814: `ReminderPrimerCoordinator` (SettingsUI) appears in the public init's
// `makeDailyReminderPrimer` builder — mirrors `MinesweeperBoardLoaderView`.
public import SettingsUI

public struct MinesweeperFreshBoardLoaderView: View {

    /// The identity `.task(id:)` AND `.id()` both key on — a NEW key (either
    /// field) means a genuinely different board, so the view model must be
    /// rebuilt AND the rendered `MinesweeperBoardView` must be torn down and
    /// remounted (see `boardContent(viewModel:)` below). `internal` (not
    /// `private`) + `Hashable` (not just `Equatable`, `.id()` requires it) so
    /// `MinesweeperFreshBoardLoaderViewIdentityTests` can mirror-reflect the
    /// rendered `.id()` payload and compare it directly.
    struct BoardKey: Hashable {
        let difficulty: Difficulty
        let seed: UInt64
    }

    private enum LoadState {
        case loading
        case loaded(MinesweeperGameViewModel)
    }

    private let difficulty: Difficulty
    private let seed: UInt64
    private let mode: GameMode
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    private let soundPlayer: any SoundPlaying
    private let onPlayAgain: ((Difficulty) -> Void)?
    private let makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)?
    private let store: MinesweeperSavedGameStore?
    private let recordName: String?
    private let personalRecordStore: MinesweeperPersonalRecordStore?

    @State private var state: LoadState = .loading
    @Environment(\.theme) private var theme

    public init(
        difficulty: Difficulty,
        seed: UInt64,
        mode: GameMode,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        onPlayAgain: ((Difficulty) -> Void)? = nil,
        makeDailyReminderPrimer: (@MainActor () -> ReminderPrimerCoordinator)? = nil,
        store: MinesweeperSavedGameStore? = nil,
        recordName: String? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil
    ) {
        self.difficulty = difficulty
        self.seed = seed
        self.mode = mode
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.soundPlayer = soundPlayer
        self.onPlayAgain = onPlayAgain
        self.makeDailyReminderPrimer = makeDailyReminderPrimer
        self.store = store
        self.recordName = recordName
        self.personalRecordStore = personalRecordStore
    }

    public var body: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(theme.surface.background.resolved)
            .task(id: BoardKey(difficulty: difficulty, seed: seed)) {
                state = .loaded(makeViewModel())
            }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView()
                .controlSize(.large)
        case .loaded(let viewModel):
            boardContent(viewModel: viewModel)
        }
    }

    // #910 round 2: the `.id()` is the actual fix — see the header doc for
    // why this loader can't rely on a rendered `.loading` frame the way its
    // sibling loaders do. `internal` (not `private`) so
    // `MinesweeperFreshBoardLoaderViewIdentityTests` can call this directly
    // (bypassing `.task`/`state` entirely) and Mirror-reflect the returned
    // `SwiftUI.IDView` to assert the `.id()` payload is present and keyed
    // correctly — a regression that drops the `.id()` call would make the
    // dumped value a bare `MinesweeperBoardView` again and fail that test.
    func boardContent(viewModel: MinesweeperGameViewModel) -> some View {
        MinesweeperBoardView(
            viewModel: viewModel,
            adProvider: adProvider,
            adGate: adGate,
            gameCenter: gameCenter,
            soundPlayer: soundPlayer,
            onPlayAgain: onPlayAgain,
            makeDailyReminderPrimer: makeDailyReminderPrimer
        )
        .id(BoardKey(difficulty: difficulty, seed: seed))
    }

    private func makeViewModel() -> MinesweeperGameViewModel {
        Self.makeViewModel(
            difficulty: difficulty,
            seed: seed,
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer,
            store: store,
            recordName: recordName,
            personalRecordStore: personalRecordStore
        )
    }

    // #910 test seam: the exact `MinesweeperGameViewModel` construction the
    // `.task(id:)` reload performs, factored out as a `static` so
    // `MinesweeperFreshBoardLoaderViewIdentityTests` can call it directly
    // (twice, at different seeds) and assert each call returns an
    // INDEPENDENT, fresh `.idle` instance — the exact guarantee the old
    // `@State`'s `initialValue`-only construction did NOT provide. `internal`
    // (not `private`), mirroring this file's sibling views' convention of
    // widening exactly the seam a test needs (e.g.
    // `MinesweeperBoardView.tapModeKey`).
    static func makeViewModel(
        difficulty: Difficulty,
        seed: UInt64,
        mode: GameMode,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        soundPlayer: any SoundPlaying = NoopSoundPlaying(),
        store: MinesweeperSavedGameStore? = nil,
        recordName: String? = nil,
        personalRecordStore: MinesweeperPersonalRecordStore? = nil
    ) -> MinesweeperGameViewModel {
        MinesweeperGameViewModel(
            difficulty: difficulty,
            seed: seed,
            mode: mode,
            gameCenter: gameCenter,
            errorReporter: errorReporter,
            soundPlayer: soundPlayer,
            store: store,
            recordName: recordName,
            personalRecordStore: personalRecordStore
        )
    }
}
