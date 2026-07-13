import Testing
@testable import GameShellUI

// MARK: - ModalOverlayActiveKey.reduce (#763)
//
// `NavigationStackHost` masks the macOS sidebar as soon as ANY pushed
// descendant reports an active overlay. `reduce` is the piece of that
// contract that guarantees "any one true wins" regardless of how many
// sibling subtrees set the preference or in what order SwiftUI folds them —
// pin it directly so a future edit (e.g. accidentally switching `||` to
// `&&`, or having the second value win outright) fails loudly here instead
// of only showing up as a flaky sidebar-masking bug.

@Suite("ModalOverlayActiveKey — reduce (#763)")
struct ModalOverlayPreferenceTests {

    @Test("defaultValue is false — no overlay means no masking by default")
    func defaultValueIsFalse() {
        #expect(ModalOverlayActiveKey.defaultValue == false)
    }

    @Test("reduce: false OR false stays false")
    func reduceFalseFalse() {
        var value = false
        ModalOverlayActiveKey.reduce(value: &value, nextValue: { false })
        #expect(value == false)
    }

    @Test("reduce: true OR false stays true (first sibling active)")
    func reduceTrueFalse() {
        var value = true
        ModalOverlayActiveKey.reduce(value: &value, nextValue: { false })
        #expect(value == true)
    }

    @Test("reduce: false OR true becomes true (later sibling active)")
    func reduceFalseTrue() {
        var value = false
        ModalOverlayActiveKey.reduce(value: &value, nextValue: { true })
        #expect(value == true)
    }

    @Test("reduce: true OR true stays true")
    func reduceTrueTrue() {
        var value = true
        ModalOverlayActiveKey.reduce(value: &value, nextValue: { true })
        #expect(value == true)
    }
}
