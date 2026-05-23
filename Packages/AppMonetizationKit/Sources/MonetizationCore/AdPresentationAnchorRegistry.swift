public import Foundation

// MARK: - AdPresentationAnchorRegistry
//
// N4-followup (impl-notes 2026-05-23 §未決 #4): the resolver helpers in
// `AdPresentationAnchor+Resolve.swift` already accept `[UUID: UIWindow]` /
// `[UUID: NSWindow]` lookup tables, but the host had no canonical place to
// store them. This actor-based registry is that place: AdsAdMob (or any
// future adapter) registers a window under an `AdPresentationAnchor.id`
// when a scene appears and unregisters on scene tear-down.
//
// Cross-platform shape:
//   * The registry stores window references inside `WindowRef` — an
//     `@unchecked Sendable` weak box. The public surface stays
//     Foundation-only; AdsAdMob casts `WindowRef.unsafeAnyObject` to
//     `UIWindow` / `NSWindow` at the call site (the cast lives in the
//     UI-framework-aware adapter, not in MonetizationCore).
//   * Weak references: registered windows are held weakly so a scene
//     teardown that fails to call `unregister` cannot leak the window.
//     A follow-up resolve after deinit yields `nil`.

public actor AdPresentationAnchorRegistry {
    private var entries: [UUID: WindowRef] = [:]

    public init() {}

    /// Register a window object under an anchor's id. Re-registering the
    /// same id replaces the prior entry.
    public func register(_ anchor: AdPresentationAnchor, window: WindowRef) {
        entries[anchor.id] = window
    }

    /// Remove the entry for `anchor`. No-op if not registered.
    public func unregister(_ anchor: AdPresentationAnchor) {
        entries.removeValue(forKey: anchor.id)
    }

    /// Resolve an anchor to its currently-registered window-ref, or `nil`
    /// if the anchor was never registered OR the underlying window has been
    /// deallocated (weak-cleared). Callers cast `WindowRef.unsafeAnyObject`
    /// to the platform window type they expect.
    public func resolve(_ anchor: AdPresentationAnchor) -> WindowRef? {
        guard let ref = entries[anchor.id], ref.isAlive else { return nil }
        return ref
    }

    /// Number of currently-registered (still-alive) entries. Entries whose
    /// underlying window has been weak-cleared are excluded. Diagnostic
    /// helper for tests; production code should use `resolve(_:)`.
    public var liveEntryCount: Int {
        entries.values.reduce(0) { acc, ref in
            acc + (ref.isAlive ? 1 : 0)
        }
    }
}

// MARK: - WindowRef

/// `@unchecked Sendable` weak holder for a platform window (`UIWindow` /
/// `NSWindow`) tracked by `AdPresentationAnchorRegistry`. The unchecked
/// conformance is sound because the registry actor serialises every
/// access, and `unsafeAnyObject` is only read on actor-isolated paths or
/// immediately handed to the platform UI framework on its own main thread.
public final class WindowRef: @unchecked Sendable {
    private weak var window: AnyObject?

    public init(_ window: AnyObject) {
        self.window = window
    }

    /// Whether the underlying window is still alive (not weak-cleared).
    public var isAlive: Bool { window != nil }

    /// The wrapped window, or `nil` if it has been deallocated. Callers
    /// cast to `UIWindow` / `NSWindow` at the call site (the cast lives in
    /// the UI-framework-aware adapter, not in MonetizationCore).
    public var unsafeAnyObject: AnyObject? { window }
}
