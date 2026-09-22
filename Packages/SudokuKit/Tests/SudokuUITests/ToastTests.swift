// ToastTests — v2.4.5.
//
// This file only holds `ToastView` snapshot baselines. `ToastController`
// behavior is pinned by AppMonetizationKit's `ToastControllerBehaviorTests`
// (#1087) — no need to duplicate it per app.

import SnapshotTesting
import SwiftUI
import Testing

import MonetizationUI
@testable import SudokuUI

@MainActor
@Suite("ToastView")
struct ToastTests {

    // MARK: - Snapshot baselines

    #if canImport(AppKit)
    /// MS monetization wire Phase 1: the moved `ToastView` is theme-agnostic
    /// (no `@Environment(\.theme)` read). To preserve the historical snapshot
    /// bytes, Sudoku tests pass `DefaultTheme().status.success/error.resolved`
    /// at the call site — exactly what the old env-driven path resolved to.
    private static let successTint: Color = DefaultTheme().status.success.resolved
    private static let failureTint: Color = DefaultTheme().status.error.resolved
    // #950: same "attention, not error" tint GameConfig now injects at the
    // GameRoot call site.
    private static let infoTint: Color = DefaultTheme().status.warning.resolved

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotSuccessLight() {
        let view = ToastView(
            toast: Toast(style: .success, message: "Ads removed"),
            successTint: Self.successTint,
            failureTint: Self.failureTint,
            infoTint: Self.infoTint
        )
        .frame(width: 320, height: 80)
        .padding()
        let host = hostingView(view, size: CGSize(width: 320, height: 120), colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ToastView-success-light")
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotFailureLight() {
        let view = ToastView(
            toast: Toast(style: .failure, message: "Purchase failed"),
            successTint: Self.successTint,
            failureTint: Self.failureTint,
            infoTint: Self.infoTint
        )
        .frame(width: 320, height: 80)
        .padding()
        let host = hostingView(view, size: CGSize(width: 320, height: 120), colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ToastView-failure-light")
        }
    }

    /// #950: "No purchases to restore" — the info-style toast added for the
    /// restore-with-nothing-restorable fix.
    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud)) func snapshotInfoLight() {
        let view = ToastView(
            toast: Toast(style: .info, message: "No purchases to restore"),
            successTint: Self.successTint,
            failureTint: Self.failureTint,
            infoTint: Self.infoTint
        )
        .frame(width: 320, height: 80)
        .padding()
        let host = hostingView(view, size: CGSize(width: 320, height: 120), colorScheme: .light)
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(of: host, as: .image, named: "ToastView-info-light")
        }
    }
    #endif
}
