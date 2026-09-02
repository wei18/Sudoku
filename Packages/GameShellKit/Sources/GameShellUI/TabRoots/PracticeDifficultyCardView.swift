// PracticeDifficultyCardView — PRACTICE's three difficulty cards (#1021
// Phase A, design.md §3.2). The thumbnail is a representative sample
// (`BoardPreview.densitySample`, see `BoardPreview+DensitySample.swift`),
// never the actual next puzzle — picking a real one here would move the
// game's own draw-timing forward and collide with each app's existing
// generation state machine (design.md §3.2 explicit rationale).

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

    public init(model: PracticeCardModel, isSelected: Bool, action: @escaping () -> Void) {
        self.model = model
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HubCard {
                VStack(alignment: .leading, spacing: contentGap) {
                    BoardPreviewView(preview: model.preview)
                    Text(model.title)
                        .font(.headline)
                        .foregroundStyle(theme.text.primary.resolved)
                    DifficultyPips(level: model.pipLevel)
                    Text(model.detail)
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
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
