# ASC IAP extension — Phase 1 proposal

**Issue**: #200
**Author**: Developer (Track C v2, dispatched by Leader)
**Date**: 2026-06-02
**State**: PROPOSAL_DRAFT — awaiting Leader review

---

## 0. Recommendation (TL;DR)

**Phase 1 is GO** for unblocking v2.5 TestFlight. The ASC API surface for IAP localization + review note + family-sharing + pricing exists in Apple's public Connect API v1 (confirmed via authoritative OpenAPI-derived SDKs — see §3). Implementation fits the existing ASCRegister module shape (`Config.swift` → `Reconciler` → `ASCClient` → `plan`/`apply`). LOC delta ~ 550 added across 3 new files + ~ 60 lines in Config.swift.

**One non-trivial deviation from the dispatch brief**: the brief assumed a `priceTier: Int` model. Apple **removed tiered pricing** in the v2 IAP API — pricing is now expressed as a `inAppPurchasePriceSchedules` with `baseTerritory` + per-territory `manualPrices` referencing concrete `inAppPurchasePricePoints`. See §3.4 + §4.

---

## 1. Phase 1 scope — IAP product metadata

Target product: `com.wei18.sudoku.iap.remove_ads` (NON_CONSUMABLE).

Fields driven by ASCRegister in Phase 1:

| Field | Source of truth | ASC resource |
|---|---|---|
| `name` (reference name) | `Config.swift` `IAPProduct.referenceName` | `inAppPurchases` attribute |
| `reviewNote` | `Config.swift` `IAPProduct.reviewNotes` | `inAppPurchases` attribute |
| `familySharable: Bool` | `Config.swift` `IAPProduct.familyShareable` | `inAppPurchases` attribute |
| Per-locale `name` | xcstrings `iap.remove_ads.name` per locale | `inAppPurchaseLocalizations` |
| Per-locale `description` | xcstrings `iap.remove_ads.description` per locale | `inAppPurchaseLocalizations` |
| Base territory + price | `Config.swift` `IAPProduct.basePrice` (territory + pricePointId) | `inAppPurchasePriceSchedules` (Phase 1.b — see §1.1) |

Locales (7, from `ai-translated-localization` skill): `en`, `zh-Hant`, `ja`, `zh-Hans`, `es`, `th`, `ko` → mapped to ASC codes via existing `Config.ascLocaleCode(_:)` (`Config.swift:101-112`).

**Phase 1 is split into two waves** to derisk pricing:

- **1.a (unblocks v2.5)**: localizations + reviewNote + familySharable. These four alone resolve "缺少元資料" / `MISSING_METADATA` for products that already have a price set manually in ASC.
- **1.b (immediately after)**: pricing schedule (base territory + price point ID). Optional for v2.5 if the product already has a manual price; required if we ever re-create the product.

If user already manually set Remove Ads to USD 1.99 in ASC web UI, **1.a alone unblocks TestFlight**. The dispatch brief lumped them together; recommend Leader splits the merge into two PRs.

### 1.1 Explicitly NOT in Phase 1

| Excluded | Reason | Phase |
|---|---|---|
| Review screenshot upload | Multipart + asset-token state machine; meaningful complexity | Phase 2 |
| `inAppPurchaseAvailabilities` (territory inclusion/exclusion) | Remove Ads ships worldwide; default availability is fine for v2.5 | Phase 2 (if we ever restrict) |
| Promotional images / offer codes | Not requested | Phase 2/3 |
| App-level metadata (description, keywords, screenshots, age rating) | Per issue #200 §"Scope (candidate)" item 3 | Phase 3 (separate issue) |
| TestFlight / build submission | Per issue #200 — out of scope | — |

---

## 2. Current ASCRegister surface (snapshot)

Files in `Packages/SudokuKit/Sources/ASCRegister/` (read 2026-06-02):

- `main.swift` (363 LOC) — argv parsing + `validate` / `plan` / `apply` / `inspect` subcommands, dispatches via top-level `await ASCRegisterCLI.run()`.
- `ASCClient.swift` (336 LOC) — actor; JWT-signed REST client. Defines `Auth`, `Mode { .plan, .apply }`, `mutate(method:path:body:)`, `getResource(path:)`, `getCollection(path:)`. Uses raw `[String:Any]` JSON bodies (no Codable). Plan-mode short-circuits mutations and returns stub `APIResource`.
- `ASCClient+Achievements.swift` — split out to honour swiftlint `type_body_length`. Phase 1 should mirror by adding `ASCClient+IAP.swift`.
- `Config.swift` (217 LOC) — static enum with `leaderboards: [LeaderboardConfig]` + `achievements: [AchievementConfig]` + `ascLocaleCode(for:)` mapping.
- `Reconciler.swift` (209 LOC) — pure function `plan(config:strings:remote:) -> [Action]`. `Action` enum lists every create/update/unchanged variant. `RemoteState` indexed by vendorId / `(vendorId, locale)`.
- `XCStringsParser.swift` + `Strings/` — JSON parser for `.xcstrings`.
- `JWT.swift` — ES256 token signer.

Auth pattern: `--key <p8 path> --key-id <id> --issuer <id> --app-id <id>`; client `init` takes a PEM string read from the .p8 path (`main.swift:111-114`).

Retry / error-decode loop: `.claude/workflows/asc-apply-round.js` runs `swift run --package-path ... ASCRegister apply <creds>`, captures ENTITY_ERROR codes, suggests Config.swift patches. Known recipes for GC errors (#17, #19, #22, #24, #26, #31, #37, #40) live in the `KNOWN_RECIPES` map at workflow line 76-112; **Phase 1 will add IAP-specific entries here as ASC surfaces them**.

`mise.toml`: not present at repo root (the dispatch brief assumed it). The asc-apply-round workflow drives `swift run` directly, no mise indirection.

---

## 3. ASC API surface for Phase 1

**Reference source**: spaceship's `connect_api/models` directory does **not** include any IAP model (verified 2026-06-02 via `gh api repos/fastlane/fastlane/contents/spaceship/lib/spaceship/connect_api/models`). Spaceship's IAP support (`spaceship/lib/spaceship/tunes/iap*.rb`) targets the **legacy iTunes Connect private API**, not Apple's public ASC Connect REST API. The dispatch brief's primary reference is therefore unusable for Phase 1.

Authoritative substitute used: **`aaronsky/asc-swift`** (auto-generated from Apple's official ASC OpenAPI spec, CreateAPI tool). Cross-confirmed against `MortenGregersen/Bagbutik` (same OpenAPI source). Both publish under MIT-style licenses; we are reading API shape only, not vendoring code.

### 3.1 Read current IAP state (Phase 1)

```
GET /v1/apps/{appId}/inAppPurchasesV2
  ?filter[productId]=com.wei18.sudoku.iap.remove_ads
  &include=inAppPurchaseLocalizations,iapPriceSchedule
  &fields[inAppPurchases]=name,productId,reviewNote,familySharable,state,inAppPurchaseLocalizations,iapPriceSchedule
  &fields[inAppPurchaseLocalizations]=locale,name,description,state
```

Source: `aaronsky/asc-swift` — `Sources/AppStoreAPI/Generated/Paths/PathsV1AppsWithIDInAppPurchasesV2.swift` (the `get(...)` function with all `Fields*` enums, lines ~20-180).

Response includes the IAP `id` (we'll need it for subsequent writes) and all localizations + price schedule via `included[]`.

### 3.2 Read a single IAP (alternative / by-id)

```
GET /v1/inAppPurchases/{id}      ← does NOT exist in v2; v2 uses /v1/inAppPurchasesV2/{id}
```

⚠️ Brief assumed `GET /v1/inAppPurchases/{id}`. asc-swift exposes `/v1/inAppPurchasesV2/{id}` for v2 products. Reading by listing under app (§3.1) is simpler for our single-product Phase 1 — we never need to GET by id since we discover by `filter[productId]`.

### 3.3 Localization create / update

```
POST  /v1/inAppPurchaseLocalizations
PATCH /v1/inAppPurchaseLocalizations/{id}
GET   /v1/inAppPurchaseLocalizations/{id}        # rarely needed if §3.1 includes them
DELETE /v1/inAppPurchaseLocalizations/{id}
```

Source: `aaronsky/asc-swift` — `Sources/AppStoreAPI/Generated/Paths/PathsV1InAppPurchaseLocalizations.swift` + `...WithID.swift`.

POST body shape (mirrors GC localization pattern in our existing `ASCClient.createLeaderboardLocalization`, `ASCClient.swift:143-163`):

```json
{
  "data": {
    "type": "inAppPurchaseLocalizations",
    "attributes": {
      "locale": "en-US",
      "name": "Remove Ads",
      "description": "Remove all banner and interstitial ads forever."
    },
    "relationships": {
      "inAppPurchaseV2": { "data": { "type": "inAppPurchases", "id": "<iap-id>" } }
    }
  }
}
```

PATCH body (no `relationships`, only mutable attributes):

```json
{
  "data": {
    "type": "inAppPurchaseLocalizations",
    "id": "<loc-id>",
    "attributes": { "name": "...", "description": "..." }
  }
}
```

The `Fields` enum on the GET path confirms exactly four mutable attributes: `name`, `locale`, `description`, `state` (`state` is read-only; transitions are server-side).

### 3.4 Pricing — IMPORTANT correction to brief

The dispatch brief assumed:

```swift
let priceTier: Int  // or territory-specific
```

**This model is obsolete.** Apple's v2 IAP API replaced tier integers with **price points** (concrete USD-anchored amounts) + **schedules** (when each price takes effect, per territory).

Phase 1.b creates a one-shot price schedule:

```
POST /v1/inAppPurchasePriceSchedules
```

Source: `aaronsky/asc-swift` — `Sources/AppStoreAPI/Generated/Paths/PathsV1InAppPurchasePriceSchedules.swift`.

Body shape (derived from `InAppPurchasePriceScheduleCreateRequest` schema; needs one-time verification against Apple's docs by `inspect` mode on first apply):

```json
{
  "data": {
    "type": "inAppPurchasePriceSchedules",
    "relationships": {
      "inAppPurchase": { "data": { "type": "inAppPurchases", "id": "<iap-id>" } },
      "baseTerritory": { "data": { "type": "territories", "id": "USA" } },
      "manualPrices": {
        "data": [{ "type": "inAppPurchasePrices", "id": "<temp-id-1>" }]
      }
    }
  },
  "included": [{
    "type": "inAppPurchasePrices",
    "id": "<temp-id-1>",
    "attributes": { "startDate": null },
    "relationships": {
      "inAppPurchasePricePoint": {
        "data": { "type": "inAppPurchasePricePoints", "id": "<price-point-id>" }
      }
    }
  }]
}
```

`<price-point-id>` is looked up via:

```
GET /v1/inAppPurchases/{id}/pricePoints?filter[territory]=USA
```

…to find the USD 1.99 price point's id. (Apple no longer lets us say "tier 2"; we must reference a concrete pricePoint resource.)

⚠️ **UNCONFIRMED until first `apply`**: the exact shape of the `included[]` nesting for `manualPrices`. asc-swift's body type is a generated `InAppPurchasePriceScheduleCreateRequest` whose Codable layout I have not fetched. **Recommendation**: implement, run `plan` first to dump the request body, then run `apply` once and let `asc-apply-round.js` decode any `ENTITY_ERROR` — this is the same iterative pattern that resolved 8 GC unknowns in #17/#19/#22/#24/#26/#31/#37/#40.

### 3.5 IAP root attributes (familyShareable, reviewNote)

⚠️ asc-swift's `PathsV1InAppPurchasesV2.swift` / `...WithID.swift` was not fetched in this round (token budget). The GET fields enum (§3.1) lists `reviewNote` + `familySharable` as readable + writeable attributes on the `inAppPurchases` resource. The PATCH endpoint path is by reasonable inference:

```
PATCH /v1/inAppPurchases/{id}      ← NEEDS one-shot verification via `inspect`
```

Body:

```json
{
  "data": {
    "type": "inAppPurchases",
    "id": "<iap-id>",
    "attributes": {
      "reviewNote": "This IAP removes banner ads only. Test by tapping 'Remove Ads' in Settings > Pro.",
      "familySharable": true
    }
  }
}
```

**Open question 1** (§9): confirm the PATCH path on first round. The asc-swift directory listing showed `PathsV1AppsWithIDInAppPurchases.swift` (legacy v1) and `PathsV1AppsWithIDInAppPurchasesV2.swift` but I have not confirmed whether `/v1/inAppPurchases/{id}` PATCH exists for v2 products. Add `ASCRegister inspect --iap <product-id>` (mirror of existing leaderboard inspect, `main.swift:280-313`) as round-0 step before first apply.

---

## 4. Config.swift Phase 1 schema sketch

Targeting style + tone of existing GC config (`Config.swift:65-86`). Goes under the existing `internal enum Config { ... }` body, after `achievements`:

```swift
// MARK: - In-App Purchases (Phase 1 — issue #200)

/// v2.5 Remove Ads IAP. Must equal the `productID` constant in
/// `Packages/AppMonetizationKit/Sources/IAPStoreKit2/...` — enforce via
/// ConfigConsistencyTests once the IAP product constant exists there.
internal static let iaps: [IAPProduct] = [
    IAPProduct(
        productId: "com.wei18.sudoku.iap.remove_ads",
        referenceName: "Remove Ads v1",
        kind: .nonConsumable,
        familyShareable: true,
        reviewNote: """
            This non-consumable IAP removes banner and interstitial ads app-wide.
            Test by purchasing in Settings → Pro → Remove Ads. After purchase,
            ads should not appear anywhere in the app.
            """,
        // Phase 1.b — see §3.4. Nil for 1.a if price already set in ASC web UI.
        basePrice: IAPBasePrice(
            territoryId: "USA",
            // Price point id resolved on first `plan`; logged for the user
            // to paste back in the next round. Avoids hardcoding Apple's
            // opaque id system.
            usdPricePointId: nil
        )
    )
]

internal struct IAPProduct: Sendable, Equatable {
    internal let productId: String        // e.g. "com.wei18.sudoku.iap.remove_ads"
    internal let referenceName: String    // internal ASC label
    internal let kind: IAPKind
    internal let familyShareable: Bool
    internal let reviewNote: String
    internal let basePrice: IAPBasePrice?

    /// Per-locale strings live in the xcstrings catalog, keyed by
    /// `iap.<short>.name` / `iap.<short>.description`.
    internal var shortId: String {
        // strips the "com.wei18.sudoku.iap." prefix
        productId.replacingOccurrences(of: "com.wei18.sudoku.iap.", with: "")
    }
    internal var nameKey: String { "iap.\(shortId).name" }
    internal var descriptionKey: String { "iap.\(shortId).description" }
}

internal enum IAPKind: String, Sendable, Equatable {
    case nonConsumable    = "NON_CONSUMABLE"
    case consumable       = "CONSUMABLE"
    case nonRenewingSub   = "NON_RENEWING_SUBSCRIPTION"
}

internal struct IAPBasePrice: Sendable, Equatable {
    /// ISO country code expected by ASC `territories.id` (e.g. "USA" — see
    /// asc-swift territory enum). Phase 1 uses USA as the anchor; Apple
    /// auto-converts to other territories via `automaticPrices`.
    internal let territoryId: String
    /// Apple's opaque pricePoint id (e.g. "eyJzIjoiNz..."). Looked up via
    /// GET /v1/inAppPurchases/{id}/pricePoints?filter[territory]=USA on
    /// first `plan`; user then commits the resolved id back here.
    internal let usdPricePointId: String?
}
```

Locale code mapping reuses `Config.ascLocaleCode(_:)` unchanged — IAP localizations and Game Center share the same ASC locale catalogue (e.g. `en-US`, `zh-Hant`, `ja`, `es-ES`, `th-TH`, `ko-KR`).

---

## 5. Reconciler + Actions sketch

Extend `Action` enum (`Reconciler.swift:16-49`) with IAP variants — same shape as achievement variants:

```swift
// IAP root (PATCH only — Phase 1 does NOT create IAP products; user
// already created Remove Ads in ASC web UI per current state)
case updateIAP(existingId: String, IAPProduct)
case iapUnchanged(id: String)

// IAP localization
case createIAPLocalization(productId: String, locale: String, name: String, description: String)
case updateIAPLocalization(localizationId: String, locale: String, name: String, description: String)
case iapLocalizationUnchanged(productId: String, locale: String)

// Pricing (Phase 1.b)
case createIAPPriceSchedule(productId: String, territoryId: String, pricePointId: String)
case iapPriceScheduleUnchanged(productId: String)
```

`RemoteState` gains:

```swift
internal var iaps: [String: String]  // productId → ASC id
internal var iapLocalizations: [LocalizationKey: String]  // (productId, ascLocale) → loc id
internal var iapPriceSchedules: [String: String]  // productId → schedule id
```

`Reconciler.plan` adds a third phase after achievements:

```swift
actions.append(contentsOf: planIAPs(config: config, strings: strings, remote: remote))
```

`planIAPs` mirrors `planAchievements` structurally — for each `IAPProduct`:
1. If `remote.iaps[productId]` exists → emit `updateIAP` (we always PATCH because PATCH is idempotent + cheap, same as `updateLeaderboardLocalization` policy at `Reconciler.swift:131-136`).
2. For each target locale with both `name` + `description` strings present in xcstrings, emit create or update.
3. If `basePrice` non-nil and `remote.iapPriceSchedules[productId]` absent → emit `createIAPPriceSchedule`.

**Phase 1 intentional gap**: we do NOT `createIAP`. The user already created `com.wei18.sudoku.iap.remove_ads` via web UI; round-1 only fills in metadata. If the IAP is missing in ASC, plan/apply errors out with a clear message ("IAP product not found — create it in ASC web UI first"). This matches the brief's "Phase 1 unblocks v2.5" framing and avoids needing the `POST /v1/inAppPurchasesV2` body shape.

---

## 6. CLI subcommand UX

Mirror existing `plan|apply|inspect`:

```
ASCRegister iap plan      --key ... --key-id ... --issuer ... --app-id ... --xcstrings ...
ASCRegister iap apply     --key ... --key-id ... --issuer ... --app-id ... --xcstrings ...
ASCRegister iap inspect   --key ... --key-id ... --issuer ... --app-id ... --product <productId>
```

Routing in `main.swift` `run()` switch (`main.swift:35-50`):

```swift
case "iap":
    let subSub = rest.first ?? ""
    let rest2 = Array(rest.dropFirst())
    switch subSub {
    case "plan":    try await runIAPRemote(args: rest2, mode: .plan)
    case "apply":   try await runIAPRemote(args: rest2, mode: .apply)
    case "inspect": try await runIAPInspect(args: rest2)
    default:        printIAPUsage(); exit(2)
    }
```

`asc-apply-round.js` reuse: the workflow takes `credentialsArgs` as opaque string; it already runs `swift run ... ASCRegister <mode> <args>`. Pass `mode: "plan"` and prepend `iap` to the argv:

```
credentialsArgs: "iap --key $HOME/.../ASC.p8 --key-id ABC ..."
```

The workflow's `swift run --package-path ${repo}/${packagePath} ASCRegister ${mode} ${credentialsArgs}` line composes correctly because `${mode}` is `plan` and `${credentialsArgs}` starts with `iap`. **Minor wrinkle**: the workflow logs `ASCRegister ${mode}` which would say "ASCRegister plan" but actually runs "ASCRegister plan iap …" — order is wrong. Fix: invoke with `mode: "iap plan"` OR add a small `subcommand` arg to the workflow. Recommend the latter as a one-line workflow change in the Phase 1 PR.

Add IAP entries to `KNOWN_RECIPES` (`asc-apply-round.js:76-112`) as ENTITY_ERROR codes surface — e.g. `LOCALE_INVALID`, `MISSING_METADATA`, `INVALID_PRICE_POINT`, `IAP_NOT_FOUND`. Empty at Phase 1 start; populated over the first few rounds.

---

## 7. Phase 1 LOC estimate

| Where | Lines added | Notes |
|---|---|---|
| `Config.swift` | ~ 60 | `iaps` array + `IAPProduct` / `IAPKind` / `IAPBasePrice` structs + 1-2 doc comments |
| `ASCClient+IAP.swift` (new) | ~ 220 | Mirror `ASCClient+Achievements.swift`: list, create-localization, update-localization, patch-IAP, create-price-schedule, list-price-points |
| `Reconciler.swift` (additions) | ~ 90 | `planIAPs(...)` + extend `Action` + extend `RemoteState` |
| `main.swift` (additions) | ~ 70 | `iap` subcommand dispatch + `runIAPRemote` + `runIAPInspect` + IAP execute switch |
| `Strings/iap-strings.xcstrings` (new) | ~ 80 (data) | 1 product × 2 keys × 7 locales = 14 entries; not Swift LOC but counts toward review surface |
| Test additions (`Tests/ASCRegisterTests/IAPReconcilerTests.swift`) | ~ 130 | Mirror existing `AchievementReconcilerTests` shape (create / update / unchanged / locale-mapping cases) |
| `asc-apply-round.js` (workflow tweak) | ~ 10 | New optional `subcommand` arg ("iap" vs "" default) |
| **Total Swift added** | **~ 440** | |
| **Total review surface** (Swift + xcstrings + workflow) | **~ 530** | |

Well above the 50-LOC Code Reviewer threshold (per `feedback-code-reviewer-rule-is-or-not-and`); CR subagent is mandatory on the Phase 1 implementation PR.

---

## 8. Phase 2 / 3 deferral notes

- **Phase 2 — review screenshot upload**: `inAppPurchaseAppStoreReviewScreenshots` resource uses Apple's multipart asset-token state machine (`assetToken`, `uploadOperations`, `assetDeliveryState` per `FieldsInAppPurchaseAppStoreReviewScreenshots` enum, §3.1). Needs `PUT` to a per-chunk URL Apple returns, then a finalisation `PATCH`. Distinct complexity class from Phase 1's flat JSON:API writes — deferred to its own issue.
- **Phase 3 — app-level metadata** (description, keywords, marketing URLs, support URLs, age rating): per issue #200 §"Scope (candidate)" item 3, separate from IAP and tracked separately. Requires `appStoreVersions` + `appStoreVersionLocalizations` + `ageRatingDeclarations` resources. Larger schema; defer until Phase 1 is working in production.

---

## 9. Risk + rollback

- **`plan` mode**: dry-run prints every request body before any write, matching existing GC flow (`ASCClient.swift:223-227`). First Phase 1 round MUST be plan-only; second round apply.
- **No automated rollback**: an apply that PATCHes wrong values must be reverted manually via ASC web UI. Same as current GC posture; acceptable for low-frequency mutations on 1 product.
- **Pre-apply sanity**: run `ASCRegister iap inspect --product com.wei18.sudoku.iap.remove_ads` before first apply to capture Apple's current attribute names + the IAP's ASC id + existing localization ids. Stores the truth-on-the-ground that the brief's "spaceship reference" cannot, given spaceship has no IAP v2 model.
- **Sandbox tester smoke test**: after first successful apply, run a sandbox purchase via TestFlight (per `asc-ops-handoff` skill) to confirm StoreKit2 reads the new localization. This is the only end-to-end signal that the metadata actually flows from ASC → device.
- **Credential hygiene**: identical to GC pattern — `asc-apply-round.js:65-72` already redacts `--key/--key-id/--issuer/--app-id` flags from any logged stdout, applies to IAP runs unchanged.

---

## 10. Open questions for Leader

1. **Confirm PATCH path for IAP root attributes** (`reviewNote`, `familySharable`). asc-swift directory listing showed `PathsV1AppsWithIDInAppPurchasesV2.swift` exists, but the `WithID.swift` PATCH file for IAP-v2 was not opened this round (token budget). Likely path: `PATCH /v1/inAppPurchases/{id}` (carrying over from v1) — to be confirmed by one round of `inspect` + first `plan` output. Acceptable to discover via the existing `asc-apply-round` retry loop.

2. **Confirm `inAppPurchasePriceSchedules` request body nesting**. asc-swift's generated Codable body type (`InAppPurchasePriceScheduleCreateRequest`) was not unwrapped. The §3.4 sketch follows JSON:API `included[]` conventions but the exact key names (`manualPrices` as relationship name?, or as nested object?) need first-apply confirmation. Plan-mode dry-run will surface the gap before any live write.

3. **Phase 1.a vs 1.b split decision**. Recommendation: ship 1.a (localizations + reviewNote + familySharable) as PR #1 since it alone resolves `MISSING_METADATA` if Remove Ads already has a manual price set. Ship 1.b (pricing schedule) as PR #2 once 1.a lands. Defer to Leader.

4. **xcstrings file location**. New `Strings/iap-strings.xcstrings` lives alongside `Strings/gc-strings.xcstrings`? Or merged into one catalog? Recommendation: keep separate — different review audiences, different translator briefs. Matches the precedent set by GC having its own catalog.

5. **Product creation policy**. Phase 1 assumes the IAP product itself already exists in ASC. If a future scenario needs ASCRegister to CREATE the IAP (e.g. recreating after deletion), that's a separate sub-phase. Confirm we never re-create; if we might, add `POST /v1/inAppPurchasesV2` to the Phase 1 scope (~ +60 LOC).

6. **Test fixture for `IAPReconcilerTests`**. The existing `AchievementReconcilerTests` use in-memory `RemoteState` literals — pattern is straightforward. No blocker; flagged only because Phase 1 test count (~ 130 LOC) is non-trivial.

---

## 11. References (for Leader's audit)

- `Packages/SudokuKit/Sources/ASCRegister/main.swift` — argv router, lines 35-50 (subcommand switch), 103-175 (`runRemote`), 280-313 (`runInspect`).
- `Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift` — actor + `mutate` envelope, lines 87-181 (leaderboard methods to mirror), 187-203 (auth header).
- `Packages/SudokuKit/Sources/ASCRegister/Reconciler.swift` — `Action` enum + `plan`, lines 16-49, 89-98 (planning entrypoint), 149-196 (`planAchievements` — closest structural sibling to `planIAPs`).
- `Packages/SudokuKit/Sources/ASCRegister/Config.swift` — `Config` enum + `LeaderboardConfig` / `AchievementConfig` value types, lines 17-216; `ascLocaleCode` mapping at 101-112.
- `.claude/workflows/asc-apply-round.js` — retry / decode loop, lines 76-112 (`KNOWN_RECIPES`), 142-158 (run phase).
- `aaronsky/asc-swift` (GitHub) — `Sources/AppStoreAPI/Generated/Paths/PathsV1AppsWithIDInAppPurchasesV2.swift` (read fields + filters), `PathsV1InAppPurchaseLocalizations.swift` + `PathsV1InAppPurchaseLocalizationsWithID.swift` (write paths), `PathsV1InAppPurchasePriceSchedules.swift` (pricing path).
- **Negative result**: `fastlane/fastlane` spaceship `connect_api/models/` has no IAP file (verified via `gh api repos/fastlane/fastlane/contents/...`). spaceship's `tunes/iap*.rb` targets legacy iTunes Connect API and is not usable for Phase 1.
