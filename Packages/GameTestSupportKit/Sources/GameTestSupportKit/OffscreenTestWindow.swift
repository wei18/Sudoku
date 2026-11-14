// OffscreenTestWindow — the one shared factory for `NSWindow`s that tests host
// SwiftUI/AppKit content in (#1103). Three hand-rolled copies existed; one of
// them left `isReleasedWhenClosed` at its default and crashed the test helper.

#if canImport(AppKit)
public import AppKit

/// Creates an `NSWindow` for test-only hosting. Callers assign
/// `contentView` / `contentViewController` themselves and `close()` the window
/// when done.
///
/// Two rules every test window must follow, which is why this is the only place
/// that constructs one:
///
/// 1. `isReleasedWhenClosed = false`. Under ARC a `close()` on a
///    release-when-closed window over-releases it: SIGSEGV in `objc_release` at
///    the next main-queue autorelease-pool pop (#1103).
/// 2. The window is never ordered front or made key. The machine is shared, and
///    a window taking focus corrupts other sessions' simulator and UI runs.
///    Callers that need pixels capture through a synchronous draw into a bitmap
///    context (`displayIgnoringOpacity(_:in:)`) instead.
///
/// - Parameters:
///   - size: content size in points; the content rect's origin is zero.
///   - styleMask: defaults to borderless.
///   - appearance: applied only when non-nil.
@MainActor
public func makeOffscreenTestWindow(
    size: CGSize,
    styleMask: NSWindow.StyleMask = [.borderless],
    appearance: NSAppearance? = nil
) -> NSWindow {
    let window = NSWindow(
        contentRect: CGRect(origin: .zero, size: size),
        styleMask: styleMask,
        backing: .buffered,
        defer: false
    )
    window.isReleasedWhenClosed = false
    if let appearance {
        window.appearance = appearance
    }
    return window
}
#endif
