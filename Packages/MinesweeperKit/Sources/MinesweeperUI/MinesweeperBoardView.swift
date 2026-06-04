// MinesweeperBoardView — MVP SwiftUI board renderer.
//
// Renders an `MinesweeperGameViewModel` as a row-major grid of cell buttons:
//   - Tap = reveal OR flag, depending on the on-screen Reveal/Flag mode toggle
//     (#278 Tier-0 #3 — discoverable, works on iPhone tap + Mac click).
//   - Long-press (iOS) / secondary click via context menu (macOS) = toggle flag
//     (accelerators, available in either mode).
//
// The board grid is sized by a GeometryReader (#278 Tier-0 #1/#2): cell side is
// derived from the offered rect, fitting the NON-SQUARE board by its longer axis,
// and the board scrolls instead of shrinking below a tap-target floor.
//
// Win/lose overlay is plain Text on a translucent backdrop — no animation,
// no haptics, no localization (English inline per dispatch spec).

public import SwiftUI
public import GameCenterClient
public import MinesweeperEngine
public import MonetizationCore
internal import MinesweeperGameState
public import Telemetry

public struct MinesweeperBoardView: View {

    @State private var viewModel: MinesweeperGameViewModel
    // #278 Tier-0 #3: on-screen reveal/flag mode. View-local because it has no
    // engine semantics — it only routes which action a cell tap fires. Mirrors
    // Sudoku's pencil-mode toggle as a discoverable primary control.
    @State private var interactionMode: InteractionMode = .reveal
    // #292: the Completion overlay's VM. Held in `@State` so it survives the
    // board's recomputes (the status bar's 1 Hz TimelineView re-runs `body`
    // every second) — building it inline would reset its leaderboard-slice
    // fetch on every tick. Populated lazily the first time the board reaches a
    // terminal state, cleared on Retry. swiftui-interaction-footguns: a
    // recompute-rebuilt @Observable VM loses its loaded state + re-fires .task.
    @State private var completionViewModel: MinesweeperCompletionViewModel?
    // U15 (2026-06-03): banner slot wiring. Optional so the merged MVP `init`
    // shapes (used by `#Preview` + tests) keep compiling without monetization.
    // Production callsites wire both via `LiveRouteFactory`.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    // #292: Game Center client forwarded into the Completion overlay's
    // leaderboard-slice VM. Optional so MVP / preview callsites stay no-op
    // (the slice degrades to the sign-in affordance, never blocking the win).
    private let gameCenter: (any GameCenterClient)?
    // #292: New Game CTA on the Completion overlay → dismiss to root. The board
    // has no path binding of its own (it's constructed with difficulty+seed), so
    // the navigation owner (Home / Root) injects this. `nil` → the CTA is hidden
    // (preview / standalone board).
    private let onNewGame: (() -> Void)?

    public init(
        viewModel: MinesweeperGameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        onNewGame: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.onNewGame = onNewGame
    }

    public init(
        difficulty: Difficulty = .beginner,
        seed: UInt64 = 0,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        onNewGame: (() -> Void)? = nil
    ) {
        self._viewModel = State(initialValue: MinesweeperGameViewModel(
            difficulty: difficulty,
            seed: seed,
            gameCenter: gameCenter,
            errorReporter: errorReporter
        ))
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.onNewGame = onNewGame
    }

    public var body: some View {
        VStack(spacing: 12) {
            statusBar
            modeToggle
            boardGrid
            // Banner sits between the grid and the bottom edge. Mirrors
            // Sudoku's BoardView slot pattern. Suppressed during terminal
            // states (win / lose) — showing an ad on top of the Completion
            // surface contradicts the moment's tone, same way Sudoku
            // suppresses banners during pause.
            if !viewModel.isTerminal, let adProvider, let adGate {
                MinesweeperBannerSlotView(adProvider: adProvider, adGate: adGate)
            }
        }
        .padding()
        // #292: the post-game Completion surface replaces the old inline
        // `terminalOverlay` (plain Text on material). It covers the whole board
        // on win/lose with the result hero + leaderboard slice + CTAs. Mounted
        // as a full-cover overlay (not a pushed route) because the board owns its
        // terminal state inline and has no completion AppRoute.
        .overlay {
            if viewModel.isTerminal, let completionViewModel {
                completionSurface(completionViewModel)
            }
        }
        // Build the Completion VM once when the board crosses into a terminal
        // state (and not on every TimelineView tick). Cleared by Retry below.
        .onChange(of: viewModel.isTerminal) { _, isTerminal in
            if isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            } else if !isTerminal {
                completionViewModel = nil
            }
        }
        .task {
            await viewModel.refresh()
            // The very first snapshot could already be terminal (e.g. a board
            // restored into a finished state); `.onChange` only fires on a
            // transition, so seed the VM here too.
            if viewModel.isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            }
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        // TimelineView ticks at 1 Hz so the elapsed-seconds counter visibly
        // ticks during `.playing`. The `.task` inside re-fires on each tick
        // because the timeline context changes, pulling a fresh snapshot
        // from the actor (which also refreshes flag/status displays).
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            HStack {
                Label("\(viewModel.remainingMineCount)", systemImage: "flag.fill")
                    .monospacedDigit()
                Spacer()
                Text(statusText)
                    .font(.headline)
                Spacer()
                Label("\(viewModel.elapsedSeconds)", systemImage: "clock")
                    .monospacedDigit()
            }
            .font(.subheadline)
            .task { await viewModel.refresh() }
        }
    }

    private var statusText: String {
        switch viewModel.status {
        case .idle:    return "Ready"
        case .playing: return "Playing"
        case .won:     return "You won"
        case .lost:    return "Boom"
        }
    }

    // MARK: - Mode toggle (#278 Tier-0 #3)

    // Discoverable primary control for reveal vs flag. Modeled on Sudoku's
    // pencil-mode toggle (DigitPadView): a segmented control that routes which
    // action a cell tap fires. Works identically on iPhone (tap) and Mac
    // (click) — the previously invisible right-click/long-press are now just
    // accelerators on top of this.
    private var modeToggle: some View {
        Picker("Tap mode", selection: $interactionMode) {
            Label("Reveal", systemImage: "hand.tap").tag(InteractionMode.reveal)
            Label("Flag", systemImage: "flag.fill").tag(InteractionMode.flag)
        }
        .pickerStyle(.segmented)
        .accessibilityLabel("Tap action mode")
        .accessibilityValue(interactionMode == .flag ? "Flag" : "Reveal")
    }

    // MARK: - Grid

    // Cell-side floor (pt). Below this the board scrolls rather than shrinking
    // cells into an un-tappable size (#278 Tier-0 #2). 32pt keeps a deliberate
    // reveal tap comfortable; flag taps are now mode-driven so no precision
    // long-press is required on small cells.
    private static let minCellSide: CGFloat = 32
    private static let cellSpacing: CGFloat = 2

    private var boardGrid: some View {
        // GeometryReader reports the offered rectangle; we derive a single
        // square cell side that fits the NON-SQUARE board by its longer axis
        // (Expert is 16×30), then floor it for crisp glyphs. If that would drop
        // below the tap-target floor we clamp to the floor and let the board
        // scroll in both axes instead of shrinking.
        GeometryReader { geo in
            let rows = viewModel.rows
            let cols = viewModel.columns
            let spacing = Self.cellSpacing
            // Subtract the inter-cell gaps before dividing so the cells (not
            // the gaps) fill the offered box exactly.
            let availW = geo.size.width - spacing * CGFloat(cols - 1)
            let availH = geo.size.height - spacing * CGFloat(rows - 1)
            let fitted = floor(min(availW / CGFloat(cols), availH / CGFloat(rows)))
            let cellSide = max(Self.minCellSide, fitted)
            // Fits (side at/above floor): center the floored grid in the
            // offered rect — mirrors Sudoku BoardView's centered frame and
            // avoids the top-leading drift a ScrollView would impose (#278 CR).
            // Clamped (below floor, e.g. Expert on iPhone): the board exceeds
            // the rect, so scroll both axes instead of shrinking.
            if fitted >= Self.minCellSide {
                gridStack(rows: rows, cols: cols, cellSide: cellSide, spacing: spacing)
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    gridStack(rows: rows, cols: cols, cellSide: cellSide, spacing: spacing)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        // Reserve a square-ish slot; the GR fills whatever it is offered.
        .aspectRatio(boardAspectRatio, contentMode: .fit)
    }

    private var boardAspectRatio: CGFloat {
        CGFloat(viewModel.columns) / CGFloat(viewModel.rows)
    }

    private func gridStack(rows: Int, cols: Int, cellSide: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<cols, id: \.self) { col in
                        MinesweeperCellButton(
                            cell: viewModel.cell(row: row, col: col),
                            side: cellSide,
                            mode: interactionMode,
                            onReveal: {
                                Task { await viewModel.reveal(row: row, col: col) }
                            },
                            onToggleFlag: {
                                Task { await viewModel.toggleFlag(row: row, col: col) }
                            }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Completion overlay (#292)

    /// Construct the post-game VM from the current terminal snapshot. Called
    /// once per terminal transition (see `.onChange` / `.task` above) so the
    /// leaderboard-slice fetch + degrade state aren't reset by recomputes. The
    /// VM fetches the local-player-centred slice on a win, and stays hero-only
    /// on a loss.
    private func makeCompletionViewModel() -> MinesweeperCompletionViewModel {
        MinesweeperCompletionViewModel(
            didWin: viewModel.status == .won,
            elapsedSeconds: viewModel.elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.bestTime(
                for: viewModel.session.difficulty
            ),
            gameCenter: gameCenter
        )
    }

    // The themed post-game surface. Retry rebuilds the session in place at the
    // SAME difficulty + seed (a true replay; mines are placed deferred, so the
    // same seed reproduces the board) and clears the Completion VM so the next
    // terminal state rebuilds a fresh slice.
    private func completionSurface(_ completionViewModel: MinesweeperCompletionViewModel) -> some View {
        MinesweeperCompletionView(
            viewModel: completionViewModel,
            onNewGame: onNewGame,
            onRetry: {
                let difficulty = viewModel.session.difficulty
                let seed = viewModel.session.seed
                self.completionViewModel = nil
                viewModel = MinesweeperGameViewModel(
                    difficulty: difficulty,
                    seed: seed,
                    gameCenter: gameCenter
                )
            }
        )
    }
}

// `InteractionMode` + `MinesweeperCellButton` were extracted to
// `MinesweeperCellButton.swift` (#292) to keep this file under the lint ceiling.

// MARK: - Preview

#Preview("Beginner 9x9") {
    MinesweeperBoardView(difficulty: .beginner, seed: 42)
        .frame(minWidth: 360, minHeight: 480)
}
