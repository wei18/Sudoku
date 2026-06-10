// ResumePill — shared "resume in-progress game" pill (#448 step 3).
//
// Moved out of `SudokuUI.RootView` so any game's Root can mount the same
// resume affordance over its Home content. Renders a plain `title` /
// `subtitle` (the game-agnostic `ResumeCandidate` fields, #455) as a tappable
// card; the host supplies the tap action. Rendering is byte-identical to the
// former `SavedGameSummary`-typed version so existing snapshot baselines are
// unchanged. The `"Resume \(difficulty)"` + `%d:%02d` elapsed formatting now
// lives in each game's `fetchResume` mapping.
//
// Uses the `@Environment(\.theme)` from GameShellUI.

public import SwiftUI
internal import GameShellUI

public struct ResumePill: View {
    let title: String
    let subtitle: String
    let onTap: () -> Void
    @Environment(\.theme) private var theme

    public init(title: String, subtitle: String, onTap: @escaping () -> Void) {
        self.title = title
        self.subtitle = subtitle
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.accent.primary.resolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(subtitle)
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
}
