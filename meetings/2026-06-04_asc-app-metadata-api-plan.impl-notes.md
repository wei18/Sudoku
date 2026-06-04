# Impl Notes — ASC metadata subcommand (#310) (2026-06-04)

Status: COMPLETE
Owner: Senior Developer (worktree dispatch)
Dispatched by: Leader
Started: 2026-06-04

## 設計決定 (Design decisions)

- **YAML reader = Yams (third-party), NOT hand-rolled** — Plan §3 / §7 left
  this open (option a: hand-roll, option b: build-time JSON convert). Chose
  **Yams** (`jpsim/Yams`). Reason: the `listing.yaml` files use `|` block
  scalars that contain **embedded blank lines** (the `description` /
  `whats_new` paragraph breaks) plus a nested map (`review_information:` with
  its own `|` block + `null` values). A correct hand-rolled block-scalar
  reader (indentation tracking + blank-line preservation + chomping) is ~120
  lines of fiddly parsing that itself needs a test matrix — net more code +
  risk than a vetted dep. Plan explicitly allows the dep ("dev-only macOS CLI,
  third-party dep is acceptable"). Yams is the de-facto Swift YAML lib
  (SwiftLint / Sourcery use it), pure-Swift, SwiftPM, macOS-clean.

- **`--app <sudoku|minesweeper>` selects the metadata subtree** — per plan §3
  and metadata/README asymmetric layout: `sudoku` → `docs/app-store/metadata/`
  top level; `minesweeper` → `docs/app-store/metadata/minesweeper/`. The
  `--metadata-dir` flag defaults to `docs/app-store/metadata` (override for
  tests / relocations).

- **`apple_id` (app-id) precedence** — `metadata` reads `app-meta.yaml`'s
  `apple_id` if present, but a `--app-id` flag overrides. Sudoku app-meta has
  `apple_id: "6772925351"`; MS app-meta has it commented out (no ASC record).
  So `--app sudoku` needs no `--app-id`; `--app minesweeper` will fail the
  app lookup (404/no-id) — handled gracefully (warn + clean exit), per brief.

- **Category model** — `app-meta.yaml` is the canonical category source
  (primary/secondary + first/second sub-category). ASC models categories as a
  relationship on `appInfos` → `appCategories`. The human labels ("Games",
  "Puzzle") map to ASC category id tokens (`GAMES`, `GAMES_PUZZLE`, ...). The
  exact tokens were UNCONFIRMED (plan §7); resolved via the live
  `listAppCategories()` GET in the plan pass (see Open questions / plan doc).

## 偏離 (Deviations)

- **Version string handling** — plan §3 CLI shows `--version <e.g. 2.5>`.
  Sudoku's listings say `Version 1.0` (whats_new) and ASC app is pre-launch.
  Implemented `--version` as **optional**: if omitted, the command GETs the
  app's `appStoreVersions` and picks the single editable one (state ∈
  editable set). Avoids hardcoding a version that drifts. Falls back to
  `--version` filter when the app has multiple versions.

## 折衷 (Tradeoffs)

- **Reuse `getCollectionWithIncluded` vs new GET helpers** — reused the
  existing `?include=` fan-out helper for appInfos→localizations and
  version→localizations (one GET each), matching the IAP path. Added thin
  per-endpoint GET wrappers in `ASCClient+Metadata.swift` only where a
  dedicated relationship URL is needed (appCategories list).

- **MetadataConfig as a standalone loader (not folded into Config.swift)** —
  Config.swift is the GC/IAP single-source-of-truth with byte-equality tests.
  Metadata content lives in YAML, not Swift, so it gets its own
  `MetadataConfig.swift` loader rather than polluting Config. Mirrors the
  XCStringsParser separation.

## 未決 (Open questions)

- **Live Sudoku plan pass NOT run by subagent — BLOCKED on secret access.**
  The required `metadata plan --app sudoku` run resolves plan §7's `?` items
  (category id tokens, editable appInfo state, live attribute key names). The
  sandbox correctly denies the subagent reading `secrets/.env` (where the
  `.p8` path + issuer live), so the subagent cannot execute the authenticated
  GET pass. The command is built to print every finding (category catalog,
  chosen appInfo id+state, attribute keys seen) — **Leader/User must run it
  once** (command in plan doc §7.a). Code-side defaults: attribute names per
  Apple docs; category tokens `GAMES_<SUB>`; editable-state set listed in
  `snapshotMetadata`. Risk if a default is wrong: first `apply` 4xx, decoded
  via the existing `asc-apply-round` flow — non-destructive, surfaced as a
  plan/error, not silent corruption.

- **`apply` implemented but never run** (per brief — user-owned). The execute
  paths (`executeMetadata`) POST/PATCH appInfoLocalizations,
  appStoreVersionLocalizations, and the appInfos category relationship. Only
  reachable via `metadata apply`; `plan` is pure GET + dry-run `mutate`.
