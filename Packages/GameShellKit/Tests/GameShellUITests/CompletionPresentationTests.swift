import Foundation
import SwiftUI
import Testing
@testable import GameShellUI

@Suite("CompletionPresentation — #1049 pushed review page")
struct CompletionPresentationTests {
    /// 2026-11-14 00:00 UTC, a Saturday.
    private let title = CompletionPageTitle(difficultyKey: "Easy", day: Date(timeIntervalSince1970: 1_794_614_400))

    @Test("only a pushed page in regular width gets the page layout")
    func pageLayoutGate() {
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: .regular) == title)
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: .compact) == nil)
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: nil) == nil)
        #expect(CompletionPresentation.overlay.pageTitle(in: .regular) == nil)
        #expect(CompletionPresentation.overlay.pageTitle(in: .compact) == nil)
    }

    @Test("the day prints as the UTC day, not the device's local day")
    func dayFormatsInUTC() {
        let format = CompletionPageTitle.dayFormat.locale(Locale(identifier: "en_US"))
        #expect(title.day.formatted(format) == "Sat, Nov 14")
        #expect(title.day.addingTimeInterval(86_399).formatted(format) == "Sat, Nov 14", "23:59:59 UTC is already Sunday east of UTC")
    }
}
