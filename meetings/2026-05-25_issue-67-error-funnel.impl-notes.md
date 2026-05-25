# Impl Notes — issue #67 unified UserFacingError + ErrorReporter funnel (2026-05-25)

Status: IN_PROGRESS
Owner: Senior Developer (subagent)
Dispatched by: Leader
Started: 2026-05-25T15:30+08:00

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

- None at this point. The 5-case enum, protocol shape, and try? retention policy all read directly from issue spec + design.md §How.6.

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
