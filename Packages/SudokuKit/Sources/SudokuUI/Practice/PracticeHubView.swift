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
            .tint(theme.accent.primary.resolved)
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
                Task { await viewModel.drawPuzzle() }
            } label: {
                Label("Draw new puzzle", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accent.primary.resolved)
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

    private var isDrawing: Bool {
        switch viewModel.loadingState {
        case .drawingQuiet, .drawingShimmer: return true
        default: return false
        }
    }
}
