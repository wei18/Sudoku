// SettingsIAPRows — Form rows for the Remove Ads / Restore Purchases section.
//
// Extracted from `SudokuUI/Settings/SettingsView.swift` in Phase 1 of the MS
// monetization wire (see `meetings/2026-06-02_minesweeper-monetization-wire-proposal.md`).
// The rows are reusable across apps — Sudoku and Minesweeper both mount
// identical "Purchases" sections. Theme decoupling is via a required
// `tintColor: Color` init param; the host (Sudoku reads `theme.accent.primary`)
// resolves it at the call site.
//
// Composition contract: drop these into a `Section("Purchases")` of a Form
// owned by the host's SettingsView. The view shapes (icon-left / label /
// spacer / value-right HStack) intentionally match the host's About rows so
// `.formStyle(.grouped)` renders both sections with the same full-width pill
// background on macOS (issue #197).

public import SwiftUI

// MARK: - Remove Ads CTA row

/// Tap-to-purchase row. Visible only when `controller.hasPurchasedRemoveAds`
/// is `false`. Spinner swaps in while `controller.purchaseInFlight` is `true`.
public struct RemoveAdsRow: View {
    @Bindable private var controller: MonetizationStateController
    private let tintColor: Color

    public init(
        controller: MonetizationStateController,
        tintColor: Color
    ) {
        self.controller = controller
        self.tintColor = tintColor
    }

    public var body: some View {
        Button {
            Task { await controller.purchaseRemoveAds() }
        } label: {
            HStack {
                Image(systemName: "sparkles")
                    .foregroundStyle(tintColor)
                Text("Remove Ads")
                Spacer()
                Group {
                    if controller.purchaseInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(controller.removeAdsDisplayPrice)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .disabled(controller.purchaseInFlight)
        .accessibilityLabel("Remove Ads \(controller.removeAdsDisplayPrice)")
    }
}

// MARK: - Already-purchased confirmation row

/// Static "Ads Removed — Active" row shown in place of `RemoveAdsRow` after
/// the entitlement flips on.
public struct AdsRemovedRow: View {
    private let tintColor: Color

    public init(tintColor: Color) {
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack {
            Label("Ads Removed", systemImage: "checkmark.seal.fill")
                .foregroundStyle(tintColor)
            Spacer()
            Text("Active")
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Ads removed. Active.")
    }
}

// MARK: - Restore Purchases row

/// Always-visible companion to the Remove Ads / Ads Removed row. Calls
/// `controller.restorePurchases()` and shows a spinner while the call is
/// in flight.
public struct RestorePurchasesRow: View {
    @Bindable private var controller: MonetizationStateController
    private let tintColor: Color

    public init(
        controller: MonetizationStateController,
        tintColor: Color
    ) {
        self.controller = controller
        self.tintColor = tintColor
    }

    public var body: some View {
        Button {
            Task { await controller.restorePurchases() }
        } label: {
            HStack {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(tintColor)
                Text("Restore Purchases")
                Spacer()
                Group {
                    if controller.restoreInFlight {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                }
                .frame(minWidth: 60, alignment: .trailing)
            }
        }
        .disabled(controller.restoreInFlight)
    }
}
