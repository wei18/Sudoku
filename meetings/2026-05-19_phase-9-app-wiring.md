# 2026-05-19 — Phase 9 App Wiring (DI + Privacy + L10n)

Session continuation of `ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`.
Mode: AI Collaboration Mode (Leader + 1 Developer subagent dispatch, background).

## Goal

Execute plan.md Phase 9 — wire the App target via DI composition root, finalize entitlements, ship `PrivacyInfo.xcprivacy`, seed Localizable.xcstrings (en + zh-Hant), run 5-locale AI translation pass (ja / zh-Hans / es / th / ko). End state: v1 codebase feature-complete; Phase 10 is operational only.

## Decisions

1. **`AppComposition` is a SwiftPM target, not raw `App/` files**. Reason: `swift test` can't reach files under `App/`; the only way to unit-test DI wiring is via a thin SwiftPM module. `App/SudokuApp.swift` just imports `AppComposition` + `SudokuUI`.
2. **`LivePersistence` lives at `Packages/SudokuKit/Sources/Persistence/LivePersistence.swift`**, not in `App/CompositionRoot/`. Reason: production stores (`SavedGameStore`, `PersonalRecordStore`, `LivePrivateCKGateway`) are `internal` to Persistence — the public live entry must compose them from inside the module.
3. **`AppComposition` is `@MainActor`-isolated**, not `Sendable`. Held VMs are MainActor-bound.
4. **`LivePersistence` CloudKit init is deferred (lazy via NSLock-guarded fields)**. `LivePrivateCKGateway.init` would call `CKContainer.default()` which traps without entitlements — deferral makes `AppComposition.live()` safely callable from unit tests.
5. **MetricKit subscription registration skipped under XCTest** (env-var check) to avoid `MXMetricManager` crashes in the test process.
6. **PrivacyInfo `NSPrivacyAccessedAPITypes` is empty array** (key present, list empty). Verified: v1 production code uses NO UserDefaults, no file-timestamp APIs, no disk-space APIs, no system-boot-time APIs. Prompt suggested `CA92.1` for UserDefaults — would have been a false declaration. Will revisit when a transitive dep introduces one of the four required-reason categories.
7. **Tuist `Project.swift` edits**:
   - Added `.package(product: "AppComposition")` to App target dependencies.
   - `resources:` += `App/Resources/PrivacyInfo.xcprivacy` + `App/Resources/Localizable.xcstrings`.
   - `defaultKnownRegions: ["en"] → all 7 locales`.
   - Capabilities still file-based via `entitlements: .file(path: "App/Sudoku.entitlements")`. No declarative `.gameCenter() / .iCloud(...)` Tuist API needed.

## Rejected alternatives

- **`App/CompositionRoot/LivePersistence.swift` per the spec**: rejected because internal Persistence types make App-level facade impossible without exposing the stores. LivePersistence ended up inside Persistence module instead.
- **Declaring `CA92.1` (UserDefaults) in PrivacyInfo**: rejected — v1 doesn't actually use UserDefaults; declaring would be false. Empty list is honest and lets future code add reasons as needed.
- **Eager CloudKit `CKContainer.default()` initialization**: rejected — traps unit tests without entitlements; lazy NSLock-guarded init preserves the unit-test surface.

## Translation tricky cases

- **Thai** "leaderboard" → "กระดานผู้นำ" (board of leaders); no single-word equivalent. Sentence-end politeness markers `ครับ/ค่ะ` deliberately omitted to match calm-paper neutrality.
- **Japanese** "Pencil" → "メモ" (memo/notes), not literal "鉛筆". Matches UI semantics (pencil mode = note input).
- **Practice**: 練習 for ja AND zh-Hant (visual consistency).

## Subagent dispatch

| Step | Commit | New tests |
|---|---|---|
| 9.1 SudokuApp + AppComposition + LivePersistence | `54c8fc1` | 3 (CompositionTests) |
| 9.2 GameCenter + CloudKit entitlements + Tuist resources | `e22f10e` | 0 (build-time) |
| 9.3 PrivacyInfo.xcprivacy | `0c5e303` | 3 (PrivacyManifestTests) |
| 9.4 Localizable.xcstrings (en + zh-Hant seed, ~54 keys) | `415e3ef` | 2 (L10nTests) |
| 9.5 5-locale AI translation (ja / zh-Hans / es / th / ko) | `3fae80c` | 2 (L10nCompletenessTests) |

**Total: 10 new tests, 309 → 319, 0 warnings Swift 6 strict.**

## GameViewModel async factory pattern (recorded for future reference)

```swift
gameViewModelFactory: { envelope in
    let identity = envelope.identity
    let snapshot = try await persistence.loadOrCreate(
        puzzleId: identity.puzzleId,
        mode: identity.kind.rawValue,
        difficulty: identity.difficulty
    )
    let adapter = GameStateTelemetryAdapter(
        telemetry: telemetry,
        puzzleId: identity.puzzleId,
        mode: identity.kind.rawValue,
        difficulty: identity.difficulty
    )
    let session = await GameSession.restore(from: snapshot, telemetry: adapter)
    return await MainActor.run {
        GameViewModel(
            identity: identity,
            session: session,
            initialBoard: snapshot.currentBoard,
            initialNotes: snapshot.notes,
            initialStatus: snapshot.status,
            initialElapsedSeconds: snapshot.elapsedSeconds,
            persistence: persistence
        )
    }
}
```

`.preview()` / `.tests()` use the synchronous snapshot-only `GameViewModel(identity:board:)` init for deterministic preview rendering.

## v1 codebase feature-complete

After Phase 9, the autonomous-implementation portion of v1 is done. Final state:

- **80 commits** on `main`, working tree clean.
- **319 swift-testing tests** across SudokuKit; 0 warnings on Swift 6 strict + complete concurrency + InternalImportsByDefault + ExistentialAny.
- **25 PNG snapshot baselines** for SudokuUI; baseline diff-stable on rerun.
- **7-locale Localizable.xcstrings** with ~54 user-facing keys.
- **PrivacyInfo.xcprivacy** shipped, no third-party trackers / no PII collection.
- **Entitlements** declared: CloudKit container `iCloud.com.wei18.sudoku`, GameCenter on.
- **Tuist Project.swift** generates `Sudoku.xcworkspace` from sources.

## Phase 10 — what remains (operational, mostly manual)

| Item | Owner | Notes |
|---|---|---|
| Real signing certificate / provisioning profile | **User** (Apple Developer account) | `xcodebuild` currently fails on signing |
| ASC: reserve `com.wei18.sudoku` bundle ID + iOS + macOS app records | **User** | Phase 1.7 deferred |
| CloudKit container `iCloud.com.wei18.sudoku` (Public + Private DB scopes) | **User** | Public DB unused in v1, just reserved |
| Xcode Cloud workflows (PR / Main / Release) in ASC | **User** | foundations §4 |
| GitHub public repo + Secret Scanning Alerts + branch protection | **User** | Was always deferred |
| ASC: register 3 leaderboards (`com.wei18.sudoku.leaderboard.{easy,medium,hard}.daily.v1`) | **User** or scriptable | Source: leaderboard ID derivation in Phase 7 |
| ASC: register 8 achievements per §How.3.2 | **User** or scriptable | Could be a Phase 10 follow-up subagent if ASC API is willing |
| Upload 7-locale strings to ASC achievements / leaderboards | **User** or scriptable | xcstrings has the strings; ASC API can ingest |
| Internal TestFlight build via Main CI | **CI** once configured | requires signing + ASC bundle ID first |
| Sandbox `GKLocalPlayer` smoke test on iPhone + Mac | **User** (real device) | TestFlight install required |
| CloudKit dev container validation (zone provisioning, subscription, conflict resolution) | **User** (real device) | TestFlight install required |
| App Store metadata + screenshots in ASC | **User** | 7-locale rollout |
| Production submission | **User** | Final step |

## Leader-parallel work this session

During Phase 9's ~23-minute background run:
- Created task #22, marked in_progress.
- Wrote Phase 8 Part 2 meeting log + committed.
- Drafted Phase 9 dispatch covering the 5-step DI/Privacy/L10n surface.
- (Now) Writing Phase 9 meeting log.

## Next session

Pause point. v1 codebase is feature-complete; further progress is **operational** and requires the user's Apple Developer / GitHub / ASC access. Two remaining subagent-automatable possibilities:

1. ASC achievement + leaderboard registration script (uses the App Store Connect API; requires user-provided API key — was Phase 10 Option in plan).
2. Plan.md / methodology.md / design.md final consistency sweep (cross-reference cleanup after the §8.11 amendment and the LivePersistence module-location shift).
