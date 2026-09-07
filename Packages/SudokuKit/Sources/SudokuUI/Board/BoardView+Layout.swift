// BoardView+Layout — the board screen's two size-class arrangements.
//
// Extracted from BoardView.swift to keep that file under SwiftLint's
// file_length ceiling (repo convention: extract a `+Feature.swift` sibling
// rather than disabling the rule). BoardView.swift keeps the view's state,
// `body` and lifecycle; the geometry lives here.
//
// #1022 reshaped both layouts: the compact one puts the board edge-to-edge
// and floats the G4 control cluster below it, while the Mac one keeps the
// capped 960/640 detail column it has always had. See `compactLayout` for
// why the board keeps its size when the cluster unmounts.

internal import GameAppKit
import MonetizationCore
import MonetizationUI
import SudokuEngine
import SwiftUI

extension BoardView {
    // MARK: - Compact (iPhone) layout

    var compactLayout: some View {
        // Structural (#762 PR2 two-tier spacing contract) — screen rhythm
        // between header/board/control cluster; fixed because inflating it
        // would shrink the `GeometryReader`-sized board grid below it.
        VStack(spacing: theme.spacing.medium) {
            // Chrome keeps its screen margin; the board below does not.
            header
                .padding(.horizontal, theme.spacing.medium)
            // #1022: full-bleed — no horizontal padding between this square
            // and the screen edge, so the cell side is the offered width / 9
            // (design.md §3.4). `.layoutPriority(1)` gives the board first
            // claim on the leftover height, so the trailing `Spacer` — not the
            // board — absorbs whatever the chrome below occupies; that is what
            // stops the board resizing when the cluster unmounts below.
            boardWithOverlay
                .layoutPriority(1)
            Spacer(minLength: 0)
            // v2.3.5: banner sits between the grid and the control cluster,
            // suppressed while paused — pause is a moment of intentional quiet
            // (PauseOverlayView already dims the grid) and an ad on top of that
            // contradicts the calm contract.
            if !viewModel.isPaused, let adProvider, let adGate {
                themedBanner(adProvider: adProvider, adGate: adGate)
                    .padding(.horizontal, theme.spacing.medium)
            }
            controlCluster
        }
        // #1022: vertical screen margin only — the horizontal half of the old
        // blanket padding is what used to inset the board; it is per-child now.
        .padding(.vertical, theme.spacing.medium)
    }

    // MARK: - Mac (regular) 2-column layout
    //
    // Per docs/designs/05-board.md §b Mac wireframe (locked 2026-05-30):
    //   - outer maxWidth 960 pt, centered
    //   - left: 9×9 board (capped to ≤ 640 pt square)
    //   - right: 260 pt control rail (history / Notes / 3×3 digit / Erase)
    //   - 24 pt gap between board and rail
    var macLayout: some View {
        // Structural (#762 PR2 two-tier spacing contract) — same rationale
        // as `compactLayout` above.
        VStack(spacing: theme.spacing.medium) {
            header
            // Structural — 24 pt gap between board and rail (locked in the
            // Mac wireframe comment above); fixed because it governs how
            // much width `macBoardColumn` gets, which drives its cell size.
            HStack(alignment: .top, spacing: theme.spacing.large) {
                macBoardColumn
                controlCluster
            }
            // Pause-time banner suppression preserved on Mac too.
            if !viewModel.isPaused, let adProvider, let adGate {
                themedBanner(adProvider: adProvider, adGate: adGate)
            }
        }
        .frame(maxWidth: 960)
        .frame(maxWidth: .infinity, alignment: .center)
        // Structural (#762 PR2 two-tier spacing contract) — additive to the
        // screen-margin padding below (→ ≥ 32 pt combined); fixed for
        // the same board-sizing reason as that screen margin.
        .padding(.horizontal, theme.spacing.medium)
        // #1022: the screen margin `body` used to apply to BOTH layouts.
        // Full-bleed is an iPhone-board rule (§3.4's cell table is three
        // iPhone widths); the Mac board sits in a capped 960/640 detail
        // column, so it keeps the margin it had and is unchanged by #1022.
        .padding(theme.spacing.medium)
    }

    /// Themed shared `MonetizationUI.BannerSlotView` (#441). Board never drives
    /// ATT (Home owns the primer), so `onAdContext` stays nil. The live provider
    /// conforms to `BannerViewProviding`; fakes / macOS return nil → honest
    /// fallback. The cast keeps SudokuUI free of an AdsAdMob import (§9.1).
    private func themedBanner(adProvider: any AdProvider, adGate: AdGate) -> some View {
        BannerSlotView(
            adProvider: adProvider,
            adGate: adGate,
            bannerHost: adProvider as? any BannerViewProviding,
            // #688 item 2: was `theme.surface.placeholder.resolved` — mirrors
            // the MS fix in `MinesweeperBoardView` so both apps' banner
            // containers match their own page background instead of a
            // "card" tone that reads as a seam in dark mode.
            backgroundColor: theme.surface.background.resolved,
            progressTint: theme.accent.primary.resolved,
            captionColor: theme.text.secondary.resolved,
            dismissTint: theme.accent.muted.resolved.opacity(0.7)
        )
    }

    private var macBoardColumn: some View {
        boardWithOverlay
            .frame(maxWidth: 640, maxHeight: 640)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // #1022 scene exclusivity (design.md §4.3): when Completion's G6 panel
    // rises, board-scene G4 must LEAVE — "不是被蓋住,是真的 unmount" — and it
    // must equally be gone while paused. Both come off the ONE value that
    // already drives every board modal, `modalOverlayPresentation`
    // (BoardView+Completion.swift), nil exactly when no completion / pause /
    // leave-confirmation surface is up. Deliberately NO new observer and NO
    // preference key: #1020 removed `BoardModalOverlayActivePreferenceKey`
    // because observing it from the shell root unmounted the pushed board on
    // macOS, and #1019 proved `.disabled()` on the shell deadlocks the
    // overlay's own CTA.
    @ViewBuilder
    private var controlCluster: some View {
        if modalOverlayPresentation == nil {
            digitPad
        }
    }

    private var digitPad: some View {
        DigitPadView(
            pencilMode: viewModel.pencilMode,
            canUndo: viewModel.canUndo,
            canRedo: viewModel.canRedo,
            sizeClass: sizeClass,
            remainingCounts: (1...9).map { dgt in max(0, 9 - viewModel.board.cells.filter { $0 == UInt8(dgt) }.count) },
            armedDigit: viewModel.armedDigit,
            hasSelection: viewModel.selection != nil,
            // #722: routing (place-into-selection vs arm/disarm) lives on the
            // VM (`keypadDigit`), matching every other mutation on this board.
            onDigit: { digit in Task { await viewModel.keypadDigit(digit) } },
            onErase: { Task { await viewModel.eraseCell() } },
            onTogglePencil: { viewModel.togglePencil() },
            onUndo: { Task { await viewModel.undo() } },
            onRedo: { Task { await viewModel.redo() } }
        )
    }

    // MARK: - Layout
    //
    // The header (incl. the #540 Dynamic Type robustness via ViewThatFits)
    // lives in the sibling file BoardView+AccessibilityHeader.swift.

    private var boardWithOverlay: some View {
        // GeometryReader reports the offered size to its children but takes
        // the full offered frame for its own layout — so we read the offered
        // box here, compute the square `side`, and explicitly size both the
        // grid and the overlay to that square.
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let cellSide = side / CGFloat(Board.dimension)
            ZStack {
                // spacing-exempt: zero-gap — the board grid's own row/column
                // seams are cell geometry, not a spacing decision (#762 PR2).
                VStack(spacing: 0) {
                    ForEach(0..<Board.dimension, id: \.self) { row in
                        HStack(spacing: 0) {
                            ForEach(0..<Board.dimension, id: \.self) { col in
                                cell(row: row, column: col, side: cellSide)
                            }
                        }
                    }
                }
                .frame(width: side, height: side)
            }
            // Centre the square grid within the GR's offered rectangle so
            // the board sits inline with the surrounding header/digit pad
            // padding instead of sticking to the leading edge.
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
        .aspectRatio(1, contentMode: .fit)
    }

}
