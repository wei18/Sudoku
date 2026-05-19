// SnapshotConfig — shared layouts, NSHostingView wrapper, and record mode.
//
// `swift test` on the host can only run macOS tests; we render SwiftUI
// Views through `NSHostingView` (size-pinned to one of the canonical
// `SnapshotLayouts`) and snapshot as an NSView. The dimensions mirror
// the canonical device sizes from design.md §How.5.8.
//
// Two appearance/layout concerns the host doesn't honor automatically:
//   1. `.preferredColorScheme(...)` on a SwiftUI subtree does NOT change
//      the `NSAppearance` of the surrounding `NSHostingView`, so dynamic
//      colors built with `NSColor(name:dynamicProvider:)` (which is how
//      `Color(light:dark:)` resolves on AppKit) keep the *system*
//      appearance. We mirror the requested scheme onto `host.appearance`.
//   2. `NSHostingView`'s default `sizingOptions` adapt the view's frame
//      to the SwiftUI subtree's preferred size, which can blow past the
//      device-sized box for views that declare `maxWidth: .infinity`.
//      We pin the SwiftUI subtree to the device frame with an explicit
//      `.frame(width:height:)` so the snapshot matches the requested box.
//
// macOS `horizontalSizeClass` is always treated as `.regular` by SwiftUI
// host views unless overridden, which forces iPhone-shaped snapshots into
// `NavigationSplitView` / two-column grids. The wrapper accepts a
// `sizeClass` so iPhone fixtures get `.compact` and Mac fixtures stay
// `.regular`.

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
///
/// - Parameters:
///   - view:        the SwiftUI subtree under test.
///   - size:        device-pixel box (in points) the snapshot should fill.
///   - colorScheme: applied via `.preferredColorScheme` AND mirrored onto
///                  `host.appearance` so AppKit dynamic colors resolve.
///   - locale:      injected via `.environment(\.locale, ...)` when supplied.
///   - sizeClass:   horizontal size class for the SwiftUI subtree. Defaults
///                  to `.compact` (iPhone). Mac fixtures should pass `.regular`.
@MainActor
func hostingView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact
) -> NSView {
    let wrapped = view
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .preferredColorScheme(colorScheme)
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: wrapped)
    // Disable the default `.standardBounds` so the SwiftUI subtree can
    // never grow the host past our requested device frame.
    host.sizingOptions = []
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    return host
}
