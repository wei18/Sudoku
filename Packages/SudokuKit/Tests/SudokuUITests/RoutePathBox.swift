// RoutePathBox — test seam for asserting navigation through an injected
// `Binding<[AppRoute]>`.
//
// The three hub ViewModels (Home / Daily / Practice) drive navigation by
// appending to a `path` that routes through an *external* binding when one is
// injected (RootView / RouteFactory wiring, issue #197) and falls back to a
// local stub otherwise. Existing VM tests only exercise the local-stub branch;
// these interaction tests wire a real binding through this box so a regression
// that left the external-binding branch unwired (the "no-op taps on macOS
// detail-pane scope" failure mode RouteFactory.swift:32-34 warns about) would
// fail here.

import SwiftUI
@testable import SudokuUI

/// Mutable, `@MainActor`-isolated holder exposing a `Binding<[AppRoute]>` that
/// records every route the VM writes. Mirrors the role a host `NavigationStack`
/// path plays in production.
@MainActor
final class RoutePathBox {
    private(set) var routes: [AppRoute] = []

    var binding: Binding<[AppRoute]> {
        Binding(
            get: { self.routes },
            set: { self.routes = $0 }
        )
    }
}
