// SnapshotConfig — shared layouts, NSHostingView wrapper, and record mode.
//
// `swift test` on the host can only run macOS tests; we render SwiftUI
// Views through `NSHostingView` (size-pinned to one of the canonical
// `SnapshotLayouts`) and snapshot as an NSView. The dimensions mirror
// the canonical device sizes from design.md §How.5.8.

import AppKit
import Foundation
import SnapshotTesting
import SwiftUI

enum SnapshotLayouts {
    /// iPhone 16 / 15 canonical compact size class.
    static let iPhone = CGSize(width: 393, height: 852)
    /// Mac regular size class — matches the design preview frame
    /// (`#Preview` width 900 × height 600).
    static let mac = CGSize(width: 900, height: 600)
}

/// Default record mode. Set to `.missing` so first runs record baselines;
/// subsequent runs diff. Flip to `.all` locally to force re-record.
enum SnapshotMode {
    static let recordMode: SnapshotTestingConfiguration.Record = .missing
}

/// Wrap a SwiftUI View in an `NSHostingView` sized to `size` for snapshot.
@MainActor
func hostingView<V: SwiftUI.View>(_ view: V, size: CGSize) -> NSView {
    let host = NSHostingView(rootView: view)
    host.frame = CGRect(origin: .zero, size: size)
    host.layoutSubtreeIfNeeded()
    return host
}
