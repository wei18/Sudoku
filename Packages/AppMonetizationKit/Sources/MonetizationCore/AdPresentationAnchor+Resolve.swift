public import Foundation

// MARK: - AdPresentationAnchor platform resolvers
//
// N3 (v2-audit-code-polish): the resolver helpers below need UIKit / AppKit
// types, which would otherwise force MonetizationCore's binary surface to
// carry public Apple-UI-framework symbols. Moving them into a dedicated
// extension file makes the dependency explicit at the file level and lets
// future portability work (e.g. a Linux-side MonetizationCore build) skip
// this single file via SwiftPM `exclude:` without touching the type itself.

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
    public func resolveUIWindow(in registry: [UUID: UIWindow]) -> UIWindow? {
        registry[id]
    }
}
#endif

#if canImport(AppKit)
public import AppKit

extension AdPresentationAnchor {
    /// Resolve to an `NSWindow` if the host application has registered one
    /// under this anchor's id. Returns `nil` if unmatched.
    public func resolveNSWindow(in registry: [UUID: NSWindow]) -> NSWindow? {
        registry[id]
    }
}
#endif
