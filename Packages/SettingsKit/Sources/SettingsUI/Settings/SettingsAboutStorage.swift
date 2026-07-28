// SettingsAboutStorage — app-agnostic About(Version) row + Storage section.
//
// The genuinely cross-game pieces of a game's Settings page:
//   - `SettingsAboutVersionRow` — the "Version" row (icon-left / label /
//     spacer / value-right pill).
//   - `SettingsAboutExtraRow` — a generic icon/label/value pill for an
//     optional extra About row. #832: extracted from the per-app `AboutRow`
//     (originally SudokuUI-only, rendering the Generator version) so the
//     unified `GameAppKit.SettingsView` can mount it generically — it carries
//     no Sudoku dependency, just the three primitives.
//   - `SettingsStorageSection` — a `Section("Storage")` with a destructive
//     "Clear cache" button + confirmation dialog.
//
// Extracted from `SudokuUI/Settings/SettingsView.swift` (issue #277) so
// Minesweeper mounts the identical rows instead of a "Coming soon" stub.
//
// Theme decoupling mirrors `MonetizationUI.RemoveAdsRow`: the Version row
// takes a required `tintColor: Color` — GameShellUI gains NO dependency on
// any game's Theme. The host resolves it at the call site (both Sudoku and
// Minesweeper pass `theme.accent.primary.resolved` as of #688 item 5a —
// Minesweeper previously passed `.accentColor`, a cross-app tint drift).
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
            // #845: `Label { } icon: { }` (not a raw `Image + Text` HStack) —
            // matches `AudioSettingsSection`'s row shape so the icon column
            // gets the same system-standard leading width as every other
            // settings row instead of a tighter ad-hoc HStack gap.
            Label {
                Text("Version")
            } icon: {
                Image(systemName: "info.circle")
                    .foregroundStyle(tintColor)
            }
            Spacer()
            Text(version)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - About: generic extra row

/// Static icon-left / label / spacer / value-right row matching
/// `SettingsAboutVersionRow`'s pill shape (issue #197), for an app-injected
/// extra About row. Today's only consumer is Sudoku's "Generator" row
/// (`GameAppKit.SettingsView`, gated on `SettingsViewModel.generatorVersionLabel`).
/// `tintColor` is required (no default) — same theme-decoupling as
/// `SettingsAboutVersionRow` above; the host resolves it at the call site.
public struct SettingsAboutExtraRow: View {
    private let systemImage: String
    private let title: LocalizedStringKey
    private let value: String
    private let tintColor: Color

    public init(systemImage: String, title: LocalizedStringKey, value: String, tintColor: Color) {
        self.systemImage = systemImage
        self.title = title
        self.value = value
        self.tintColor = tintColor
    }

    public var body: some View {
        HStack {
            // #845: same `Label` fix as `SettingsAboutVersionRow` above.
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(tintColor)
            }
            Spacer()
            Text(value)
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
    // #956: `true` once the host's `clearCache()` precondition (its
    // `resumeCandidate` load) has settled — see `SettingsViewModel.isCacheStateReady`.
    // Defaults `true` so previews / tests (which never wire an async
    // bootstrap) keep the marker present unchanged.
    private let isCacheStateReady: Bool
    @State private var showClearCacheConfirmation = false

    public init(
        isCacheStateReady: Bool = true,
        clearCache: @escaping @MainActor () async -> Void
    ) {
        self.isCacheStateReady = isCacheStateReady
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
            // #935 batch 5: stable, non-localized anchor for the N19
            // clear-cache negative-flow E2E test.
            .accessibilityIdentifier("settings.storage.clearCache")
            // #956: zero-size, non-localized anchor that exists ONLY once
            // `clearCache()`'s precondition has settled — lets a host-driven
            // E2E test wait for it before tapping Confirm instead of racing
            // the async load (the N19 flake's actual root cause). Composed
            // as a SIBLING `.background` layer, not a container id, per the
            // #937 "container id clobbers descendant ids" lesson — mirrors
            // `DailyHubView`'s `sudoku.dailyHub.root` marker (#935 batch 3).
            .background(alignment: .topLeading) {
                if isCacheStateReady {
                    Color.clear
                        .frame(width: 1, height: 1)
                        .accessibilityIdentifier("settings.storage.cacheReady")
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
            // #935 batch 5: stable ids on the system-rendered confirmation
            // dialog's own buttons so the N19 E2E test can discriminate
            // confirm vs Cancel without depending on localized titles.
            .accessibilityIdentifier("settings.storage.clearCache.confirm")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.storage.clearCache.cancel")
        } message: {
            Text("Generated puzzles will be re-derived next play. Saved games are not affected.")
        }
    }
}
