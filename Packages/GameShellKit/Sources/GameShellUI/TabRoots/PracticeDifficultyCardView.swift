// PracticeDifficultyCardView — PRACTICE's three difficulty cards (#1021
// Phase A/C, design.md §3.2). The thumbnail is a representative sample
// (`BoardPreview.densitySample`, see `BoardPreview+DensitySample.swift`),
// never the actual next puzzle — picking a real one here would move the
// game's own draw-timing forward and collide with each app's existing
// generation state machine (design.md §3.2 explicit rationale).
//
// #1021 Phase C layout correction: row shape (thumbnail leading, name/detail/
// pips trailing, checkmark on selection), matching `docs/designs/v3/
// prototype.html`'s `.bcard`/`.thumb`/`.meta`/`.cv` — NOT a 3-column grid.
// The thumbnail is pinned to a fixed HEIGHT only; `BoardPreviewView`'s own
// `.aspectRatio(_, contentMode: .fit)` then floats the width, so a wide
// board (MS's 16×30 Expert) renders wide instead of being squeezed into a
// square cell.

public import SwiftUI

public struct PracticeCardModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let pipLevel: Int
    public let detail: String
    public let preview: BoardPreview

    public init(id: String, title: String, pipLevel: Int, detail: String, preview: BoardPreview) {
        self.id = id
        self.title = title
        self.pipLevel = pipLevel
        self.detail = detail
        self.preview = preview
    }
}

public struct PracticeDifficultyCardView: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let model: PracticeCardModel
    private let isSelected: Bool
    private let action: () -> Void

    private static let selectionStrokeWidth: CGFloat = 2
    /// Thumbnail height only — width floats via `BoardPreviewView`'s own
    /// `.aspectRatio(fit)`, so a wide board renders wide (prototype `.thumb`
    /// is likewise a fixed box the Canvas fits into, not a forced square).
    private static let thumbnailHeight: CGFloat = 64

    public init(model: PracticeCardModel, isSelected: Bool, action: @escaping () -> Void) {
        self.model = model
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HubCard {
                HStack(spacing: contentGap) {
                    BoardPreviewView(preview: model.preview)
                        .frame(height: Self.thumbnailHeight)

                    VStack(alignment: .leading, spacing: contentGap) {
                        Text(model.title)
                            .font(.headline)
                            .foregroundStyle(theme.text.primary.resolved)
                        Text(model.detail)
                            .font(.subheadline)
                            .foregroundStyle(theme.text.secondary.resolved)
                        DifficultyPips(level: model.pipLevel)
                    }

                    Spacer(minLength: 0)

                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(theme.accent.primary.resolved)
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(isSelected ? theme.accent.primary.resolved : Color.clear, lineWidth: Self.selectionStrokeWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(title: model.title, detail: model.detail))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    public static func accessibilityLabel(title: String, detail: String) -> String {
        String(localized: "\(title), \(detail)", bundle: .main)
    }
}
