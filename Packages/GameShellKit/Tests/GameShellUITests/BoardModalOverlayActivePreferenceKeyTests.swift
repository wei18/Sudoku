// BoardModalOverlayActivePreferenceKeyTests — pins the #763 reduce contract.
//
// `RootShellView` masks + disables the macOS sidebar while ANY board-mounted
// Pause/Completion overlay is up. Multiple preference-emitting views can
// coexist in the tree during a transition (e.g. the outgoing and incoming
// destination briefly overlap), so `reduce` must be a logical OR — one `true`
// anywhere in the subtree wins, never gets overwritten back to `false` by a
// sibling that happens to report `false`.

import Testing
@testable import GameShellUI

@Suite("GameShellUI — BoardModalOverlayActivePreferenceKey")
struct BoardModalOverlayActivePreferenceKeyTests {
    @Test("defaultValue is false")
    func defaultValueIsFalse() {
        #expect(BoardModalOverlayActivePreferenceKey.defaultValue == false)
    }

    @Test("reduce: true OR false = true")
    func reduceTrueOrFalse() {
        var value = true
        BoardModalOverlayActivePreferenceKey.reduce(value: &value) { false }
        #expect(value == true)
    }

    @Test("reduce: false OR true = true")
    func reduceFalseOrTrue() {
        var value = false
        BoardModalOverlayActivePreferenceKey.reduce(value: &value) { true }
        #expect(value == true)
    }

    @Test("reduce: false OR false = false")
    func reduceFalseOrFalse() {
        var value = false
        BoardModalOverlayActivePreferenceKey.reduce(value: &value) { false }
        #expect(value == false)
    }

    @Test("reduce: true OR true = true")
    func reduceTrueOrTrue() {
        var value = true
        BoardModalOverlayActivePreferenceKey.reduce(value: &value) { true }
        #expect(value == true)
    }
}
