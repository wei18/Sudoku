# ASC App-Metadata API — extension plan for ASCRegister

**Date**: 2026-06-04
**Author**: Developer/Researcher (worktree dispatch, #236)
**Status**: PLAN ONLY — no Swift impl this round (needs ASC creds to test; follow-up)
**Relates to**: `asc-ops-handoff` skill ("Upload App Metadata … `ASCRegister
app-metadata` mode" = 📅 BACKLOG); `docs/app-store/metadata/README.md`;
existing `iap` subcommand pattern.

## 1. Goal

Let ASCRegister push the per-locale storefront listing copy (name / subtitle /
promotional text / description / keywords / what's-new / URLs / category) from
the committed `listing.yaml` files to App Store Connect, the same
plan/apply/idempotent-reconcile way the `iap` subcommand already pushes IAP
localizations. This replaces the manual "paste 7 locales × N fields into the
ASC web UI, then diff" loop (today's process per metadata/README.md).

Screenshot upload is explicitly out of scope (needs built-app images) — see §6.
Final "Submit for Review" stays user-owned per `asc-ops-handoff`.

## 2. ASC API resource map

The ASC REST API models app metadata as a tree under an app version. The
relevant resources, in dependency order:

```
apps/{appId}
├── appInfos                      (1+ per app; the "current editable" one)
│   ├── appInfoLocalizations      ← name, subtitle, privacyPolicyUrl
│   └── relationships: primaryCategory / secondaryCategory → appCategories
└── appStoreVersions             (one per version string, e.g. "2.5")
    └── appStoreVersionLocalizations ← description, keywords, promotionalText,
                                        whatsNew, marketingUrl, supportUrl
        └── appScreenshotSets → appScreenshots  (OUT OF SCOPE, §6)
```

### Which field lives on which resource (this is the non-obvious part)

| `listing.yaml` field | ASC resource | ASC attribute |
|---|---|---|
| `name` | `appInfoLocalizations` | `name` |
| `subtitle` | `appInfoLocalizations` | `subtitle` |
| `privacy_policy_url` | `appInfoLocalizations` | `privacyPolicyUrl` |
| `primary_category` / `secondary_category` | `appInfos` (relationship) | rel → `appCategories` |
| `description` | `appStoreVersionLocalizations` | `description` |
| `keywords` | `appStoreVersionLocalizations` | `keywords` |
| `promotional_text` | `appStoreVersionLocalizations` | `promotionalText` |
| `whats_new` | `appStoreVersionLocalizations` | `whatsNew` |
| `marketing_url` | `appStoreVersionLocalizations` | `marketingUrl` |
| `support_url` | `appStoreVersionLocalizations` | `supportUrl` |
| `age_rating` | (NOT version-localization) | `ageRatingDeclarations` on the version — separate resource; treat as user-owned for v1, see §5 |

The split matters: a single `listing.yaml` locale block fans out to **two**
ASC POST/PATCH targets (`appInfoLocalizations` + `appStoreVersionLocalizations`),
plus a one-time category relationship PATCH on `appInfos`.

## 3. CLI / code shape (mirrors the existing `iap` subcommand)

New subcommand, parallel to `iap`:

```
ASCRegister metadata plan  --key <p8> --key-id <id> --issuer <id> \
    --app-id <id> --app <sudoku|minesweeper> --version <e.g. 2.5> \
    --metadata-dir docs/app-store/metadata
ASCRegister metadata apply --key ... (same flags)
```

Files to add / extend (mirrors `iap`'s `Config` + `ASCClient+IAP` +
`Reconciler` + `main.swift` slice):

- **`Sources/ASCRegister/MetadataConfig.swift`** (new) — a YAML reader. The
  repo has no YAML dep and `main.swift` deliberately avoids
  swift-argument-parser; follow the same no-external-dep stance. Two options
  (decide at impl time, §7 prereq): (a) hand-roll a minimal YAML subset
  reader for the flat `key: "value"` + `key: |` block shapes these files use,
  or (b) convert the `listing.yaml` files to JSON at build time and decode
  with `JSONDecoder`. Recommend (a) — the schema is tiny and fixed; a ~60-line
  reader avoids a build-step dependency. Mirrors how `XCStringsParser` already
  hand-parses the xcstrings JSON without a schema lib.
- **`Sources/ASCRegister/ASCClient+Metadata.swift`** (new) — methods:
  - `getAppInfos(appId:)` → pick the editable `appInfo`
    (state ∈ {PREPARE_FOR_SUBMISSION, …}).
  - `listAppInfoLocalizations(appInfoId:)`
  - `create/updateAppInfoLocalization(...)` (name, subtitle, privacyPolicyUrl)
  - `getAppStoreVersion(appId:, versionString:)` → the version resource id.
  - `listAppStoreVersionLocalizations(versionId:)`
  - `create/updateAppStoreVersionLocalization(...)` (description, keywords,
    promotionalText, whatsNew, marketingUrl, supportUrl)
  - `listAppCategories()` + `patchAppInfoCategories(appInfoId:, primary:, secondary:)`
  - Reuse `getCollectionWithIncluded` (already in ASCClient) to pull a version
    + its localizations in one GET via `?include=appStoreVersionLocalizations`,
    exactly as the IAP path does.
- **`Reconciler.swift`** (extend) — add metadata actions
  (`createAppInfoLoc / updateAppInfoLoc / appInfoLocUnchanged`,
  `createVersionLoc / updateVersionLoc / versionLocUnchanged`,
  `updateCategories / categoriesUnchanged`). Pure function: `(config, remote)
  → [Action]`, same as the GC/IAP reconcile. Per-field diff so an unchanged
  locale produces `*Unchanged` (no-op) — the idempotency property.
- **`main.swift`** (extend) — `case "metadata":` nested subcommand dispatch
  (`plan` / `apply`), copying `runIAPRemote`'s structure: snapshot remote,
  reconcile, print plan, optionally execute. Filter to metadata-scoped actions
  only (same defensive filter the IAP path uses to drop GC noise).

The `--app` flag selects the metadata subtree
(`metadata/<locale>/` for sudoku, `metadata/minesweeper/<locale>/`); see
metadata/README.md for the asymmetric layout. Locale codes map through the
existing `Config.ascLocaleCode(for:)` (en→en-US, es→es-ES, th→th-TH, ko→ko-KR,
zh-Hant/zh-Hans/ja unchanged).

## 4. Idempotency / reconcilability

- **Idempotent**: name / subtitle / description / keywords / promotionalText /
  whatsNew / marketingUrl / supportUrl / privacyPolicyUrl — all are plain
  PATCH-able attributes; reconcile = GET remote, diff per field, PATCH only
  changed. A second `apply` with no source change yields an all-`Unchanged`
  plan. Same guarantee the IAP-localization path already provides.
- **Create-vs-update**: if a locale's `appStoreVersionLocalization` /
  `appInfoLocalization` does not exist yet, POST it; else PATCH. Detect by
  matching the `locale` attribute in the remote snapshot (same key shape as
  `RemoteState.LocalizationKey`).
- **Categories**: a relationship PATCH on `appInfos`; idempotent (PATCH to the
  same category ids is a no-op). Needs a one-time `listAppCategories()` to map
  the human label ("Games > Puzzle") to the ASC category id
  (`GAMES_PUZZLE` / `GAMES_BOARD` enum-ish ids). UNCONFIRMED exact id tokens
  (§7).

## 5. USER-OWNED boundary (do NOT automate)

Per `asc-ops-handoff` taxonomy:

- **App version creation** — the `appStoreVersions` record for "2.5" (Sudoku)
  or "1.0" (MS) must already exist in ASC before metadata localizations can
  attach. ASCRegister should GET-and-fail-loud if the version is missing, not
  create it. (Version creation is coupled to the build/TestFlight flow, which
  is user-owned.)
- **Age rating** (`ageRatingDeclarations`) — a questionnaire-style resource;
  keep user-owned for v1 (parallels the App Privacy questionnaire which has no
  API). The `age_rating: "4+"` in the YAML is documentation, not pushed.
- **App Privacy questionnaire / nutrition labels** — no API (verified
  2026-05-23 per asc-ops-handoff); user-owned.
- **Screenshots** — need built-app images; §6.
- **Submit for Review** — user-owned.

## 6. Screenshots (deferred — needs built app)

`appScreenshotSets` + `appScreenshots` is a multi-step reservation/upload/commit
flow (create set → reserve asset → PUT bytes to the returned upload
operations → commit with checksum). It is automatable in principle, but:
(a) it needs the actual PNGs, which require the built app (Sudoku
`screenshot-strategy.md` = 140 files; MS strategy not yet authored), and
(b) the reserve/upload/commit handshake is materially more complex than the
flat PATCH attributes above. **Recommendation: separate, later phase** once
the binaries + screenshots exist. List it as a follow-up, not part of the
first `metadata` mode.

## 7. Prerequisite checklist

Per AI-collaboration-mode rule, every dependency marked Verified ✓ / Unconfirmed ?.

- ✓ ASCRegister already authenticates to ASC (JWT.sign + ASCClient) and has a
  working plan/apply/reconcile pattern (GC + IAP shipped).
- ✓ `getCollectionWithIncluded` exists for one-GET `?include=` fan-out.
- ✓ Locale mapping (`Config.ascLocaleCode`) covers all 7 locales.
- ✓ `listing.yaml` field names already chosen to mirror ASC attributes
  (snake_case → camelCase is a trivial map).
- ✓ Per-app metadata subtree decided + documented (metadata/README.md).
- ? **`appInfoLocalizations` attribute names** — `name`, `subtitle`,
  `privacyPolicyUrl` are the documented attributes, but confirm against a live
  GET before first apply (Apple has shifted `name` between resources
  historically). Resolve with one `inspect`-style GET once creds are available.
- ? **`appStoreVersionLocalizations` attribute names** — `description`,
  `keywords`, `promotionalText`, `whatsNew`, `marketingUrl`, `supportUrl`.
  Same: confirm via live GET.
- ? **`appCategories` id tokens** — exact enum strings for "Games > Puzzle",
  "Games > Board", "Games > Family". Resolve via `listAppCategories()` GET.
- ? **Which `appInfo` is editable** — an app can have multiple `appInfos`;
  need to select the one in an editable state. Confirm the state enum value
  via live GET.
- ? **MS app record exists in ASC** — the Minesweeper app + its `appStoreVersions`
  "1.0" must be created (user-owned) before `metadata apply --app minesweeper`
  can run. Currently the MS app record likely does not exist yet (no Apple ID
  in `minesweeper/iap/remove-ads.yaml`).
- ? **No-YAML-dep reader** — confirm the hand-rolled minimal YAML reader (§3
  option a) handles the `|` block scalars + quoted scalars in these files. Low
  risk (schema is fixed), but it's net-new parsing code to test.

**Gate**: all `?` items resolve with a single read-only `inspect`/GET pass once
the user provides ASC creds (secrets/ — not referenced here). None are
blockers to writing the code; they're blockers to a confident first `apply`.
This is why this round is plan-only.

## 8. Suggested follow-up dispatch

One Developer dispatch, Code-Reviewer-gated (touches ASCRegister core →
core-module CR trigger), in two steps:
1. **Read-only verify pass**: add a `metadata inspect` that GETs appInfos +
   appStoreVersions + appCategories and prints attribute keys — resolves all
   §7 `?` items in one run. (Mirrors the existing leaderboard `inspect`.)
2. **Impl**: `MetadataConfig` + `ASCClient+Metadata` + `Reconciler` extension +
   `main.swift` wiring + tests (mirror `ReconcilerIAPTests`). Screenshots
   excluded.
