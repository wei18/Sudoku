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

    /// #881 (closing #874 F-7): true when the most recent purchase attempt
    /// failed. Drives a distinct icon/tint + a short-lived secondary caption
    /// so this row no longer renders identically to "never attempted" once
    /// the transient success/failure toast has dismissed.
    private var purchaseFailed: Bool {
        if case .purchaseFailed = controller.flowState { return true }
        return false
    }

    public var body: some View {
        Button {
            Task { await controller.purchaseRemoveAds() }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // #845/#848: `Label { } icon: { }` (not a raw `Image + Text`
                    // HStack) — matches the standard row shape so the icon
                    // column gets the same system-standard leading width as
                    // every other settings row.
                    Label {
                        Text("Remove Ads")
                    } icon: {
                        Image(systemName: purchaseFailed ? "exclamationmark.triangle.fill" : "sparkles")
                            .foregroundStyle(purchaseFailed ? .red : tintColor)
                    }
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
                if purchaseFailed {
                    // #881: distinct persistent caption (#874 F-7) — the
                    // transient toast already told the user once; this stays
                    // until the next purchase/restore attempt clears
                    // `flowState`.
                    Text("Last attempt failed")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.leading, 28)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(controller.purchaseInFlight)
        .accessibilityLabel(accessibilityLabelText)
    }

    /// #895: VoiceOver was announcing this raw Swift string in English on all
    /// 7 locales. Composed from `String(localized:)` fragments — the
    /// price-interpolated base needs its own key; the failure caption reuses
    /// the existing "Last attempt failed" key (#881) rather than minting a
    /// duplicate combined string.
    private var accessibilityLabelText: String {
        let base = String(localized: "Remove Ads \(controller.removeAdsDisplayPrice)", bundle: .main)
        guard purchaseFailed else { return base }
        let failedCaption = String(localized: "Last attempt failed", bundle: .main)
        return "\(base). \(failedCaption)"
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
        .accessibilityLabel(accessibilityLabelText)
    }

    /// #895: composed from `String(localized:)` fragments — "Ads removed"
    /// (sentence case) is a new key since it differs in case from the
    /// visible "Ads Removed" title-case label; "Active" reuses the existing
    /// key already shown by the trailing `Text("Active")` above.
    private var accessibilityLabelText: String {
        let adsRemoved = String(localized: "Ads removed", bundle: .main)
        let active = String(localized: "Active", bundle: .main)
        return "\(adsRemoved). \(active)."
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
                // #845/#848: same `Label` fix as `RemoveAdsRow` above.
                Label {
                    Text("Restore Purchases")
                } icon: {
                    Image(systemName: "arrow.clockwise")
                        .foregroundStyle(tintColor)
                }
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
        .buttonStyle(.plain)
        .disabled(controller.restoreInFlight)
    }
}
