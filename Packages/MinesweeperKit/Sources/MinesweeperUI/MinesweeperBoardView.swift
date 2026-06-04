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

// swiftlint:disable file_length
// 410 lines vs 400 limit. The #297 snapshot seam (~10 lines) pushed a file that
// was already at the limit over it; the view is cohesive (one board renderer +
// its layout/overlay) and extracting a helper for a test seam would be a larger,
// non-surgical change. Mirrors the SudokuUI/Board/GameViewModel.swift precedent.

public import SwiftUI
public import GameCenterClient
public import MinesweeperEngine
public import MonetizationCore
internal import MinesweeperGameState
public import Telemetry

public struct MinesweeperBoardView: View {

    @Environment(\.theme) private var theme
    // #298 #6 (Tier-1 leftover): drive the Mac 2-column side-rail layout. On
    // iPad/Mac (regular width) the board + a control rail sit side-by-side,
    // mirroring Sudoku's BoardView.macLayout; iPhone (compact) keeps the
    // vertical stack. swiftui-interaction-footguns: read `horizontalSizeClass`,
    // which is `.regular` on Mac, not a hardcoded `#if os(macOS)`.
    @Environment(\.horizontalSizeClass) private var sizeClass

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
    // #297: snapshot / preview seam. `true` skips the in-body ticker `.task` so
    // a pre-seeded board survives capture and no Completion overlay is drawn
    // over a loss board. Defaults `false` — production never sets it, so the
    // live refresh path is preserved. Pairs with `MinesweeperGameViewModel(seeded:)`.
    private let suppressTickerForSnapshot: Bool

    public init(
        viewModel: MinesweeperGameViewModel,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        onNewGame: (() -> Void)? = nil,
        suppressTickerForSnapshot: Bool = false
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.adProvider = adProvider
        self.adGate = adGate
        self.gameCenter = gameCenter
        self.onNewGame = onNewGame
        self.suppressTickerForSnapshot = suppressTickerForSnapshot
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
        self.suppressTickerForSnapshot = false
    }

    public var body: some View {
        // #298 #6: compact (iPhone) keeps the vertical stack; regular (iPad /
        // Mac) splits into a 2-column board + control rail, mirroring Sudoku's
        // BoardView.macLayout.
        Group {
            if sizeClass == .regular {
                macLayout
            } else {
                compactLayout
            }
        }
        // #298 #11: theme spacing scale. `.padding()` default is 16, identical
        // to `theme.spacing.medium`, so this is a value-preserving migration (no
        // snapshot churn).
        .padding(theme.spacing.medium)
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
        // #298 #9: single elapsed-mirror ticker, replacing the prior
        // TimelineView-nested-`.task` 1 Hz hack (which re-fired a fresh `.task`
        // on every timeline tick — swiftui-interaction-footguns: .task re-fire).
        // Mirrors Sudoku BoardView: one `.task(id:)` owning a `while
        // !Task.isCancelled { sleep }` loop, cancelled automatically on
        // disappear. Keyed on the VM's identity so Retry (which swaps the VM in
        // place at the same seed) restarts the loop with a fresh clock.
        .task(id: ObjectIdentifier(viewModel)) {
            // #297: skip the ticker for a seeded snapshot board (see property).
            guard !suppressTickerForSnapshot else { return }
            // Pull once immediately so the first frame isn't stale. The very
            // first snapshot could already be terminal (e.g. a board restored
            // into a finished state); `.onChange` only fires on a transition,
            // so seed the completion VM here too.
            await viewModel.refresh()
            if viewModel.isTerminal, completionViewModel == nil {
                completionViewModel = makeCompletionViewModel()
            }
            // Then poll once per second while the game is live. The elapsed
            // label re-renders because `refresh()` republishes the @Observable
            // snapshot. Stop polling once terminal (the clock is frozen) but
            // keep the task alive so cancellation stays tied to the view.
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refresh()
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Compact (iPhone) layout

    private var compactLayout: some View {
        // Spacing literal preserved verbatim (12) from the pre-#298 VStack so the
        // recorded iPhone covered-board snapshots don't churn. The theme spacing
        // scale (#298 #11) is applied to the NEW Mac layout below; migrating the
        // compact literal would re-record baselines and is deferred to #11.
        VStack(spacing: 12) {
            statusBar
            modeToggle
            boardGrid
            bannerSlot
        }
    }

    // MARK: - Mac (regular) 2-column layout (#298 #6)
    //
    // Mirrors Sudoku's BoardView.macLayout (locked 2026-05-30): outer maxWidth
    // capped + centered, board on the left capped to a square, a ~260 pt control
    // rail on the right. MS's rail carries the status bar + the Reveal/Flag mode
    // toggle (MS has no digit pad), keeping the iPhone grid out of the wide Mac
    // detail pane (#298 critique: the board currently renders the iPhone stack
    // in the Mac detail).
    private var macLayout: some View {
        VStack(spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.large) {
                macBoardColumn
                controlRail
            }
            bannerSlot
        }
        .frame(maxWidth: Self.macOuterMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.medium)
    }

    private static let macOuterMaxWidth: CGFloat = 900
    private static let macBoardMaxSide: CGFloat = 600
    private static let macRailWidth: CGFloat = 260

    private var macBoardColumn: some View {
        boardGrid
            .frame(maxWidth: Self.macBoardMaxSide, maxHeight: Self.macBoardMaxSide)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    // The Mac control rail: status read-out + the Reveal/Flag toggle, stacked
    // vertically in a fixed-width column. The toggle keeps `.segmented` styling
    // (same control as iPhone) — only the placement changes.
    private var controlRail: some View {
        VStack(spacing: theme.spacing.medium) {
            statusBar
            modeToggle
            Spacer(minLength: 0)
        }
        .frame(width: Self.macRailWidth)
    }

    // MARK: - Banner slot
    //
    // Banner sits between the grid and the bottom edge. Mirrors Sudoku's
    // BoardView slot pattern. Suppressed during terminal states (win / lose) —
    // showing an ad on top of the Completion surface contradicts the moment's
    // tone, same way Sudoku suppresses banners during pause.
    @ViewBuilder
    private var bannerSlot: some View {
        if !viewModel.isTerminal, let adProvider, let adGate {
            MinesweeperBannerSlotView(adProvider: adProvider, adGate: adGate)
        }
    }

    // MARK: - Status bar

    private var statusBar: some View {
        // #298 #9: plain HStack — the elapsed/flag/status fields are read
        // straight off the @Observable view model, which republishes when the
        // ticker loop (`.task(id:)` on the body) refreshes the snapshot each
        // second. No TimelineView, no nested `.task`.
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
                            row: row,
                            column: col,
                            side: cellSide,
                            mode: interactionMode,
                            // #298 #7: on a loss, surface every mine. The detonated
                            // cell is already `.revealed`; the rest are still hidden
                            // and the cell button paints them from `cell.isMine`.
                            revealMines: viewModel.status == .lost,
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
            leaderboardId: MinesweeperLeaderboardID.daily(
                for: viewModel.session.difficulty
            ),
            gameCenter: gameCenter
        )
    }

    // The themed post-game surface. Retry rebuilds the session in place at the
    // SAME difficulty + seed, and clears the Completion VM so the next terminal
    // state rebuilds a fresh slice. Note: mine placement is deferred to the
    // first reveal, so the layout is determined by seed + opening tap — an
    // identical first tap reproduces the same board, a different one does not.
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
// swiftlint:enable file_length
