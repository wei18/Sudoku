# Impl Notes — ASC metadata follow-ups (#333) (2026-06-05)

Status: COMPLETE
Owner: Developer subagent
Dispatched by: Leader
Started: 2026-06-05

## 設計決定 (Design decisions)

- **Root cause of item 1 (version-loc always UPDATE) is NOT a missing drift
  comparison — it already exists** (`Reconciler+Metadata.swift`
  `planVersionLocalizations`, lines 233-244, present since #310/#332). The pure
  `idempotencyRoundTrip` test already passes when remote mirrors config
  byte-for-byte. The live non-convergence comes from a **trailing-newline
  mismatch**: `MetadataConfig.str()` (`MetadataConfig.swift:304-314`) computes a
  `trimmed` value only to test emptiness but **returns `raw`** — so block-scalar
  fields (`description`/`whats_new`/`promotional_text`) keep their terminating
  `\n`. Apply sends `"…\n"`; ASC stores+returns `"…"` (drops the trailing
  newline — confirmed by the #333 issue comment + `ascCharacterCount`'s existing
  "ASC doesn't count the trailing newline" note at `MetadataConfig.swift:368-387`).
  Snapshot reads back the trimmed value → `existing != desired` → UPDATE every
  run. appInfo-locs (`name`/`subtitle`: short single-line plain scalars, no
  trailing `\n`) and categories (no text) converge, exactly matching the issue's
  observation.

- **Fix chosen: normalize the trailing newline in the reconciler's drift
  comparison** (newline-insensitive on the single trailing terminator), the same
  semantics `ascCharacterCount` already uses. This is the "field-level drift
  comparison so a converged plan is a true no-op" item 1 asks for. Applied to
  BOTH version-loc and appInfo-loc drift for symmetry (appInfo URLs could in
  principle carry a block-scalar newline too). Comparison fields: version-loc =
  description / keywords / promotionalText / whatsNew / marketingUrl / supportUrl;
  appInfo-loc = name / subtitle / privacyPolicyUrl.

## 偏離 (Deviations)

- Issue item 1 phrasing implies adding a drift comparison that's absent. It is
  in fact present; the true gap is trailing-newline normalization. Implementing
  the normalization (not a redundant second comparison) — same end result the
  issue's success criterion (a) demands: zero `UPDATE version-loc` on unchanged
  content.

## 折衷 (Tradeoffs)

- **Where to normalize**: (A) fix `str()` to return `trimmed` at load;
  (B) normalize only in the reconciler drift comparison. Picked **B** (reconciler)
  to keep the change surgical to the drift path and avoid altering what apply
  SENDS (changing `str()` would also change the payload, a broader behavioral
  change with its own length-validation interactions — out of scope for a
  non-blocking quality follow-up). The reconciler comparison is the single place
  the issue's no-op criterion is measured.

## 偏離 (Deviations) — item 2 visibility

- **`createOrUpdateVersionLoc` / `createOrUpdateAppInfoLoc` widened
  `private static` → `internal static`** (`main.swift`, `ASCRegisterCLI`). The
  CREATE→PATCH 409 self-heal orchestration lived as a `private` helper,
  unreachable from the test target. To integration-test the REAL fallback path
  (POST → 409 dup → GET re-fetch → PATCH) offline rather than re-implementing the
  orchestration in the test, the two helpers are now `internal`. Minimal
  visibility widening, no logic change. `@testable import` then drives them
  through the URLProtocol stub.

## 設計決定 (Design decisions) — URLProtocol harness

- **`StubURLProtocol`** (test-only): a `URLProtocol` subclass with a per-test
  task-local queue of canned `(status, body)` responses keyed by an ordered
  match on `method + path-substring`. Registered on
  `URLSessionConfiguration.ephemeral` → injected via `ASCClient(session:)` +
  `baseURL: URL(string: "https://stub.local")`. Fully offline; no live ASC.
- **Auth**: a fresh in-test `P256.Signing.PrivateKey().pemRepresentation`
  (same pattern as `JWTTests`) so `JWT.sign` succeeds without any real key.
- Two integration tests: (1) `getAllPages` follows `links.next` across 2 pages
  and concatenates results; (2) `createOrUpdateVersionLoc` POST→409-dup→GET→PATCH
  self-heal issues exactly that request sequence and ends on the existing id.

## 未決 (Open questions)

- None load-bearing. `str()` returning `raw` looks like a latent bug but fixing
  it is out of #333 scope (would change sent payloads); left as-is, noted here.
