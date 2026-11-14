import Foundation
import SwiftUI
import Testing
@testable import GameShellUI

@Suite("CompletionPresentation — #1049 pushed review page")
struct CompletionPresentationTests {
    private let title = CompletionPageTitle(difficultyKey: "Easy", utcDay: "2026-11-14")

    @Test("only a pushed page in regular width gets the page layout")
    func pageLayoutGate() {
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: .regular) == title)
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: .compact) == nil)
        #expect(CompletionPresentation.pushedPage(title).pageTitle(in: nil) == nil)
        #expect(CompletionPresentation.overlay.pageTitle(in: .regular) == nil)
        #expect(CompletionPresentation.overlay.pageTitle(in: .compact) == nil)
    }

    @Test("a UTC day parses to midnight UTC")
    func dayParsesAsUTCMidnight() throws {
        let day = try #require(title.day)
        #expect(day == Date(timeIntervalSince1970: 1_794_614_400))
    }

    @Test("malformed days degrade to no date", arguments: ["", "2026-11", "2026-11-1", "2026-13-01", "2026-02-30", "26-11-14", "abcd-ef-gh"])
    func malformedDayIsNil(utcDay: String) {
        #expect(CompletionPageTitle(difficultyKey: "Easy", utcDay: utcDay).day == nil)
    }

    @Test("the day prints as the UTC day, not the device's local day")
    func dayFormatsInUTC() throws {
        let day = try #require(title.day)
        let format = CompletionPageTitle.dayFormat.locale(Locale(identifier: "en_US"))
        #expect(day.formatted(format) == "Sat, Nov 14")
        #expect(day.addingTimeInterval(86_399).formatted(format) == "Sat, Nov 14", "23:59:59 UTC is already Sunday east of UTC")
    }
}
