// DailyCardView — TODAY's three-puzzle card (#1021 Phase A, design.md §3.1).
//
// The thumbnail is `.accessibilityHidden` (`BoardPreviewView`) — `statusText`
// is the ONLY progress channel VoiceOver gets, so the whole card collapses to
// ONE combined a11y element whose label is "{title}, {statusText}" (design.md
// §3.1 official-quote callout: "縮圖不得是進度的唯一通道").
//
// #1021 Phase B: split into `DailyCardContent` (all the visuals + combined
// a11y, no `Button`) + `DailyCardView` (`Button { DailyCardContent }`) per
// Phase A's own flagged integration note below — `DailyHubShellView.cardList`
// already wraps its `card:` builder output in its own
// `Button { onItemTap }`, so a caller wiring this into the shell uses
// `DailyCardContent` directly inside that builder instead of double-nesting
// two buttons. `DailyCardView` stays as a standalone, directly-tappable card
// for any other call site (previews, non-shell hosts).
//
// ORIGINAL Phase A NOTE (kept for history): that shell already wraps its
// `card:` builder output in its own `Button { onItemTap }`
// (`DailyHubShellView.swift` `cardList`). This view is ALSO a `Button` (per
// this phase's dispatch spec, `DailyCardView(model:action:)`) so it is usable
// standalone. Nesting it inside the shell's per-item `Button` would nest two
// buttons — pass a no-op `action` (or extract a content-only variant) at the
// call site instead of relying on both firing. Flagged, not resolved here:
// Phase A does not touch `DailyHubShellView` (forbidden list).

public import SwiftUI

public struct DailyCardModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let pipLevel: Int
    public let statusText: String
    public let preview: BoardPreview?
    public let isSkeleton: Bool
    public let isCompleted: Bool
    public let accessibilityIdentifier: String?

    public init(
        id: String,
        title: String,
        pipLevel: Int,
        statusText: String,
        preview: BoardPreview?,
        isSkeleton: Bool,
        isCompleted: Bool,
        accessibilityIdentifier: String? = nil
    ) {
        self.id = id
        self.title = title
        self.pipLevel = pipLevel
        self.statusText = statusText
        self.preview = preview
        self.isSkeleton = isSkeleton
        self.isCompleted = isCompleted
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// Content-only rendering of a `DailyCardModel` — no `Button` wrapper. Use
/// this directly inside a host that already supplies its own tap handling
/// (e.g. `DailyHubShellView.cardList`'s per-item `Button`); use
/// `DailyCardView` below for a standalone, directly-tappable card.
public struct DailyCardContent: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let model: DailyCardModel

    public init(model: DailyCardModel) {
        self.model = model
    }

    public var body: some View {
        HubCard {
            VStack(alignment: .leading, spacing: contentGap) {
                thumbnail
                Text(model.title)
                    .font(.headline)
                    .foregroundStyle(theme.text.primary.resolved)
                DifficultyPips(level: model.pipLevel)
                statusRow
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DailyCardView.accessibilityLabel(title: model.title, statusText: model.statusText))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(model.accessibilityIdentifier ?? "")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if !model.isSkeleton, let preview = model.preview {
            BoardPreviewView(preview: preview)
        } else {
            BoardPreviewView.skeleton(columns: model.preview?.columns ?? 9, rows: model.preview?.rows ?? 9)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 4) {
            Text(model.statusText)
                .font(.subheadline)
                .foregroundStyle(theme.text.secondary.resolved)
            if model.isCompleted {
                // Color is not the sole channel for "completed" — the symbol
                // shape carries the signal too, `statusText` carries it a
                // third time in words.
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(theme.status.success.resolved)
                    .font(.caption)
            }
        }
    }
}

public struct DailyCardView: View {
    private let model: DailyCardModel
    private let action: () -> Void

    public init(model: DailyCardModel, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            DailyCardContent(model: model)
        }
        .buttonStyle(.plain)
    }

    public static func accessibilityLabel(title: String, statusText: String) -> String {
        String(localized: "\(title), \(statusText)", bundle: .main)
    }
}
