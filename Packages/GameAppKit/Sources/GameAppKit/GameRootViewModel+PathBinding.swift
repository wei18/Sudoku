// GameRootViewModel+PathBinding — the #1042 per-tab path Binding factory.
//
// Split out of `GameRootViewModel.swift` to keep that file under SwiftLint's
// 400-line ceiling (mirrors the `MakeGameApp+*.swift` split pattern already
// used in this target).

public import SwiftUI
public import GameShellUI

extension GameRootViewModel {

    /// The ONE place a per-tab path `Binding` is built (#1042). `GameRoot` and
    /// both apps' `Live+TabRoots.swift` all consume this factory instead of
    /// each constructing their own `Binding(get:set:)` — before #1042 the
    /// two per-app copies called `setPath(_:for:)` with no `persistJoin`,
    /// silently bypassing the #823 race guard for hub-originated writes
    /// (Practice/Daily hub navigation), while only `GameRoot`'s own binding
    /// threaded it through.
    ///
    /// `setPath(_:for:persistJoin:)` stays `public` — tests and
    /// `UITestRouteModifier` still call it directly.
    public func pathBinding(for tab: AppTab) -> Binding<[Route]> {
        Binding(
            get: { self.path(for: tab) },
            set: { newPath in self.setPath(newPath, for: tab, persistJoin: self.persistJoin) }
        )
    }
}
