// Game2048BoardView — SwiftUI board renderer for a 2048 game session.
//
// Mirrors MinesweeperBoardView exactly in structure:
//   - @Environment(\.gameChrome): pushes elapsed to the modal top chrome.
//   - @Environment(\.horizontalSizeClass): compact (iPhone) / regular (Mac) layout.
//   - @Environment(\.scenePhase): background → save point (M4 stub wired here).
//   - .onAppear { Task {} } not .task — Xcode 26 arm64 Release link bug (#361).
//   - Ticker loop: one `while !Task.isCancelled { sleep }` owned task, keyed on
//     the VM's identity so Retry (VM swap) restarts it.
//   - Terminal state: stuck board shows an inline "No moves" banner; full
//     CompletionScreen is M4 (same deferral as MS's completion overlay seam).
//   - Swipe gestures in all 4 directions calling viewModel.slide(_:).
//   - Tile animation via withAnimation on snap update, no over-engineering.
//
// M3→M4 seams:
//   - persistCurrentState() is a no-op stub (see Game2048GameViewModel).
//   - adProvider / adGate / onNewGame are nil placeholders (M4).
//   - CompletionScreen from GameShellKit replaces the inline stuck banner (M4).
//   - GameRoot modal flow (present + [X] + Leave Confirmation) is M4.

// Board view + gesture wiring + stuck overlay + pause cover in one cohesive file.
// Extracting helpers for the sub-400 line count would increase indirection
// without simplification — file_length disable is intentionally absent at M3.

public import SwiftUI
internal import Game2048Engine
internal import Game2048GameState
internal import GameShellUI
internal import GameAppKit

public struct Game2048BoardView: View {

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gameChrome) private var gameChrome

    @State private var viewModel: Game2048GameViewModel
    // #297 mirror: seeded boards skip the in-body ticker + stuck overlay so
    // the snapshot fixture survives NSHostingView capture.
    private let suppressTickerForSnapshot: Bool

    // M4 seams (nil at M3):
    // private let adProvider: (any AdProvider)?
    // private let adGate: AdGate?
    // private let onNewGame: (() -> Void)?

    // MARK: - Public inits

    /// Construct from an existing view model (previews, snapshot tests, resume).
    public init(
        viewModel: Game2048GameViewModel,
        suppressTickerForSnapshot: Bool = false
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.suppressTickerForSnapshot = suppressTickerForSnapshot
    }

    /// Convenience: construct a fresh session from seed + mode.
    public init(seed: UInt64 = 0, mode: GameMode = .practice) {
        self._viewModel = State(initialValue: Game2048GameViewModel(seed: seed, mode: mode))
        self.suppressTickerForSnapshot = false
    }

    // MARK: - Body

    public var body: some View {
        Group {
            if sizeClass == .regular {
                macLayout
            } else {
                compactLayout
            }
        }
        .padding(theme.spacing.medium)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Stuck overlay: covers the board with a "no moves" surface when stuck.
        // M4: replace with the shared CompletionScreen injection.
        .overlay {
            if viewModel.isTerminal, !suppressTickerForSnapshot {
                stuckOverlay
                    .ignoresSafeArea()
            }
        }
        // Save point: background → persist (M4: will call real store).
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel.persistCurrentState() }
            }
        }
        .onDisappear {
            Task { await viewModel.persistCurrentState() }
        }
        // Swipe gestures in all 4 directions.
        // Note: gestures are attached at the outer frame so the whole board
        // surface is swipe-sensitive, not just the grid cells.
        .gesture(swipeGesture)
        // Ticker: pull snapshot once per second while playing; push elapsed to chrome.
        // Uses .onAppear { Task { } } not .task per #361 (arm64 Release link bug).
        // The task is started once on appear and loops until cancellation —
        // but Swift structured concurrency doesn't allow cancellation here
        // via .onAppear. Instead we replicate the MS pattern with a @State task
        // that is cancelled on disappear via .onDisappear.
        .onAppear {
            startTickerIfNeeded()
        }
        .onDisappear {
            tickerTask?.cancel()
            tickerTask = nil
        }
    }

    // MARK: - Ticker state

    /// The running ticker task. Held in @State-adjacent storage via a class
    /// wrapper so it can be cancelled on disappear. SwiftUI @State is value-type
    /// so we use a private reference-type wrapper approach: hold the Task directly
    /// in an actor-isolated nonisolated(unsafe) stored property, which is safe
    /// here because all access is on @MainActor.
    @State private var tickerTask: Task<Void, Never>?

    private func startTickerIfNeeded() {
        guard !suppressTickerForSnapshot else { return }
        tickerTask?.cancel()
        tickerTask = Task { @MainActor in
            // Pull once immediately so first frame isn't stale.
            await viewModel.refresh()
            gameChrome?.updateElapsed(elapsedString)
            while !Task.isCancelled {
                if viewModel.status == .playing {
                    await viewModel.refresh()
                    gameChrome?.updateElapsed(elapsedString)
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private var elapsedString: String {
        let secs = viewModel.elapsedSeconds
        return String(format: "%d:%02d", secs / 60, secs % 60)
    }

    // MARK: - Swipe gesture

    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onEnded { value in
                let horizontal = value.translation.width
                let vertical = value.translation.height
                // Resolve to the dominant axis.
                if abs(horizontal) > abs(vertical) {
                    Task { await viewModel.slide(horizontal > 0 ? .right : .left) }
                } else {
                    Task { await viewModel.slide(vertical > 0 ? .down : .up) }
                }
            }
    }

    // MARK: - Layouts (mirrors MinesweeperBoardView compact/mac split)

    private var compactLayout: some View {
        VStack(spacing: 12) {
            statusBar
            boardGrid
        }
    }

    private var macLayout: some View {
        VStack(spacing: theme.spacing.medium) {
            HStack(alignment: .top, spacing: theme.spacing.large) {
                macBoardColumn
                controlRail
            }
        }
        .frame(maxWidth: Self.macOuterMaxWidth)
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, theme.spacing.medium)
    }

    private static let macOuterMaxWidth: CGFloat = 700
    private static let macBoardMaxSide: CGFloat = 500
    private static let macRailWidth: CGFloat = 220

    private var macBoardColumn: some View {
        boardGrid
            .frame(maxWidth: Self.macBoardMaxSide, maxHeight: Self.macBoardMaxSide)
            .frame(maxWidth: .infinity, alignment: .center)
    }

    private var controlRail: some View {
        VStack(spacing: theme.spacing.medium) {
            statusBar
            Spacer(minLength: 0)
        }
        .frame(width: Self.macRailWidth)
    }

    // MARK: - Status bar (mirrors MinesweeperBoardView statusBar)

    private var statusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Score")
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
                Text("\(viewModel.score)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(theme.text.primary.resolved)
            }
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                Text("Moves")
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
                Text("\(viewModel.moveCount)")
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(theme.text.primary.resolved)
            }
            Spacer()
            // SDD-003 OQ-001 pattern: suppress in-board clock when chrome shows it.
            if gameChrome == nil {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Time")
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                    Label(elapsedString, systemImage: "clock")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(theme.text.primary.resolved)
                }
            }
            pauseToggle
        }
        .font(.subheadline)
    }

    // MARK: - Pause toggle (mirrors MinesweeperBoardView pauseToggle)

    @ViewBuilder
    private var pauseToggle: some View {
        if viewModel.status == .playing || viewModel.isPaused {
            Button {
                Task {
                    if viewModel.isPaused {
                        await viewModel.resume()
                    } else {
                        await viewModel.pause()
                    }
                }
            } label: {
                if sizeClass == .regular {
                    Label(
                        viewModel.isPaused ? "Resume" : "Pause",
                        systemImage: viewModel.isPaused ? "play.fill" : "pause.fill"
                    )
                } else {
                    Image(systemName: viewModel.isPaused ? "play.fill" : "pause.fill")
                }
            }
            .accessibilityLabel(viewModel.isPaused ? "Resume" : "Pause")
            .accessibilityIdentifier("tiles2048.board.pauseToggle")
        }
    }

    // MARK: - Board grid

    private static let cellSpacing: CGFloat = 8

    private var boardGrid: some View {
        GeometryReader { geo in
            let size = Board.size
            let spacing = Self.cellSpacing
            let availW = geo.size.width - spacing * CGFloat(size - 1)
            let availH = geo.size.height - spacing * CGFloat(size - 1)
            let fitted = floor(min(availW / CGFloat(size), availH / CGFloat(size)))
            let cellSide = max(40, fitted)

            let content = gridStack(cellSide: cellSide, spacing: spacing)

            if fitted >= 40 {
                content
                    .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
            } else {
                ScrollView([.horizontal, .vertical]) { content }
                    .frame(width: geo.size.width, height: geo.size.height)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        // Pause cover: mirrors MinesweeperBoardView's PauseOverlayView pattern.
        .overlay {
            if viewModel.isPaused {
                PauseOverlayView(onResume: {
                    Task { await viewModel.resume() }
                })
            }
        }
    }

    private func gridStack(cellSide: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            ForEach(0..<Board.size, id: \.self) { row in
                HStack(spacing: spacing) {
                    ForEach(0..<Board.size, id: \.self) { col in
                        Game2048TileView(
                            value: viewModel.board[row, col],
                            side: cellSide
                        )
                        // Tile pop animation on value change.
                        .animation(.spring(response: 0.15, dampingFraction: 0.7), value: viewModel.board[row, col])
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(tileLabel(row: row, col: col))
                    }
                }
            }
        }
    }

    private func tileLabel(row: Int, col: Int) -> String {
        let location = "Row \(row + 1), Column \(col + 1)"
        if let value = viewModel.board[row, col] {
            return "\(location), \(value)"
        }
        return "\(location), empty"
    }

    // MARK: - Stuck overlay (M3 inline; M4 → shared CompletionScreen)
    //
    // M3 decision: the GameShellKit CompletionScreen is injection-API (M4
    // wires it). For M3 we show a simple full-cover card with the score and
    // a "Game Over" label so the board is usable / testable. M4 replaces this
    // with the shared completion overlay exactly as MS does.

    private var stuckOverlay: some View {
        ZStack {
            theme.surface.primary.resolved
                .opacity(0.92)
            VStack(spacing: 24) {
                Text("Game Over")
                    .font(.largeTitle.bold())
                    .foregroundStyle(theme.text.primary.resolved)
                Text("Score: \(viewModel.score)")
                    .font(.title2)
                    .foregroundStyle(theme.text.secondary.resolved)
                if viewModel.reachedTarget {
                    Label("2048 reached!", systemImage: "star.fill")
                        .foregroundStyle(theme.accent.primary.resolved)
                }
                // M4: replace with "New Game" → navigate to hub + "Share" CTAs.
                Text("Swipe to close and return.")
                    .font(.caption)
                    .foregroundStyle(theme.text.tertiary.resolved)
                    .multilineTextAlignment(.center)
            }
            .padding(32)
        }
    }
}

// MARK: - Preview

#Preview("Initial board") {
    Game2048BoardView(seed: 42, mode: .practice)
        .frame(minWidth: 360, minHeight: 520)
}
