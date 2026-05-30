// PracticeHubView — difficulty picker + draw card + shimmer threshold.
//
// Per docs/designs/04-practice-hub.md. The "Draw new puzzle" CTA disables
// itself during draws; sub-100 ms draws skip indicators (no flash), >100 ms
// draws redact the puzzle-id hint (.redacted(reason: .placeholder)).

public import SwiftUI
internal import SudokuEngine

public struct PracticeHubView: View {
    @Bindable private var viewModel: PracticeHubViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: PracticeHubViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Difficulty")
                .font(.title3.weight(.semibold))
                .foregroundStyle(theme.text.primary.resolved)

            Picker("Difficulty", selection: difficultyBinding) {
                ForEach(Difficulty.allCases, id: \.self) { difficulty in
                    Text(LocalizedStringKey(difficulty.rawValue.capitalized))
                        .tag(difficulty)
                }
            }
            .pickerStyle(.segmented)
            // The "Difficulty" `Text` above is the section heading; the
            // Picker's own label would render again inline on macOS.
            .labelsHidden()
            // Tint the segmented control with the *selected* difficulty's
            // token so the active chip reads as that difficulty's color.
            // SwiftUI segmented Pickers don't expose per-segment tints,
            // so this is the closest we can get without a custom control.
            .tint(tint(for: viewModel.difficulty))
            .padding(8)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))

            drawCard

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.surface.background.resolved)
        .navigationTitle("Practice")
    }

    private var difficultyBinding: Binding<Difficulty> {
        Binding(
            get: { viewModel.difficulty },
            set: { viewModel.selectDifficulty($0) }
        )
    }

    @ViewBuilder
    private var drawCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ready to play")
                .font(.headline)
                .foregroundStyle(theme.text.primary.resolved)

            hintRow

            Button {
                // Single-tap: draw then push the board route. `playTapped`
                // guards on `.drawn`, so a `.failed` draw leaves the user on
                // the hub with the failure hint instead of pushing into a
                // half-loaded board (see `hintRow` `.failed` branch for the
                // visible affordance on draw failure). Issue #197: previously
                // only `drawPuzzle` was called, leaving the puzzle id displayed
                // inline with no affordance to navigate.
                Task {
                    await viewModel.drawPuzzle()
                    viewModel.playTapped()
                }
            } label: {
                Label("Draw new puzzle", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // CTA carries the selected difficulty's tint, keeping the
            // segmented Picker and the draw button visually linked.
            .tint(tint(for: viewModel.difficulty))
            .controlSize(.large)
            .disabled(isDrawing)
        }
        .padding(16)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var hintRow: some View {
        switch viewModel.loadingState {
        case .idle, .drawingQuiet:
            Text("\(viewModel.difficulty.rawValue.capitalized) · ready")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        case .drawingShimmer:
            Text("placeholder placeholder placeholder")
                .font(.caption)
                .redacted(reason: .placeholder)
                .accessibilityLabel("Loading")
                .accessibilityAddTraits(.updatesFrequently)
        case .drawn(let envelope):
            Text("\(viewModel.difficulty.rawValue.capitalized) · \(envelope.identity.puzzleId)")
                .font(.caption)
                .foregroundStyle(theme.text.secondary.resolved)
        case .failed(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(theme.status.error.resolved)
        }
    }

    /// Map a `Difficulty` to its `difficulty.*` token.
    private func tint(for difficulty: Difficulty) -> Color {
        switch difficulty {
        case .easy: return theme.difficulty.easy.resolved
        case .medium: return theme.difficulty.medium.resolved
        case .hard: return theme.difficulty.hard.resolved
        }
    }

    private var isDrawing: Bool {
        switch viewModel.loadingState {
        case .drawingQuiet, .drawingShimmer: return true
        default: return false
        }
    }
}
