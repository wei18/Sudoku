# Impl Notes — ASC metadata harden (#310) (2026-06-04)

Status: COMPLETE
Owner: Developer
Dispatched by: Leader
Started: 2026-06-04

File-domain constraint: may touch ONLY `MetadataConfig.swift`,
`Reconciler+Metadata.swift`, `ASCClient+Metadata.swift`, + a new test file.
MUST NOT touch `main.swift` or `Config.swift` (parallel agent owns those).

## 設計決定 (Design decisions)

- **Length-limit table location** — Single source of truth as a nested
  `MetadataFieldLimits` enum in `MetadataConfig.swift`.

- **Validation injection point = `MetadataConfig.load()`** — Required to run
  during `plan` before any apply mutation WITHOUT editing main.swift.
  `load()` already `throws` / is `try`-called at main.swift:359 (before
  reconcile :402 and apply :409). Throwing a new
  `MetadataConfigError.fieldTooLong` from inside `load()` fails loud during
  plan, zero main.swift change. All violations collected, reported at once.

- **Char counting = grapheme `.count`, trim single trailing newline** — Swift
  `String.count` is grapheme count (closest to ASC). Trim ONE trailing `\n`
  (block-scalar artifact ASC ignores; live apply showed promo 171 only from
  trailing `\n`). Not a full whitespace trim — internal/leading whitespace
  still counts as ASC counts it.

## 偏離 (Deviations)

- **Problem 2 — reconciler-side strip, not client** — Brief pointed at
  `ASCClient+Metadata.swift:115`/`:149`, but the "first version" signal lives
  only in main.swift's `snapshotMetadata`. Threading a bool into the client
  needs `executeMetadata` (main.swift) to pass it — forbidden. Instead strip
  in `Reconciler+Metadata.swift`: when `remote.hasReleasedVersion == false`,
  emit version actions with a `ListingLocale` whose `whatsNew` is nilled.
  main.swift's `executeMetadata` forwards `listing.whatsNew` verbatim, so the
  upstream strip is equivalent with no client/main change.

## 折衷 (Tradeoffs)

- **`hasReleasedVersion` default = `true`** — main.swift can't be edited to
  set it, so the default must preserve TODAY's behavior (send whatsNew). Drop
  only triggers once a snapshot explicitly reports `false`.

## 未決 (Open questions)

- **main.swift wiring for Problem 2 is BLOCKED by the file constraint.** The
  reconciler drops whatsNew when `hasReleasedVersion == false`, but
  `snapshotMetadata` never sets the flag (defaults `true`), so the live
  first-version bug is not fixed end-to-end until a one-line wiring is added
  by whoever owns main.swift. Exact patch in the final report. Problem 1
  (length validation) IS fully wired with no main.swift change.

## Verification (2026-06-04)

- `swift build` clean. `swift test` → 93 tests / 14 suites pass (80 prior +
  13 new in `MetadataHardeningTests`). `MetadataConfigLoadTests` (loads the
  real committed `docs/app-store/metadata` tree through the NEW validator)
  pass ⇒ the corrected YAML clears the length caps offline.
- `swiftlint --strict` clean on all 4 changed files. MetadataConfig.swift
  crossed the 400-line `file_length` cap → added `// swiftlint:disable
  file_length` matching ASCClient.swift precedent (splitting a new source
  file was disallowed by the file-domain constraint).
- Live `metadata plan` NOT run: the sandbox denies outbound network to the
  ASC API (the run requires live GETs). No apply attempted; no secrets read
  into output. Offline proof of validator-passes-corrected-YAML stands via
  the load tests.

## Required follow-up (main.swift owner)

To make Problem 2 effective end-to-end, `snapshotMetadata` must set the new
flag from the already-fetched version list (no new network call):

```swift
// after `let versions = try await client.listAppStoreVersions(...)`
remote.hasReleasedVersion = versions.data.contains { v in
    let state = v.attributes["appStoreState"] ?? ""
    return MetadataRemoteState.releasedAppStoreStates.contains(state)
}
```

Until then `hasReleasedVersion` defaults `true` (legacy: whatsNew sent).
