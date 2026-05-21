// MARK: - AdPresentationAnchor
//
// Cross-platform wrapper for "the window / scene the ad should attach to."
// The public surface intentionally does NOT import UIKit / AppKit so this
// type can travel through MonetizationCore freely.
//
// Internally, callers in `AdsAdMob` resolve the opaque `id` back to a host
// `UIWindow` / `NSWindow` via the platform-specific extensions below.
//
// Sendability note: `AnyHashable` is not itself `Sendable` in the stdlib.
// We use `@unchecked Sendable` with the documented invariant that callers
// pass only Sendable-compatible hashable values (UUIDs, window identifiers,
// scene session IDs). Construction is the only place this invariant is
// established; once boxed, the value is treated as immutable.

public struct AdPresentationAnchor: @unchecked Sendable {
    public let id: AnyHashable

    public init(id: AnyHashable) {
        self.id = id
    }
}

// MARK: - Platform lookup (host-side extensions)
//
// Resolution from `AnyHashable` back to a concrete window happens in the
// adapter target (AdsAdMob) where UIKit / AppKit imports are acceptable.
// We expose the type-level fences here so future platform code can extend
// `AdPresentationAnchor` without re-declaring the conditional import dance.

#if canImport(UIKit)
public import UIKit

extension AdPresentationAnchor {
    /// Resolve to a `UIWindow` if the host application has registered one
    /// under this anchor's id. Returns `nil` if unmatched.
    ///
    /// The lookup table itself lives in the AdsAdMob adapter (where the
    /// UIKit import is already established for SDK calls). This extension
    /// exists so type-level integration compiles cross-target; AdsAdMob
    /// will provide the registry in v2.2.
    public func resolveUIWindow(in registry: [AnyHashable: UIWindow]) -> UIWindow? {
        registry[id]
    }
}
#endif

#if canImport(AppKit)
public import AppKit

extension AdPresentationAnchor {
    /// Resolve to an `NSWindow` if the host application has registered one
    /// under this anchor's id. Returns `nil` if unmatched.
    public func resolveNSWindow(in registry: [AnyHashable: NSWindow]) -> NSWindow? {
        registry[id]
    }
}
#endif
