// SnapshotConfigDynamicTypeSize — AX5 / accessibility Dynamic Type variant
// of `SnapshotConfig.swift`'s `hostingView(...)` (#762 PR1 spec item E).
//
// Extracted to its own file rather than added to `SnapshotConfig.swift`
// directly — that file is already at SwiftLint's 400-line cap (mirrors why
// MinesweeperKit's `SnapshotConfig.swift` inlines its structural-baseline
// helper instead of extracting it: Sudoku's copy is the one that needed the
// split; see that file's header comment).
//
// Kept as a SEPARATE OVERLOAD rather than an added optional parameter on the
// existing `hostingView(...)` so every existing call site keeps resolving to
// that function — its concrete `NSHostingView<...>` generic type (and
// therefore `assertViewStructure`'s mangled-type-name baselines) stays
// byte-identical. Same environment injection as `hostingView(...)`, plus an
// explicit `dynamicTypeSize` override.

#if canImport(AppKit)
import AppKit
import SwiftUI
@testable import SudokuUI

@MainActor
func hostingView<V: SwiftUI.View>(
    _ view: V,
    size: CGSize,
    colorScheme: ColorScheme = .light,
    locale: Locale? = nil,
    sizeClass: UserInterfaceSizeClass = .compact,
    dynamicTypeSize: DynamicTypeSize
) -> NSView {
    let wrapped = view
        .environment(\.theme, DefaultTheme())
        .environment(\.sudokuCell, DefaultTheme().cell)
        .environment(\.horizontalSizeClass, Optional(sizeClass))
        .environment(\.locale, locale ?? .current)
        .environment(\.dynamicTypeSize, dynamicTypeSize)
        .preferredColorScheme(colorScheme)
        .frame(width: size.width, height: size.height)
    let host = NSHostingView(rootView: wrapped)
    host.sizingOptions = []
    host.frame = CGRect(origin: .zero, size: size)
    host.appearance = NSAppearance(named: colorScheme == .dark ? .darkAqua : .aqua)
    host.layoutSubtreeIfNeeded()
    return host
}
#endif
