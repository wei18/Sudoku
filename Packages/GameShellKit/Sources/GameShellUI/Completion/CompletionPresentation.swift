// CompletionPresentation — where a `CompletionOverlayScaffold` is mounted
// (#1049).
//
// Four production paths share the scaffold (design.md §3.5). Three of them
// cover a board or a loader, so the panel is an overlay. The fourth, the
// Daily hub's pushed review route, is a tab-scoped detail push (§4.4,
// D-3.3). In regular width (iPad, Mac) the overlay's vertically centred
// 480 pt card read like a modal floating in an empty page, and nothing said
// which day or difficulty was on screen. The owner ruled option B on #1049:
// in regular width the pushed review becomes a page, titled with its
// difficulty and day, with the column pinned to the top. Compact width
// (iPhone) keeps the overlay layout, so `.pushedPage` changes nothing there.

import SwiftUI

public enum CompletionPresentation: Sendable, Equatable {
    /// Board overlay, `.completedRedirect` loader state, MS guard state.
    case overlay
    /// The Daily hub's pushed review route.
    case pushedPage(CompletionPageTitle)

    /// The page title to show, or `nil` when the overlay layout applies.
    /// macOS reports `.regular` for every hosted view, so the Mac detail
    /// column takes the page layout too.
    func pageTitle(in sizeClass: UserInterfaceSizeClass?) -> CompletionPageTitle? {
        guard case .pushedPage(let title) = self, sizeClass == .regular else { return nil }
        return title
    }
}

/// "Easy · Sat, Nov 14": an existing per-app difficulty catalog key plus
/// the review's UTC day.
public struct CompletionPageTitle: Sendable, Equatable {
    /// A key already in the host app's catalog ("Easy", "Beginner", …).
    public let difficultyKey: String
    /// `"YYYY-MM-DD"`, the `UTCDay.string(from:)` form both games key
    /// their dailies by.
    public let utcDay: String

    public init(difficultyKey: String, utcDay: String) {
        self.difficultyKey = difficultyKey
        self.utcDay = utcDay
    }

    /// Formatted in UTC: the day key is a UTC day, so a local time zone
    /// west of UTC would otherwise print the previous day.
    static let dayFormat = Date.FormatStyle(timeZone: .gmt)
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()

    /// Midnight UTC of `utcDay`, or `nil` when it is not a valid
    /// `"YYYY-MM-DD"` day.
    var day: Date? {
        let parts = utcDay.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3,
              parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let dayOfMonth = Int(parts[2])
        else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        let components = DateComponents(year: year, month: month, day: dayOfMonth)
        guard components.isValidDate(in: calendar) else { return nil }
        return calendar.date(from: components)
    }

    /// A malformed day degrades to the difficulty alone rather than
    /// printing a wrong date.
    var text: Text {
        let difficulty = Text(LocalizedStringKey(difficultyKey), bundle: .main)
        guard let day else { return difficulty }
        return Text("\(difficulty) · \(Text(day, format: Self.dayFormat))", bundle: .main)
    }
}

extension View {
    func completionPageTitle(_ title: CompletionPageTitle) -> some View {
        #if os(iOS)
        navigationTitle(title.text)
            .navigationBarTitleDisplayMode(.inline)
        #else
        navigationTitle(title.text)
        #endif
    }
}
