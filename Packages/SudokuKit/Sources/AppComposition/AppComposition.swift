// AppComposition — DI composition root (design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog production wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// `composition.rootViewModel` and hands it to `RootView`.

internal import Foundation
public import SudokuUI

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel

    public init(
        rootViewModel: RootViewModel
    ) {
        self.rootViewModel = rootViewModel
    }
}
