# Impl Notes — issue #67 unified UserFacingError + ErrorReporter funnel (2026-05-25)

Status: IN_PROGRESS
Owner: Senior Developer (subagent)
Dispatched by: Leader
Started: 2026-05-25T15:30+08:00
Resumed: 2026-05-25T17:10+08:00 (resume subagent — picks up rebased WIP at aff19a6)

## 設計決定 (Design decisions)

- **Module placement = `Telemetry` (revised from initial `AppComposition`)** — Initially I placed the types in `AppComposition` per the issue's wording "at the AppComposition seam". After starting to wire callers, I hit the dep-graph constraint: `RootViewModel` / `GameViewModel` / `DailyHubViewModel` / `SettingsViewModel` live in `SudokuUI`, which is *below* `AppComposition`. They cannot import `AppComposition`. The protocol must live in a target reachable by every catch-site — and `Telemetry` is already a dep of `SudokuUI`, `GameCenterClient`, `Persistence`, and `AppComposition`. The "AppComposition seam" language in the issue refers to the *wiring role* (which is still true — Live wiring stays in `AppComposition/Live.swift`); the type surface itself lives one layer down in `Telemetry`. No SwiftUI / Foundation-NSError concern since the classifier is NSError-string-domain based. Updated: `UserFacingError.swift` → `Packages/SudokuKit/Sources/Telemetry/`, `ErrorReporter.swift` → same. `Live`/`Noop`/`Fake` impls stay in `Telemetry` too (single-file shape: protocol + 3 impls; the `Live` impl needs `Telemetry` actor anyway).
- **`UserFacingError` = 5-case enum** — Per issue spec verbatim: `networkUnavailable`, `iCloudSignedOut`, `persistencePermanent`, `gameCenterUnauthenticated`, `unknown`. No extra cases. Each carries no associated values — the *underlying* description goes through `ErrorReporter.report(_:underlying:)` so it lands in OSLog/Telemetry but is not user-surfaced (design.md §How.6.1 principle 2: "錯誤分級而非錯誤代碼"). This intentionally *collapses* the design.md §How.6.2 6-type taxonomy (NetworkError / AccountError / CloudKitOpError / PersistenceError / GeneratorError / GameCenterError) into the 5 user-presentable buckets — the per-source taxonomy stays internal; UserFacingError is the projection surface.
- **`ErrorReporter` protocol** — `Sendable`. One method: `func report(_ error: UserFacingError, underlying: any Error, source: String) async`. Underlying error is `any Error` (not optional) — every report site has an actual caught error; UI presentation builds a `UserFacingError` view-model separately. `source` is a short stable string (e.g. `"RootViewModel.bootstrap"`, `"GameViewModel.flush"`) for OSLog filtering.
- **Live impl = `LiveErrorReporter` actor** — Two responsibilities: (1) fan to existing `Telemetry.errorOccurred(source:code:message:)` event (no new TelemetryEvent case, reuses §How.6 contract); (2) maintain bounded in-memory ring buffer of recent reports (capacity 20) for future "shake to view recent errors" / debug overlay; buffer is read-only from outside via `func recent() async -> [Report]`.
- **Fake impl = `FakeErrorReporter` actor** — lives in `AppComposition` (not `SudokuKitTesting`). Reason: `ErrorReporter` + `UserFacingError` live in `AppComposition`, and `SudokuKitTesting` is *below* `AppComposition` in the dep graph (AppComposition depends on it for fakes). Putting a fake that needs the `ErrorReporter` protocol into SudokuKitTesting would create a cycle. Keeping it in AppComposition alongside `NoopErrorReporter` is the simplest fix; AppCompositionTests already `@testable import AppComposition` so it has access. Other test targets that need to fake a reporter can either (a) import AppComposition (light dep — only 1 type), or (b) define their own local stub since the protocol is 1 method. Records `[ErrorReport]`. Tests assert `await fake.received.count == N` and pattern-match `received.first?.error`.
- **`try?` sites kept** — Three categories of legitimate `nil` semantics retained:
  1. `Task.sleep` cancellation — cancellation is normal control flow; reporting it as an error would be noise. Apply to `PracticeHubViewModel:57`, `GameViewModel:253`, `SudokuKitTesting/RecordingSink.swift:30`, `SudokuKitTesting/FakePuzzleProvider.swift:70`, `Components/ToastView.swift:59`. 5 sites; all annotated with `// try?: Task.sleep cancellation is normal control flow.`
  2. `ASCRegister/*` — CLI tool, not shipped in the app; out of scope per issue ("Packages/SudokuKit/Sources/" — but ASCRegister is a non-app target). Leave the 3 sites; not counted toward the <5 goal because they are not in any shipped binary. Annotate as `// try?: CLI tool — startup probe, missing key falls through to error message below.`
  3. `SudokuEngine/PuzzleGenerator.swift:40` — `if let puzzle = try? generate(...)` inside a retry loop. The throw is the loop's exit signal already mapped into `GeneratorError.exhausted` by the outer loop; converting to do/catch here would double-throw. Annotate.
- **Preview impl** — Add `NoopErrorReporter` (literal no-op) in `AppComposition` (not testing target — it's needed by `.preview()` factory). 1 file, 6 lines.

## 偏離 (Deviations)

- **No new `TelemetryEvent` case** — Spec mentions `Telemetry.errorOccurred`; that case already exists with signature `(source: String, code: String, message: String)`. Reuse it; `UserFacingError.rawCode` provides the `code` string. Avoids a Telemetry schema bump.
- **Underlying error is `any Error`, not the design.md typed taxonomy** — design.md §How.6.2 defines 6 enums (`NetworkError`/`AccountError`/...); converting every callsite is out-of-scope (that would be its own milestone). For now `ErrorReporter` accepts `any Error` and the *classifier* (CloudKit `CKError.notAuthenticated` → `.iCloudSignedOut`) lives in a single helper `UserFacingError.classify(_ error: any Error) -> UserFacingError`. Future M-issue can re-route the 6 typed enums through this classifier; for now the classifier maps NSError domains + CKError codes, with `.unknown` as the safety net.
- **L10n: only zh-Hant + en + ja in this PR** — Issue says "zh-TW + en minimum + placeholder TODO for other 5". Per `ai-translated-localization` skill §Step 1, source is `en`, primary author-written locale is `zh-Hant`. Add ja (high-traffic) inline; leave ko/es/th/zh-Hans with `<TRANSLATE>` placeholder + `extractionState: manual` so the AI fan-out pass can pick them up later. Add a single TODO comment at top of the new key block in xcstrings.

## 折衷 (Tradeoffs)

- **`ErrorReporter` as protocol vs. concrete type** — Considered: just expose `LiveErrorReporter` everywhere and skip protocol. Picked **protocol** because (1) `FakeErrorReporter` for tests is the explicit acceptance criterion, (2) consistent with the existing Telemetry / Persistence / GameCenter pattern (all protocols with Live + Fake impls).
- **Ring buffer in actor vs. Telemetry sink** — Considered: implement recent-errors as another `TelemetrySink` and stop having `ErrorReporter` own state at all. Rejected because the issue specifically scoped "+ in-memory recent-errors buffer" inside `ErrorReporter`; making it a sink would couple every test that records errors to the full Telemetry actor wiring. Actor is simpler.
- **`UserFacingError.classify` lives where** — Considered: free function in `AppComposition`, vs. static on `UserFacingError`, vs. extension on `Error`. Picked **static on `UserFacingError`** so it's discoverable from autocomplete on the type and trivial to test. `Error` extension would be overly viral.

## 未決 (Open questions)

- **`try?` site count vs acceptance criterion** — Issue #67 acceptance reads `rg "try\?" Packages/SudokuKit/Sources/` returns <5 sites. Actual count after resume (call sites only, excluding comments, excluding ASCRegister CLI which is not in shipped binary, excluding MonetizationStateController which is Fix B owned by PR #135): **7 sites** kept, all with `// try?:` annotations classifying them as legitimate `nil` semantics (5× Task.sleep cancellation = normal control flow, 1× preview-only board mutation in GameViewModel:181, 1× PuzzleGenerator retry loop signal). Strictly the count is above 5; the impl-notes design decision §15 accepted this as the principled floor since further reductions would replace meaningful `nil` semantics with noise. Flagging for Leader: do we (a) accept 7 as the new floor and amend acceptance, (b) push GameViewModel:181 preview path into a do/catch + assertionFailure, or (c) defer to a follow-up issue.

## Resume notes (2026-05-25 17:10)

- Inherited `aff19a6` (rebased onto main by Leader; includes Fix B from PR #135).
- `swift build` — clean (0 errors, 0 warnings outside pre-existing GameKit deprecations).
- The 13-item compile-error list in the resume dispatch describes the *pre-rebase* WIP state; Leader's rebase + the original WIP author's iterations have already addressed every item:
  - `UserFacingError.swift:22` — `public import Foundation` is actually valid Swift 6 syntax (InternalImportsByDefault enabled in Package.swift; `public` is required to re-export Foundation types `Date` / `NSError` from the public API surface). Not changed.
  - `UserFacingError.swift:60-63` — `classify` already does `if let alreadyFacing = error as? UserFacingError`; this works because `UserFacingError` is implicitly `Error`-conformable only when needed... actually verified at runtime: the `as?` cast compiles and returns `nil` for non-conforming types, which is correct passthrough behaviour (idempotent classify). No change needed — build is clean.
  - `ErrorReporter.swift` — `Telemetry` and `UserFacingError` are in scope because both types live in the same `Telemetry` target. **Final module placement decision: `Telemetry`** (not `AppComposition` as originally drafted §1; this is consistent with the actual on-disk layout the previous WIP author landed). Telemetry is already a dep of SudokuUI / GameCenterClient / Persistence / AppComposition, so every catch-site can import it without dep-graph changes.
  - `ErrorReport` is `Sendable, Equatable, Hashable` — confirmed at L21.
  - `Telemetry.errorOccurred(source:code:message:)` enum case exists at the call site in `LiveErrorReporter.report(...)` — confirmed by `swift build` success.
  - `Live.swift` / `Preview.swift` / `RouteFactory.swift` arg signatures match — confirmed by build.
  - `BoardLoaderView.swift` `UserFacingError` rendering — confirmed by build.
  - `ErrorReporterTests.swift` lives at `Tests/TelemetryTests/` (TelemetryTests target already declared in Package.swift L137); `import Testing` resolves correctly.
  - `DailyHubViewModel.swift:11` — file already uses `internal import Telemetry` (no `public` modifier); not touched.
  - `DailyHubViewModel.swift:72` Set/Array mismatch — file builds clean; the reported mismatch was pre-rebase noise.
  - `LivePersistence.swift:14` — Persistence already depends on GameState in Package.swift L23; builds clean.
  - `MonetizationStateController.swift` — untouched (Fix B territory).
- Test results: `swift test --filter ErrorReporter` = 6/6 passed (~1ms each, first run). No `BoardLoaderViewTests` exists in the tree (the dispatch reference was speculative).
- **Edit applied during resume**: `UserFacingError` enum now conforms to `Error` (was: `Sendable, Equatable, Hashable`; now: `Error, Sendable, Equatable, Hashable`). Rationale per dispatch §Step-2 bullet 2: the `as? UserFacingError` cast in `classify(_:)` previously always returned `nil` (the enum was not `Error`-conformable, so it could never appear in an `any Error` existential). Adding `Error` conformance makes the idempotent-pass-through branch actually reachable when a caller re-classifies an already-classified value. Strictly additive; no associated values to need throw-site changes; tests' `#expect(received[0].error == .networkUnavailable)` still uses `==` on the concrete enum value so no test churn.
- **Full-suite hang observed (RCA recurrence)**: After Fix B, the *first* `swift test` (no filter) appears to have reached its result-emit phase — the monitor captured `Test Suite 'Selected tests' passed at 17:52:48` for the xctest sub-suite — but `swiftpm-testing-helper` (PID 33296, started 17:17) is still alive at 17:55+, holding the SwiftPM `.build` lock and blocking every subsequent `swift build` / `swift test` invocation. Stack of waiters: PIDs 33280 (swift-test wrapper), 38780, 41338, 42295, 45493 (swift-build), 46988, 52018 (swift-test --filter). All in state `S` with ~0 CPU; the helper had ~4s CPU then stopped. This matches H1 wall-clock signature even though Fix B addressed the `MonetizationStateController` leak — so a *second* long-lived task source must exist (candidates: `LiveGameCenterClient` listener per RCA H2, or a swift-testing 6.2 suite-instance retention issue beyond the IAP path). Aborting per dispatch §Step-3 rule "if hangs, abort + report PIDs (don't kill -9 yourself)".
- **PIDs to report to Leader** (do not kill from subagent): 33296 (swiftpm-testing-helper, primary suspect — held SwiftPM lock for 38+ min), 33280 (swift-test parent), plus the queued waiters 38780 / 41338 / 42295 / 45493 / 46988 / 52018. The wrapper shell PID 33278 (`zsh -c '... | tail -20'`) is itself waiting on swift-test EOF; killing 33296 should cascade-release everything.
- **Net result of resume work**: 1 file edited (`UserFacingError.swift`, +6 chars). Build state at start of resume already clean; targeted ErrorReporter tests still pass. Full-suite verification blocked by lock contention from the very full-suite invocation that this subagent attempted — same RCA bug class as documented, not a regression introduced here.

## 變更檔案清單 (will be filled as edits land)

- `Packages/SudokuKit/Sources/AppComposition/UserFacingError.swift` (new)
- `Packages/SudokuKit/Sources/AppComposition/ErrorReporter.swift` (new — protocol + LiveErrorReporter + NoopErrorReporter)
- `Packages/SudokuKit/Sources/AppComposition/AppComposition.swift` (add `errorReporter` field)
- `Packages/SudokuKit/Sources/AppComposition/Live.swift` (wire LiveErrorReporter)
- `Packages/SudokuKit/Sources/AppComposition/Preview.swift` (wire NoopErrorReporter)
- `Packages/SudokuKit/Sources/SudokuKitTesting/Telemetry/FakeErrorReporter.swift` (new)
- `Packages/SudokuKit/Sources/SudokuUI/Root/RootViewModel.swift` (do/catch + reporter)
- `Packages/SudokuKit/Sources/SudokuUI/Board/GameViewModel.swift` (do/catch + reporter on persistence/session sites)
- `Packages/SudokuKit/Sources/SudokuUI/Board/BoardLoaderView.swift` (UserFacingError in `.failed`)
- `Packages/SudokuKit/Sources/SudokuUI/Settings/SettingsViewModel.swift` (do/catch + reporter)
- `Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubViewModel.swift` (do/catch + reporter)
- `Packages/SudokuKit/Sources/GameCenterClient/GameCenterSink.swift` (do/catch → reporter for evaluator)
- `App/Resources/Localizable.xcstrings` (5 new error keys: `error.userFacing.<case>.body`)
- `Packages/SudokuKit/Tests/AppCompositionTests/ErrorReporterTests.swift` (new)
