// AppTabTests — pins the 3-tab identity set (#1020, design.md §2.1–§2.2).
//
// `AppTab` is the single source of truth for BOTH the iPhone tab bar and the
// iPad/macOS sidebar (one `sidebarAdaptable` TabView serves all three), and its
// `rawValue` is the persistence key a host restores from. Both properties are
// worth pinning: a reordered `allCases` silently reorders the tab bar, and a
// renamed `rawValue` silently invalidates restored state.

import SwiftUI
import Testing
@testable import GameShellUI

@Suite("GameShellUI — AppTab")
struct AppTabTests {

    @Test("renders exactly three tabs, in Today → Practice → Progress order")
    func allCasesOrder() {
        #expect(AppTab.allCases == [.today, .practice, .progress])
    }

    /// `rawValue` is the wire format for `Codable` restoration — changing one
    /// drops a returning player back on Today.
    @Test("raw values are stable")
    func rawValuesAreStable() {
        #expect(AppTab.today.rawValue == "today")
        #expect(AppTab.practice.rawValue == "practice")
        #expect(AppTab.progress.rawValue == "progress")
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        for tab in AppTab.allCases {
            let data = try JSONEncoder().encode(tab)
            #expect(try JSONDecoder().decode(AppTab.self, from: data) == tab)
        }
    }

    /// Symbols carried over from the surfaces these tabs replace (`HomeMode`'s
    /// daily/practice glyphs and the #773/#844 Statistics glyph), so the icon a
    /// player already learned does not move.
    @Test("keeps the pre-#1020 glyphs")
    func systemImages() {
        #expect(AppTab.today.systemImage == "calendar")
        #expect(AppTab.practice.systemImage == "dice")
        #expect(AppTab.progress.systemImage == "chart.bar")
    }

    @Test("every tab carries a title and a symbol")
    func everyTabIsRenderable() {
        for tab in AppTab.allCases {
            #expect(!tab.systemImage.isEmpty)
            _ = tab.titleKey
        }
    }
}
