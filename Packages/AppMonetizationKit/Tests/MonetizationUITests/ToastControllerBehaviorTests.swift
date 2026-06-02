// ToastControllerBehaviorTests — MS monetization wire Phase 1.
//
// Pure behavior tests for `ToastController` that don't need the SudokuUI
// snapshot harness. Full snapshot baselines (`ToastView-success-light`,
// `ToastView-failure-light`) stay in `SudokuUITests/ToastTests.swift`
// because they reuse the `SnapshotConfig` / `hostingView` helpers wired
// there. This file mirrors the non-snapshot half so MonetizationUI has
// its own zero-dep test suite.

import Foundation
import Testing

@testable import MonetizationUI

@MainActor
@Suite("ToastController — behavior")
struct ToastControllerBehaviorTests {

    @Test func show_setsCurrent() {
        let controller = ToastController()
        #expect(controller.current == nil)
        let toast = Toast(style: .success, message: "Ads removed")
        controller.show(toast)
        #expect(controller.current == toast)
    }

    @Test func dismiss_clearsCurrent() {
        let controller = ToastController()
        controller.show(Toast(style: .failure, message: "Boom", duration: .seconds(60)))
        #expect(controller.current != nil)
        controller.dismiss()
        #expect(controller.current == nil)
    }

    @Test func show_replacesPreviousToast() {
        let controller = ToastController()
        controller.show(Toast(style: .success, message: "first", duration: .seconds(60)))
        controller.show(Toast(style: .failure, message: "second", duration: .seconds(60)))
        #expect(controller.current?.message == "second")
        #expect(controller.current?.style == .failure)
    }

    @Test func autoDismiss_firesAfterDuration() async throws {
        let controller = ToastController()
        controller.show(Toast(style: .success, message: "pop", duration: .milliseconds(200)))
        #expect(controller.current != nil)
        let deadline = Date().addingTimeInterval(5.0)
        while controller.current != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.current == nil)
    }
}
