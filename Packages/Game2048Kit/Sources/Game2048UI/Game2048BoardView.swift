// Game2048BoardView — SwiftUI board renderer for a 2048 game session.
//
// Mirrors MinesweeperBoardView exactly in structure:
//   - @Environment(\.gameChrome): pushes elapsed to the modal top chrome.
//   - @Environment(\.horizontalSizeClass): compact (iPhone) / regular (Mac) layout.
//   - @Environment(\.scenePhase): background → save point.
//   - .task(id: ObjectIdentifier(viewModel)) not .onAppear — the ticker is a
//     long-lived loop that must cancel on disappear (structured cancellation);
//     the #361 arm64 Release link bug applies only to Root one-shot bootstraps.
//   - Ticker loop: one `while !Task.isCancelled { sleep }` owned task, keyed on
//     the VM's identity so Retry (VM swap) restarts it.
//   - Terminal state: stuck board shows `Game2048CompletionView` overlay (M4).
//   - Swipe gestures in all 4 directions calling viewModel.slide(_:).
//   - Tile animation via withAnimation on snap update.

// Board view + gesture wiring + completion overlay + pause cover.
// Extracting helpers for the sub-400 line count would increase indirection
// without simplification; file_length disable absent (currently under 400).

public import SwiftUI
public import MonetizationCore
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
    @State private var completionViewModel: Game2048CompletionViewModel?

    private let suppressTickerForSnapshot: Bool
    private let stuckOverlayForSnapshot: Bool

    // M4 seams (optional — nil when monetization not wired):
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    // MARK: - Public inits

    /// Construct from an existing view model (previews, snapshot tests, resume).
    public init(
        viewModel: Game2048GameViewModel,
        suppressTickerForSnapshot: Bool = false,
        stuckOverlayForSnapshot: Bool = false,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.suppressTickerForSnapshot = suppressTickerForSnapshot
        self.stuckOverlayForSnapshot = stuckOverlayForSnapshot
        self.adProvider = adProvider
        self.adGate = adGate
    }

    /// Convenience: construct a fresh session from seed + mode.
    public init(seed: UInt64 = 0, mode: GameMode = .practice) {
        self._viewModel = State(initialValue: Game2048GameViewModel(seed: seed, mode: mode))
        self.suppressTickerForSnapshot = false
        self.stuckOverlayForSnapshot = false
        self.adProvider = nil
        self.adGate = nil
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
        // M4: CompletionScreen overlay replaces the M3 inline stuckOverlay.
        .overlay {
            if let cvm = completionViewModel,
               !suppressTickerForSnapshot || stuckOverlayForSnapshot {
                Game2048CompletionView(
                    viewModel: cvm,
                    onClose: { completionViewModel = nil }
                )
                .ignoresSafeArea()
            }
        }
        // Save point: background → persist.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                Task { await viewModel.persistCurrentState() }
            }
        }
        .onDisappear {
            Task { await viewModel.persistCurrentState() }
        }
        // Watch for stuck to mount the completion overlay.
        .onChange(of: viewModel.isTerminal) { _, isNow in
            if isNow {
                completionViewModel = Game2048CompletionViewModel(
                    score: viewModel.score,
                    moveCount: viewModel.moveCount,
                    elapsedSeconds: viewModel.elapsedSeconds,
                    reachedTarget: viewModel.reachedTarget
                )
            }
        }
        // Swipe gestures.
        .gesture(swipeGesture)
        // Ticker: pull snapshot once per second while playing.
        .task(id: ObjectIdentifier(viewModel)) {
            guard !suppressTickerForSnapshot else { return }
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
        // Snapshot seam: pre-mount the completion overlay when the seeded
        // snapshot is stuck and stuckOverlayForSnapshot is true.
        .onAppear {
            if stuckOverlayForSnapshot, viewModel.isTerminal, completionViewModel == nil {
                completionViewModel = Game2048CompletionViewModel(
                    score: viewModel.score,
                    moveCount: viewModel.moveCount,
                    elapsedSeconds: viewModel.elapsedSeconds,
                    reachedTarget: viewModel.reachedTarget
                )
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
                if abs(horizontal) > abs(vertical) {
                    Task { await viewModel.slide(horizontal > 0 ? .right : .left) }
                } else {
                    Task { await viewModel.slide(vertical > 0 ? .down : .up) }
                }
            }
    }

    // MARK: - Layouts

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

    // MARK: - Status bar

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

    // MARK: - Pause toggle

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
}

// MARK: - Preview

#Preview("Initial board") {
    Game2048BoardView(seed: 42, mode: .practice)
        .frame(minWidth: 360, minHeight: 520)
}
