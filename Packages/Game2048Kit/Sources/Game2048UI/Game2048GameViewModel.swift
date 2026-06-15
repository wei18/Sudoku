// Game2048GameViewModel — @MainActor @Observable bridge between the
// `Game2048Session` actor and SwiftUI's `Game2048BoardView`.
//
// Pattern mirrors MinesweeperGameViewModel exactly: the actor is the source of
// truth; the ViewModel caches the most recent snapshot and republishes it to
// the view tree after every `await` round-trip.
//
// Scope (M3): no telemetry, no Game Center, no audio — those seams land in M4.
// Persistence is a documented no-op stub; see `persistCurrentState()` below.
//
// SDD-004 OQ-004-3 RESOLVED: stuck = natural end-of-run (no Failed state);
// `reachedTarget` feeds achievements only; Daily = high score on shared seed.

public import Observation
public import Game2048Engine
public import Game2048GameState

@MainActor
@Observable
public final class Game2048GameViewModel {

    // MARK: - Session

    public let session: Game2048Session

    // MARK: - Snapshot / preview seam (mirrors MinesweeperGameViewModel(seeded:))

    /// When `true`, `refresh()` becomes a no-op so a pre-seeded snapshot
    /// survives `Game2048BoardView`'s in-body `.onAppear { Task { refresh() } }`.
    /// Production callsites never set this; tests and previews may.
    private let isSeeded: Bool

    // MARK: - Mode

    /// Daily vs. practice classification — forwarded from the route.
    /// Stored so a rebuilt view on nav-pop keeps the same GC submit gate (M4).
    public let mode: GameMode

    // MARK: - Cached snapshot

    public private(set) var snapshot: Game2048SessionSnapshot

    // MARK: - Convenience accessors

    public var board: Board { snapshot.board }
    public var score: Int { snapshot.score }
    public var moveCount: Int { snapshot.moveCount }
    public var status: Game2048SessionStatus { snapshot.status }
    public var elapsedSeconds: Int { snapshot.elapsedSeconds }
    public var reachedTarget: Bool { snapshot.reachedTarget }

    public var isTerminal: Bool { status == .stuck }
    public var isPaused: Bool { status == .paused }

    // MARK: - Init

    /// Construct a fresh session from a seed.
    public convenience init(seed: UInt64 = 0, mode: GameMode = .practice) {
        self.init(session: Game2048Session(seed: seed), mode: mode)
    }

    /// Construct from an existing session (previews, composition).
    public init(session: Game2048Session, mode: GameMode = .practice) {
        self.session = session
        self.mode = mode
        self.isSeeded = false
        // Synchronous bootstrap: take the initial in-flight snapshot.
        // The session starts with two tiles already spawned; the actor returns
        // the current in-memory state synchronously on the first call after init.
        // We produce a standing snapshot from known-zero values so SwiftUI has
        // something to render before the first `await refresh()`.
        self.snapshot = Game2048SessionSnapshot(
            seed: session.seed,
            board: Board(),
            score: 0,
            moveCount: 0,
            status: .playing,
            elapsedSeconds: 0,
            reachedTarget: false
        )
    }

    /// Snapshot / preview seam. Installs a fixed, fully-formed snapshot and
    /// marks the view model seeded so `refresh()` is a no-op. Used only by
    /// snapshot tests + SwiftUI previews; production never sets `isSeeded`.
    public init(seeded snapshot: Game2048SessionSnapshot) {
        self.session = Game2048Session(seed: snapshot.seed)
        self.mode = .practice
        self.snapshot = snapshot
        self.isSeeded = true
    }

    // MARK: - Refresh

    /// Pull the latest snapshot from the actor (elapsed-time ticks).
    /// No-op when seeded so the fixture survives capture.
    public func refresh() async {
        guard !isSeeded else { return }
        snapshot = await session.snapshot()
    }

    // MARK: - Actions

    /// Attempt a slide in `direction`. Returns immediately; the snapshot is
    /// updated in place after the actor's synchronous `slide` completes.
    public func slide(_ direction: Direction) async {
        guard !isSeeded else { return }
        snapshot = await session.slide(direction)
    }

    // MARK: - Pause / resume

    /// Pause the game: freeze the elapsed clock. No-op when seeded or not playing.
    /// Mirrors MinesweeperGameViewModel.pause().
    public func pause() async {
        guard !isSeeded else { return }
        snapshot = await session.pause()
        await persistCurrentState()
    }

    /// Resume the game: restart the clock. No-op when seeded or not paused.
    /// Mirrors MinesweeperGameViewModel.resume().
    public func resume() async {
        guard !isSeeded else { return }
        snapshot = await session.resume()
    }

    // MARK: - Persistence seam (M4 stub)
    //
    // M4 will wire Game2048SavedGameStore (mirroring MinesweeperSavedGameStore).
    // At M3, this is an intentional no-op so the view-lifecycle hooks
    // (scenePhase == .background, onDisappear, pause) have their call-sites wired
    // and the M4 diff is purely additive (inject `store` + `recordName` into the
    // VM's init, guard on nil, call store.save).
    //
    // Why not bring PersistenceKit in now: the store is a CloudKit actor; eagerly
    // pulling `CKContainer.default()` in an unentitled test runner produces an
    // uncatchable ObjC CKException (see CLAUDE.md "Don't trust 'it compiles'").
    // The lazy factory pattern (`PrivateCKGatewayFactory`) that guards this lives
    // in `PersistenceKit`; adding that dependency for a stub would force all
    // Game2048UITests to carry the CloudKit entitlement or crash. M4 resolves
    // this by introducing `Game2048Persistence` with the factory pattern in place.
    public func persistCurrentState() async {
        // M4: guard !isSeeded, let store, let recordName else { return }
        // M4: guard snapshot.status != .playing || ... else { return }
        // M4: try await store.save(snapshot, modeRaw: mode.rawValue, recordName: recordName)
    }
}
