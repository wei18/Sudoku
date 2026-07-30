// SnapshotLocales — store-screenshot redesign (feat/store-screenshots-cb).
//
// Extracted from SnapshotConfig.swift to stay under SwiftLint's 400-line
// file_length ceiling (repeats the pattern already used elsewhere in this
// suite — see SnapshotConfig.swift's own extraction history).

/// The 6 repo locales (of 7) that need their OWN baseline for the ASC
/// marketing pipeline's per-slot `SLOTS[device][app][slot]` map — `en`
/// already has a baseline from the pre-existing (unparameterized) snapshot
/// tests, so it's excluded here. Sourced via the existing
/// `hostingView(locale:)` injection; no new capture mechanism. Keep in sync
/// with MinesweeperKit's copy (separate packages).
enum SnapshotLocales {
    static let storeLocales = ["zh-Hant", "zh-Hans", "ja", "ko", "es", "th"]
}
