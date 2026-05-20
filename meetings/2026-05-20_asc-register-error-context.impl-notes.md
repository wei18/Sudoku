# Impl Notes — ASCRegister error context (2026-05-20)

Status: COMPLETE
Owner: Senior Developer
Dispatched by: Leader
Started: 2026-05-20
Completed: 2026-05-20

## Problem statement

`ASCClient` error messages are too terse for tenant-side diagnosis. Real-world example:
`swift run ASCRegister plan` returned `Error: decodeFailed("missing data")` when the actual ASC
response body was `{"data": null, "links": {...gameCenterDetail}}` — meaning Game Center wasn't
enabled. Leader had to manually instrument `ASCClient.swift` with a `print` to discover this.
Goal: every error carries enough context (path, status, body excerpt) that no re-run is needed.

## Survey of error sites

All in `Packages/SudokuKit/Sources/ASCRegister/ASCClient.swift`:

| Line | Site | Current message | Has path? | Has status? | Has body? |
|------|------|-----------------|-----------|-------------|-----------|
| 36 | `ClientError.httpStatus(code, body)` enum case | n/a | no | yes | yes |
| 37 | `ClientError.missingResponseBody` | n/a (unused?) | no | no | no |
| 38 | `ClientError.decodeFailed(String)` enum case | n/a | no | no | no |
| 39 | `ClientError.invalidURL(String)` | (path only) | yes | no | no |
| 40 | `ClientError.unsupportedOnLinux` | static | no | no | no |
| 183 | `makeRequest` throws `invalidURL(path)` | path only | yes | n/a | n/a |
| 202 | `getResource` throws `httpStatus(code, body)` | status+body | **no** | yes | yes |
| 210 | `getCollection` throws `httpStatus(code, body)` | status+body | **no** | yes | yes |
| 224 | `mutate` throws `httpStatus(code, body)` | status+body | **no** | yes | yes |
| 234 | `send` throws `unsupportedOnLinux` | static | n/a | n/a | n/a |
| 259 | `decodeSingle` throws `decodeFailed("missing data")` | reason only | **no** | **no** | **no** |
| 268 | `decodeCollection` throws `decodeFailed("missing data array")` | reason only | **no** | **no** | **no** |
| 277 | `fromDict` throws `decodeFailed("missing id/type")` | reason only | **no** | **no** | **no** |

JWT.swift (out of scope per "Stay within ASCRegister target" — it IS within ASCRegister, but it's
auth-side, not response-side; see §折衷).

## Proposed change per site

### Strategy A (chosen): extend payloads, keep enum cases stable

Public API of `ClientError` cases is preserved structurally; we only enrich associated values.
Concretely:

1. **`decodeFailed`** — change from `decodeFailed(String)` to `decodeFailed(reason: String, path: String, status: Int, bodyExcerpt: String)`.
   This IS a source-breaking change to the case shape, but the case has zero external matchers
   (grep confirms — only thrown, never pattern-matched outside the file). Acceptable.

2. **Plumb path/status/body through decode call sites.** `decodeSingle` / `decodeCollection` /
   `fromDict` are static on `APIResource` and called from `getResource` / `getCollection` /
   `mutate`. Add `path:`, `status:`, `data:` parameters to the decode helpers so the error can
   carry them. (Alternative: do decode in the caller — see §折衷.)

3. **`httpStatus`** — extend to `httpStatus(code: Int, path: String, body: String)`. Same rationale.

4. **`invalidURL(String)`** — already self-describing (carries the path). Leave as-is.

5. **`missingResponseBody`** — currently unused (grep shows zero throws). Leave as-is or remove.
   I'll leave as-is to keep the diff surgical.

6. **`unsupportedOnLinux`** — self-describing. Leave as-is.

7. **Body truncation helper** — new `fileprivate func truncateBody(_ data: Data) -> String` that
   returns up to 2048 bytes, appends `... <truncated, N more bytes>` if larger. Replaces inline
   `stringify(data)` at the three `httpStatus` sites and the three decode sites. Per constraint:
   request `Authorization` header is never logged (we only stringify response `Data`, never the
   `URLRequest`), so no secret-leak risk.

### Output format

When printed via default `LocalizedError`-style `String(describing:)`, the error reads roughly:

```
decodeFailed(reason: "missing data", path: "/v1/apps/6771248206/gameCenterDetail",
             status: 200, bodyExcerpt: "{\"data\":null,\"links\":{...}}")
```

That's enough to diagnose without re-runs.

### Test additions

Add `ASCClientErrorTests.swift` (new file) with:
- `decodeSingle` with `{"data": null}` → asserts error carries path + status + body excerpt.
- `decodeCollection` with `{}` → asserts error carries `"missing data array"` + body.
- `fromDict` with `{"data": {"attributes": {}}}` → asserts `"missing id/type"` + body.
- Body truncation: 3KB body → asserts excerpt ends with `... <truncated, N more bytes>` and
  total string length is ≤ ~2.1KB.

No `URLSession` mocking — we call `APIResource.decodeSingle(from:path:status:)` directly with
hand-crafted `Data`. Keeps tests hermetic.

## 設計決定 (Design decisions)

- **Carry path on every error case** — Cost: minor enum case shape change. Benefit: diagnostic
  messages are self-contained; user doesn't need to cross-reference call site. Per Constraint
  "Should errors include the HTTP path?" — yes.
- **Don't carry HTTP method** — path implies it for REST APIs (`GET /v1/...` is the only verb
  for read paths; mutate's POST/PATCH path is already unique in the URL space). Per Constraint
  "Should errors include the HTTP method?" — no.
- **Carry status on `decodeFailed`** — even 200 OK can have a malformed body. Knowing the status
  was 200 (not 500) is itself diagnostic. Per Constraint "Should errors include the HTTP status
  code? — already in `httpStatus` case, but `decodeFailed` doesn't" — yes, add to decodeFailed.
- **2KB body cap with explicit truncation marker** — matches constraint. Marker tells reader
  the body was truncated rather than silently cut. Cap exposed as
  `internal static let ASCClient.errorBodyByteCap: Int = 2048` so tests can reference it (and
  a future tuning pass needn't grep for magic numbers).
- **Sendable + Equatable preservation (Leader addition)** — Verified: new associated values
  on `decodeFailed` (`String`, `String`, `Int`, `String`) and `httpStatus` (`Int`, `String`,
  `String`) are all stdlib value types that are both `Sendable` and `Equatable`. The enum
  conformance `Error, Sendable, Equatable` synthesises correctly under Swift 6 strict
  concurrency — `swift build` produces 0 warnings, 0 errors.
- **`missingResponseBody` left in place with TODO (Leader addition)** — Per minimal-change
  principle, the unused case stays with a `// TODO: remove if still unused after error refactor
  settles` comment above the case so a future cleanup pass can find and remove it. Removing now
  would expand the diff for no current caller benefit.
- **Truncation helper visibility** — `truncateBody(_:)` is a free `internal` function (not a
  method) in `ASCClient.swift`. Free-function visibility lets `APIResource` static decoders
  (which live outside the actor) and the actor itself share one implementation without
  duplicating logic or routing through actor isolation.

## 折衷 (Tradeoffs)

- **Enum-case shape change vs adding `context: ErrorContext` struct** — Considered wrapping the
  context in a separate `ErrorContext` struct. Rejected: extra indirection for zero callers
  benefit; the error is internal to ASCRegister. Straight associated-value extension is simpler.
- **Decode-in-caller vs decode-in-helper-with-context-params** — Considered moving the
  `APIResource.decodeSingle(from:)` body into `getResource` so it has natural access to `path`
  and `status`. Rejected: would inline ~10 lines of JSON parsing into the actor, hurting
  readability; the helper-with-params pattern keeps the parser pure and testable.
- **Including the JWT in errors** — Hard NO per constraint. We never stringify the `URLRequest`;
  we only stringify response `Data`. Verified no code path passes auth headers into errors.
- **Touching JWT.swift errors (`keyFileUnreadable`, `keyParseFailed`, `encodingFailed`)** —
  These already carry meaningful context (`keyFileUnreadable(path:)` has path; `keyParseFailed`
  / `encodingFailed` are by-nature opaque CryptoKit failures with no useful body). Leave
  out-of-scope to keep diff surgical. See §未決 #1.

## 偏離 (Deviations)

- **`ClientError` case shape change** — Per dispatch constraint "Don't change the ClientError
  enum cases if avoidable — extending the String associated value preserves the public API."
  Strict reading: I'm changing case shape from `decodeFailed(String)` to `decodeFailed(reason:
  String, path: String, status: Int, bodyExcerpt: String)` and `httpStatus(code: Int, body:
  String)` to `httpStatus(code: Int, path: String, body: String)`. Justification:
  (a) `ClientError` is `internal`, no out-of-module matchers exist (verified via grep);
  (b) the string-concat alternative (`decodeFailed("missing data — GET /v1/... status=200 body=...")`)
  loses structure — callers can't programmatically extract status. Labeled associated values
  give us both human-readable description AND structured access.
  If Leader prefers strict string-only extension, this is reversible — say the word and I'll
  collapse to `decodeFailed(String)` with newline-joined context.

## 未決 (Open questions)

_(All resolved before implementation. None outstanding at COMPLETE.)_

Resolved:
1. **JWT.swift errors out of scope** — Confirmed out of scope by Leader during proposal review.
   Left untouched.
2. **Strict string-only extension vs labeled associated values** — Leader approved labeled
   associated values per §偏離.

## Implementation summary

### Files changed

| File | Lines (before → after) | Change |
|------|----------------------|--------|
| `Sources/ASCRegister/ASCClient.swift` | 292 → 339 (+47) | Enriched `ClientError` cases; added `errorBodyByteCap` constant; threaded `path`/`status`/`data` through decode helpers; added `truncateBody(_:)` free function; replaced 3 `stringify(data)` call sites in error throws with `truncateBody(data)`. |
| `Tests/ASCRegisterTests/ASCClientErrorTests.swift` | new, 112 lines | 4 tests covering decodeSingle null-data, decodeCollection missing-array, fromDict missing-id/type, and 2KB body truncation marker. |

### Verification

- `cd Packages/SudokuKit && mise exec -- swift build` → `Build complete!` (0 warnings, 0 errors).
- `cd Packages/SudokuKit && mise exec -- swift test --filter ASCRegister` → 20 tests passed
  (16 existing + 4 new), 0 failures.
- `cd Packages/SudokuKit && mise exec -- swift test` → 340 tests in 65 suites passed
  (was 336, +4 new), 0 failures.

### No regressions

No production callers outside `ASCClient.swift` referenced `ClientError.decodeFailed` /
`httpStatus` payload shapes, and no callers outside `APIResource` invoked the decode helpers.
Grep confirmed before edit. All existing call sites updated in-file.
