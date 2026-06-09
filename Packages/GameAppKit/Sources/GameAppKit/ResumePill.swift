// ResumePill — shared "resume in-progress game" pill (#448 step 3).
//
// Moved out of `SudokuUI.RootView` so any game's Root can mount the same
// resume affordance over its Home content. Renders a `SavedGameSummary`
// (difficulty + elapsed) as a tappable card; the host supplies the tap
// action. Rendering is byte-identical to the former inline Sudoku version so
// existing snapshot baselines are unchanged.
//
// Uses `SavedGameSummary` from Persistence (GameAppKit already depends on it)
// and the `@Environment(\.theme)` from GameShellUI.

public import SwiftUI
public import Persistence
internal import GameShellUI

public struct ResumePill: View {
    let candidate: SavedGameSummary
    let onTap: () -> Void
    @Environment(\.theme) private var theme

    public init(candidate: SavedGameSummary, onTap: @escaping () -> Void) {
        self.candidate = candidate
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.accent.primary.resolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(candidate.difficulty.rawValue.capitalized)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(elapsedLabel)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(12)
            .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
    }

    private var elapsedLabel: String {
        let total = candidate.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
