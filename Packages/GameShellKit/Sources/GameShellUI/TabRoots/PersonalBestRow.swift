// PersonalBestRow — PROGRESS's per-difficulty personal-best row (#1021
// Phase A, design.md §3.3: "Personal bests 陳列: 每難度一列,最佳時間為主角
// (.title2),完成數與平均降為附註").

public import SwiftUI

public struct PersonalBestModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let title: String
    public let pipLevel: Int
    public let bestTimeText: String?
    public let footnote: String

    public init(id: String, title: String, pipLevel: Int, bestTimeText: String?, footnote: String) {
        self.id = id
        self.title = title
        self.pipLevel = pipLevel
        self.bestTimeText = bestTimeText
        self.footnote = footnote
    }
}

public struct PersonalBestRow: View {
    @Environment(\.theme) private var theme
    @ScaledSpacing(.small) private var contentGap

    private let model: PersonalBestModel

    public init(model: PersonalBestModel) {
        self.model = model
    }

    public var body: some View {
        HubCard {
            HStack(alignment: .center, spacing: contentGap) {
                VStack(alignment: .leading, spacing: contentGap) {
                    HStack(spacing: contentGap) {
                        Text(model.title)
                            .font(.headline)
                            .foregroundStyle(theme.text.primary.resolved)
                        DifficultyPips(level: model.pipLevel)
                    }
                    Text(model.footnote)
                        .font(.footnote)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
                Spacer(minLength: contentGap)
                // The best time is the hero: `.title2`, trailing, hero
                // typography per design.md §3.3.
                Text(model.bestTimeText ?? "—")
                    .font(.title2.monospacedDigit())
                    .foregroundStyle(theme.text.primary.resolved)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Self.accessibilityLabel(title: model.title, bestTimeText: model.bestTimeText, footnote: model.footnote))
    }

    public static func accessibilityLabel(title: String, bestTimeText: String?, footnote: String) -> String {
        let best = bestTimeText ?? String(localized: "none", bundle: .main)
        return String(localized: "\(title), best \(best), \(footnote)", bundle: .main)
    }
}
