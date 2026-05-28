// ToastTests — v2.4.5.
//
// Behavior:
//   - `ToastController.show(_:)` exposes the toast via `current`.
//   - `dismiss()` clears immediately.
//   - Auto-dismiss fires after `Toast.duration`.
//   - `ToastView` renders success + failure variants (snapshot baselines).

import Foundation
import SnapshotTesting
import SwiftUI
import Testing

@testable import SudokuUI

@MainActor
@Suite("ToastController + ToastView")
struct ToastTests {

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
        // Poll for auto-dismiss instead of one-shot wait. Single wall-clock
        // sleep raced under parallel test load (XCC + local full-suite run);
        // duration-then-poll is deterministic — we just need the dismiss
        // Task to fire eventually, not at exactly t=duration.
        controller.show(Toast(style: .success, message: "pop", duration: .milliseconds(200)))
        #expect(controller.current != nil)
        let deadline = Date().addingTimeInterval(5.0)
        while controller.current != nil, Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(controller.current == nil)
    }

    // MARK: - Snapshot baselines

    #if canImport(AppKit)
    @Test func snapshotSuccessLight() {
        let view = ToastView(toast: Toast(style: .success, message: "Ads removed"))
            .frame(width: 320, height: 80)
            .padding()
        let host = hostingView(view, size: CGSize(width: 320, height: 120), colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ToastView-success-light")
        }
    }

    @Test func snapshotFailureLight() {
        let view = ToastView(toast: Toast(style: .failure, message: "Purchase failed"))
            .frame(width: 320, height: 80)
            .padding()
        let host = hostingView(view, size: CGSize(width: 320, height: 120), colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ToastView-failure-light")
        }
    }
    #endif
}
