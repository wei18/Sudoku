// SettingsAboutStorage — app-agnostic About(Version) row + Storage section.
//
// The two genuinely cross-game pieces of a game's Settings page:
//   - `SettingsAboutVersionRow` — the "Version" row (icon-left / label /
//     spacer / value-right pill).
//   - `SettingsStorageSection` — a `Section("Storage")` with a destructive
//     "Clear cache" button + confirmation dialog.
//
// Extracted from `SudokuUI/Settings/SettingsView.swift` (issue #277) so
// Minesweeper mounts the identical rows instead of a "Coming soon" stub.
//
// Theme decoupling mirrors `MonetizationUI.RemoveAdsRow`: the Version row
// takes a required `tintColor: Color` — GameShellUI gains NO dependency on
// any game's Theme. The host resolves it at the call site (Sudoku passes
// `theme.accent.primary.resolved`, Minesweeper passes `.accentColor`).
//
// Why About is a *row* but Storage is a *Section*: Sudoku's About section
// also hosts a Sudoku-only "Generator" row that is NOT shared. Exposing the
// Version as a bare row lets Sudoku compose it alongside Generator inside its
// own `Section("About")`. Storage has no per-game additions today, so the
// whole Section ships shared.
//
// Pill shape (issue #197): both pieces use the HStack + Spacer / Button-label
// HStack primitives so `.formStyle(.grouped)` renders them as full-width pills
// on macOS, matching the Purchases section's rows.

public import SwiftUI

// MARK: - About: Version row

/// Static "Version" row. `tintColor` colors the leading SF Symbol — supplied
/// by the host so this row carries no theme dependency.
public struct SettingsAboutVersionRow: View {
    private let version: String
    private let tintColor: Color

    public init(version: String, tintColor: Color) {
        self.version = version
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack {
            Image(systemName: "info.circle")
                .foregroundStyle(tintColor)
            Text("Version")
            Spacer()
            Text(version)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Storage section

/// `Section("Storage")` with a destructive "Clear cache" button. The button
/// raises a confirmation dialog; confirming runs the host-supplied async
/// `clearCache` action. The host wires this to its persistence (deleting the
/// active in-progress saved game).
public struct SettingsStorageSection: View {
    private let clearCache: @MainActor () async -> Void
    @State private var showClearCacheConfirmation = false

    public init(clearCache: @escaping @MainActor () async -> Void) {
        self.clearCache = clearCache
    }

    public var body: some View {
        Section("Storage") {
            Button(role: .destructive) {
                showClearCacheConfirmation = true
            } label: {
                // HStack + Spacer stretches the label so the grouped Form
                // gives this row the same full-width pill treatment as the
                // Purchases section's button rows (issue #197).
                HStack {
                    Label("Clear cache", systemImage: "trash")
                    Spacer()
                }
            }
        }
        .confirmationDialog(
            "Reset session cache",
            isPresented: $showClearCacheConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear cache", role: .destructive) {
                Task { await clearCache() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Generated puzzles will be re-derived next play. Saved games are not affected.")
        }
    }
}
