// UITestLaunchArgTests — #510 deep-link argument parsing contract.
//
// The whole `UITestLaunchArg` namespace is `#if DEBUG`, so this suite is too.

#if DEBUG

import Testing
@testable import GameAppKit

@Suite("UITestLaunchArg.routeValue (#510)")
struct UITestLaunchArgTests {

    @Test func parsesTheValueAfterTheFlag() {
        #expect(
            UITestLaunchArg.routeValue(in: ["App", "-uitest-route", "settings"]) == "settings"
        )
    }

    @Test func nilWhenFlagAbsent() {
        #expect(UITestLaunchArg.routeValue(in: ["App", "-uitest-near-win"]) == nil)
    }

    @Test func nilWhenFlagHasNoTrailingValue() {
        #expect(UITestLaunchArg.routeValue(in: ["App", "-uitest-route"]) == nil)
    }

    @Test func picksTheFirstFlagOccurrence() {
        #expect(
            UITestLaunchArg.routeValue(
                in: ["-uitest-route", "daily", "-uitest-route", "settings"]
            ) == "daily"
        )
    }
}

@Suite("UITestLaunchArg.puzzleFaultValue (#935)")
struct UITestLaunchArgPuzzleFaultTests {

    @Test func parsesTheValueAfterTheFlag() {
        #expect(
            UITestLaunchArg.puzzleFaultValue(
                in: ["App", "-uitest-puzzle-fault", "dailyExhausted"]
            ) == "dailyExhausted"
        )
    }

    @Test func nilWhenFlagAbsent() {
        #expect(UITestLaunchArg.puzzleFaultValue(in: ["App", "-uitest-near-win"]) == nil)
    }

    @Test func nilWhenFlagHasNoTrailingValue() {
        #expect(UITestLaunchArg.puzzleFaultValue(in: ["App", "-uitest-puzzle-fault"]) == nil)
    }

    @Test func picksTheFirstFlagOccurrence() {
        #expect(
            UITestLaunchArg.puzzleFaultValue(
                in: ["-uitest-puzzle-fault", "practiceFail", "-uitest-puzzle-fault", "dailyFail"]
            ) == "practiceFail"
        )
    }
}

#endif
