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
// #1021 Phase B (Leader adjudication, prototype parity): the prototype's
// daily cards are `.bcard` ROWS, not columns — thumbnail leading (fixed
// height, width follows the board's own aspect ratio so a wide MS 16×30
// board reads wide, not squeezed into a square), title/status/pips trailing,
// completed → a trailing checkmark. `PracticeDifficultyCardView` converts to
// the same row shape in a concurrent phase — kept visually aligned: same
// thumbnail height, same title/detail typography, same pips placement.
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

    /// Fixed row height for the leading thumbnail — matches
    /// `PracticeDifficultyCardView`'s row so both card families read as one
    /// visual family (Leader adjudication above).
    private static let thumbnailHeight: CGFloat = 64

    public var body: some View {
        // #1021 CR2 MINOR: only apply `.accessibilityIdentifier` when the
        // model actually carries one — an empty-string id (the old `?? ""`
        // fallback) is still a REAL identifier to XCUITest/AX-inspector
        // queries, so an unset card could accidentally match a `""` lookup
        // instead of genuinely having none.
        if let id = model.accessibilityIdentifier {
            cardBody.accessibilityIdentifier(id)
        } else {
            cardBody
        }
    }

    private var cardBody: some View {
        HubCard {
            HStack(alignment: .center, spacing: contentGap) {
                thumbnail
                VStack(alignment: .leading, spacing: contentGap) {
                    Text(model.title)
                        .font(.headline)
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(model.statusText)
                        .font(.subheadline)
                        .foregroundStyle(theme.text.secondary.resolved)
                    DifficultyPips(level: model.pipLevel)
                }
                Spacer(minLength: 0)
                if model.isCompleted {
                    // Color is not the sole channel for "completed" — the
                    // symbol shape carries the signal too, `statusText`
                    // carries it a third time in words.
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(theme.status.success.resolved)
                        .font(.title3)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DailyCardView.accessibilityLabel(title: model.title, statusText: model.statusText))
        .accessibilityAddTraits(.isButton)
    }

    /// Width follows the board's own `columns/rows` aspect ratio at a fixed
    /// height — a wide Minesweeper Expert board (16×30) renders wide, not
    /// squeezed into a square (Leader adjudication above). Falls back to a
    /// 9×9 (square) ratio for a `nil` preview (skeleton with no prior shape).
    private var thumbnailWidth: CGFloat {
        let columns = model.preview?.columns ?? 9
        let rows = model.preview?.rows ?? 9
        guard rows > 0 else { return Self.thumbnailHeight }
        return Self.thumbnailHeight * CGFloat(columns) / CGFloat(rows)
    }

    @ViewBuilder
    private var thumbnail: some View {
        Group {
            if !model.isSkeleton, let preview = model.preview {
                BoardPreviewView(preview: preview)
            } else {
                BoardPreviewView.skeleton(columns: model.preview?.columns ?? 9, rows: model.preview?.rows ?? 9)
            }
        }
        .frame(width: thumbnailWidth, height: Self.thumbnailHeight)
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

    // #1021 CR2 MINOR: this interpolated `"%@, %@"` key is INTENTIONALLY
    // shared with `PracticeDifficultyCardView.accessibilityLabel(title:detail:)`
    // — the spoken result is identical, and the xcstrings catalog can't
    // attach two distinct translator comments to one key. See that func's
    // doc for the reciprocal note.
    public static func accessibilityLabel(title: String, statusText: String) -> String {
        String(localized: "\(title), \(statusText)", bundle: .main)
    }
}
