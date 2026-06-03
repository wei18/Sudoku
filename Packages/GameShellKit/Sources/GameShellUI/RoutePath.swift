// RoutePath — generic navigation-path store shared by hub ViewModels.
//
// The three Sudoku hub VMs (Home / Daily / Practice) — and any future game's
// hubs — drive navigation by appending to a `path` that routes through an
// *external* `Binding<[Route]>` when one is injected (RootView / RouteFactory
// wiring, issue #197) and falls back to a local stub array otherwise. That
// `localPath + externalPath + computed-path` idiom was hand-rolled identically
// in each VM; this lifts it into one generic-over-`Route` helper (issue #240).
//
// §設計決定: value-type struct, not class / property-wrapper / base-class.
//   Hosts are `@MainActor @Observable` classes. Stored as a *non*-
//   `@ObservationIgnored` `var` on the host, a struct's value semantics make
//   "mutate localPath" == "set the property", so `@Observable` keeps tracking
//   the local-stub branch for free. The injected `Binding` rides inside as a
//   plain stored value (its target is observed at its own site). A reference
//   type would lose the free observation; a property wrapper fights the
//   `@Observable` macro; a base class / protocol-with-default couldn't actually
//   remove the duplicated stored declarations. See the #240 impl-notes.
//
// Not `Sendable`: `Binding` is not `Sendable`. The struct is only ever
// constructed + mutated on the `@MainActor` host VMs, so it inherits their
// isolation and needs no `Sendable` conformance — matching how the VMs already
// hold a non-Sendable `Binding` today.

public import SwiftUI

/// Owns a navigation path that transparently routes through an injected
/// `Binding<[Route]>` when present, or a local fallback array otherwise.
///
/// Hold this as a (non-`@ObservationIgnored`) stored property on an
/// `@Observable` ViewModel and forward the VM's public `path` to
/// `effectivePath`; observation of the local-stub branch is preserved by the
/// struct's value semantics.
public struct RoutePath<Route> {
    /// Private fallback storage used only when no external binding is supplied
    /// (previews / unit tests).
    private var localPath: [Route]

    /// External navigation path hoisted by the host (RootView / RouteFactory).
    /// When present, all reads/writes go through it instead of `localPath`.
    private let externalPath: Binding<[Route]>?

    /// - Parameter externalPath: optional binding to the host
    ///   `NavigationStack`'s path. `nil` falls back to a local stub array so
    ///   tests / previews work without wiring a binding.
    public init(_ externalPath: Binding<[Route]>? = nil) {
        self.externalPath = externalPath
        self.localPath = []
    }

    /// Single effective view of the navigation path. Routes to the external
    /// binding when one was injected; otherwise the local stub array.
    public var effectivePath: [Route] {
        get { externalPath?.wrappedValue ?? localPath }
        set {
            if let externalPath {
                externalPath.wrappedValue = newValue
            } else {
                localPath = newValue
            }
        }
    }

    /// Convenience push that appends `route` to the effective path.
    public mutating func append(_ route: Route) {
        effectivePath.append(route)
    }
}
