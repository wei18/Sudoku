# Swift Test Hang Triage — 2026-05-22

## Verdict
**Partial bisection — hang isolated to one of the seven non-UI test targets:**
`ASCRegisterTests`, `GameCenterClientTests`, `GameStateTests`, `PersistenceTests`, `PuzzleStoreTests`, `SudokuEngineTests`, or `TelemetryTests` (combined filter hangs hard with **zero stdout** before any test begins).

All SwiftUI-side suites (`SudokuUITests` + `AppCompositionTests`) ran to completion when filtered:
- `BoardViewTests | HomeViewTests | RootViewTests | SettingsViewTests`: 30 tests PASS (1.95 s)
- `DailyHubViewTests | PracticeHubViewTests | CompletionViewTests | ToastTests | ThemeTests | SmokeTests | AppRouteTests | HomeViewRemoveAdsCardTests | SettingsIAPRowTests`: 50 tests PASS (0.58 s)
- `BannerLoad | HomeViewBanner | BoardViewBanner`: 6 tests PASS (0.006 s)
- `MonetizationStateControllerUpdates`: 6 tests PASS (0.06 s)
- `BootOrder | Composition | L10n | PrivacyManifest`: 19 tests PASS (0.008 s)

So the UI / monetization / composition layers are **clean**.

## Reproduction
```bash
cd Packages/SudokuKit
mise exec -- swift test --filter "ASCRegister|GameCenterClient|GameState|Persistence|PuzzleStore|SudokuEngine|Telemetry"
```
Result after ~20 minutes wall-clock:
- swift-test (PID 33255) + swiftpm-testing-helper (PID 33269) both in **`S` state, 0 % CPU, 0 bytes stdout**
- The helper writes to FD 1 (pipe → swift-test FD 6) but never emits the swift-testing banner (`􀟈 Test run started.`), meaning the deadlock occurs **before any `@Test` body runs** — during test discovery / module init / static initializer.

This points strongly at **top-level / static side effects in one of the test modules** rather than a hang inside a specific test body.

## Root cause (hypothesis — could not narrow further; see Constraints)
Process state (`S`, 0 CPU) + zero stdout pre-banner = the helper is parked inside dyld / Swift runtime image init, most likely a `static let` initializer that synchronously awaits an actor-isolated value, or a top-level `Task { ... }` that blocks module load.

Likely candidates (ranked by suspicion, based on file inspection):

1. **`Tests/PersistenceTests/`** — uses `FakePrivateCKGateway`, `RecordingSink`, real `GameSession`/`SavedGameStore` actor calls. If any of these have a `static let shared = X(...)` whose initializer hops to MainActor or another actor, parallel test discovery can deadlock.
2. **`Tests/GameCenterClientTests/LiveGameCenterClientDeinitTests.swift`** — spawns a `Task` observing `authDriver` stream and relies on weak-self cleanup. Module-level static driver state could keep the observer Task pinned.
3. **`Tests/PuzzleStoreTests/`** — actor-isolated `PuzzleStore`; `FakeGenerator` may carry `@MainActor` state.

The other four (`ASCRegister`, `GameState`, `SudokuEngine`, `Telemetry`) are mostly pure-value tests with no concurrency surface; lower suspicion.

## Proposed fix (not applied)
Cannot recommend a code fix without first localizing to a single target. **Next step** must be sequential per-target bisection:
```bash
mise exec -- swift test --filter ASCRegister
mise exec -- swift test --filter GameCenterClient
mise exec -- swift test --filter GameState
mise exec -- swift test --filter Persistence
mise exec -- swift test --filter PuzzleStore
mise exec -- swift test --filter SudokuEngine
mise exec -- swift test --filter Telemetry
```
Whichever single-target filter hangs identifies the offending module. Then bisect by `--filter "<Suite>/<test>"` inside it.

Once located, the fix shape will likely be one of:
- Replace `static let shared = X()` whose init touches actor state with a lazy `@MainActor` accessor.
- Add `[weak self]` to any module-level `Task { for await … }` observer.
- Move CloudKit / GameKit container access out of test-target `init()` and into per-test setup.

## Bisection log
| Filter | Result | Tests | Time |
|---|---|---|---|
| `BannerLoad\|HomeViewBanner\|BoardViewBanner` | PASS | 6 | 0.006 s |
| `MonetizationStateControllerUpdates` | PASS | 6 | 0.06 s |
| `BoardViewTests\|HomeViewTests\|RootViewTests\|SettingsViewTests` | PASS | 30 | 1.95 s |
| `DailyHub\|PracticeHub\|Completion\|Toast\|Theme\|Smoke\|AppRoute\|HomeViewRemoveAdsCard\|SettingsIAPRow` | PASS | 50 | 0.58 s |
| `BootOrder\|Composition\|L10n\|PrivacyManifest` | PASS | 19 | 0.008 s |
| **`ASCRegister\|GameCenterClient\|GameState\|Persistence\|PuzzleStore\|SudokuEngine\|Telemetry`** | **HANG** | 0 banner | >20 min, 0 stdout |
| `SudokuEngine` (alone) | **could not run** — blocked on SwiftPM build/test lock held by prior hung process |

## Constraints encountered
- Harness sandbox **denies `kill`/`pkill`** despite task spec allowing it. Once the first combined filter hung, I could not free the SwiftPM build lock to run the per-target follow-ups (`swift test --filter SudokuEngine` queued behind it).
- Investigation capped at ~30 min wall-clock per spec; per-target bisection requires either:
  - User manually running `pkill -9 -f swift-test; pkill -9 -f swiftpm-testing` then re-running the 7 single-target filters above, OR
  - Granting the subagent kill permission for `swift-test` / `swiftpm-testing-helper` processes.

## Next-action recommendation for Leader
Dispatch a follow-up subagent with `pkill` allowance and instruct it to run the 7 single-target filters above sequentially, each capped at 60 s. The first one that hangs identifies the target; then bisect within that target's `@Suite` list.
