public import Foundation

// MARK: - AdPresentationAnchor
//
// Cross-platform wrapper for "the window / scene the ad should attach to."
// The public surface of MonetizationCore intentionally does NOT import
// UIKit / AppKit, so this file is Foundation-only; the UIKit/AppKit
// resolver helpers live in `AdPresentationAnchor+Resolve.swift` (N3 from
// v2-audit-code-polish) and are pulled in via `canImport` from the
// AdsAdMob adapter — keeping the type itself UI-framework-free preserves
// MonetizationCore's portability (e.g. future Swift-on-Android).
//
// N1 (v2-audit-code-polish): `id` is now a concrete `UUID` rather than
// `AnyHashable`. All callers (host's `AdPresentationAnchorRegistry` and
// `ProtocolShapeTests`) already use UUID, and UUID is `Sendable` natively
// — we no longer need `@unchecked Sendable`.

public struct AdPresentationAnchor: Sendable, Hashable {
    public let id: UUID

    public init(id: UUID = UUID()) {
        self.id = id
    }
}
