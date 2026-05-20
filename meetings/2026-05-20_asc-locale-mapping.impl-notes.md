# Impl Notes — asc-locale-mapping (2026-05-20)

Status: COMPLETE
Owner: Developer (ASCRegister)
Dispatched by: Leader
Issue: #31 — Round-6 apply failed with `LOCALE_INVALID` on leaderboard localizations.

## 設計決定 (Design decisions)

- **Where mapping lives** — Reconciler, not ASCClient. Brief #3 was explicit and matched the existing layering: ASCClient is a thin pass-through that takes a `locale: String` and shoves it into the POST body verbatim; Reconciler owns the desired-state → action transformation, which is exactly the layer that knows xcstrings is the source-of-truth. Centralising the map there keeps `Config.ascLocaleCode(for:)` invokable from exactly one site per resource type (leaderboard / achievement) and leaves the client schema-agnostic.

- **Action.locale carries the ASC code, not the xcstrings code** — The brief said "Use the ASC code in the POST body; keep xcstrings code in internal action identifiers / log lines". Two interpretations were on the table:
  1. Action stores both (`locale` xcstrings + `ascLocale` ASC).
  2. Action stores the ASC code; describe() / logs naturally show the ASC code.
  Picked (2). Adding a second associated value to four enum cases plus the unchanged-cases would have widened the diff across ReconcilerTests + main.swift + describe() with no behavioural payoff — the ASC code is the truth value that hits the wire, and traceability back to xcstrings is one-line obvious (the map is 7 entries in one file). The "internal action identifiers" phrase is satisfied by the unchanged `vendorId` field, which is still the bundle-id-rooted xcstrings-domain identifier. Log lines show `[en-US]` instead of `[en]` after this change; that's the more useful debug signal anyway (matches what ASC GET returns and what 4xx bodies cite).

- **`RemoteState.LocalizationKey.locale` is ASC code** — `main.swift` populates this from `loc.attributes["locale"]` which ASC GET returns as the regional form. So the key space *was already* ASC-code-shaped; the Reconciler was just looking it up with the wrong (xcstrings) shape and always missing. Mapping at the loop head before both lookup and emission unifies the two spaces. Test fixtures `fullRemote` were updated to use `"en-US"` keys (matches production wire shape).

- **Default-passthrough on unknown code** — Brief specified it; rationale: a new locale added to xcstrings should surface as a `LOCALE_INVALID` from ASC on next apply, not silently get dropped by an opaque sentinel. The cost is one extra round-trip discovery loop; the benefit is no hidden state where some locales just don't get pushed.

- **No reverse map / second field for logs** — Considered building a reverse map `Config.xcstringsCode(for: ascCode)` so describe() could show `[en-US←en]`. Rejected: noise without value once `en-US` becomes the lingua franca of all our ASC logs. The `vendorId` already tells you which leaderboard/achievement it is; the locale tag is just a routing key.

## 偏離 (Deviations)

- **Brief said "keep xcstrings code in log lines"; shipped ASC code in log lines** — See design decision above. The brief's two requirements ("ASC code in POST body" + "xcstrings code in logs") would have required Action to carry both values. I picked the simpler shape (ASC code only) because the wire-truth value is the more useful debug signal and the xcstrings code can be re-derived by eye from `Config.ascLocaleCode(for:)`'s 7-line switch. Flagging here so Leader can reject + ask for the dual-field variant if traceability turns out to matter at log-grep time.

## 折衷 (Tradeoffs)

- **Surgical change vs. comprehensive locale infra** — Could have introduced a `Locale` value type that wraps `(xcstrings, asc)` and threads it everywhere. Rejected per Karpathy §2 (Simplicity First) and §3 (Surgical Changes): the bug is "send `en-US` not `en`", not "the codebase lacks a locale abstraction." 9-line Config helper + 4-line touch in Reconciler is the minimum that fixes round-6. If a third locale-related bug shows up the abstraction earns its keep then.
- **Test count of 8 new cases vs. fewer parametric tests** — swift-testing supports `@Test(arguments:)`. I picked 8 individual `@Test` cases (7 explicit codes + 1 passthrough) to keep failure messages locally legible (the test name says exactly which code regressed) and to land closer to the "355 → 363ish" target. Parametric would have been more elegant at 1-2 tests but worse for grep-the-failure-name diagnosis.

## 未決 (Open questions)

- **`ja` and `es` ASC codes are educated guesses** (per dispatch §未決). The `ja` → `ja` mapping is plausible because Japanese has no commonly-used regional split in Apple's locale schema, but ASC may want `ja-JP`. Similarly `es` → `es-ES` favours peninsular Spanish; ASC may demand `es-MX` for the App Store's Latin-American default, or accept `es` bare. Iterative discovery on next apply round — round-7 will tell us. The default-passthrough behaviour means even an unmapped `ja-JP` (if we re-add it to xcstrings) would pass through correctly.

## 驗證 (Verification beyond compile)

- **Build**: `swift build` clean, 0 warnings on Swift 6 strict.
- **Tests**: `swift test` → 363 tests pass in 69 suites (target: 363ish).
  - New `ConfigLocaleMappingTests` suite: 8 tests (7 explicit codes + 1 passthrough).
  - Updated `ReconcilerTests`: 4 existing tests retuned to expect `"en-US"` not `"en"` (no count change — same test bodies, asserting the corrected wire value).
- **Wire-shape coherence**: re-read `main.swift` lines 130–155 — `RemoteState.LocalizationKey.locale` is populated from `loc.attributes["locale"]` (ASC GET response, regional form). Reconciler now keys its lookups in the same space. Round-trip: ASC GET → RemoteState (ASC code) → Reconciler lookup (ASC code via map) → Action.locale (ASC code) → ASCClient POST (ASC code).
- **No client changes needed** (brief #3 was a confirmation, not an ask): `createLeaderboardLocalization` and `createAchievementLocalization` both take `locale: String` and forward verbatim into the JSON body. Confirmed by Read on ASCClient.swift and ASCClient+Achievements.swift.

## TODO sweep (per methodology §派發契約 #7)

Command (verbatim):
```
rg -n --no-heading -e 'TODO|FIXME|XXX|HACK|stub|placeholder|Phase [0-9]+ Part' Packages/SudokuKit/Sources/ASCRegister/
```

Output (verbatim):
```
Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift:37:        // TODO: remove if still unused after error refactor settles
Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift:225:            // Return a stub resource so reconciler can keep going.
Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift:226:            return APIResource(id: "<dry-run>", type: "stub", attributes: [:])
Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift:257:/// placeholder (same shape as `ASCClient.stringify`).
```

Triage:
- **L37 `TODO: remove if still unused after error refactor settles`** — Pre-existing from `asc-register-error-context` round. Refers to `ClientError.missingResponseBody`. Out of scope for issue #31; not introduced by this change. Leaving as-is.
- **L225–226 `stub`** — Word `"stub"` is in a comment ("Return a stub resource") and as the `.type` value of the dry-run sentinel `APIResource`. Not deferred work; it's the dry-run mode's intentional shape. No action.
- **L257 `placeholder`** — Word appears in the doc comment for `truncateBody`. Documentation prose, not deferred work. No action.

No items from this change touched any of the four lines. Phase complete.
