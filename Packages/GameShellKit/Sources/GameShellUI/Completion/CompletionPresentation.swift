// CompletionPresentation — where a `CompletionOverlayScaffold` is mounted
// (#1049).
//
// Three of the scaffold's four production paths cover a board or a loader,
// so the panel is an overlay. The Daily hub's review route is a tab-scoped
// push (design.md §4.4, D-3.3): in regular width it is a page, titled with
// its difficulty and day, with the column pinned under the title. Compact
// width keeps the overlay layout for every path.

public import Foundation
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
    /// Midnight UTC of the reviewed daily's day.
    public let day: Date

    public init(difficultyKey: String, day: Date) {
        self.difficultyKey = difficultyKey
        self.day = day
    }

    /// Formatted in UTC: `day` is a UTC day, so any other time zone could
    /// print a neighbouring date.
    static let dayFormat = Date.FormatStyle(timeZone: .gmt)
        .weekday(.abbreviated)
        .month(.abbreviated)
        .day()

    var text: Text {
        let difficulty = Text(LocalizedStringKey(difficultyKey), bundle: .main)
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
