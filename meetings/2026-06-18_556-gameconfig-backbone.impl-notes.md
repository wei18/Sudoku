# Impl Notes — #556 GameConfig + makeGameApp backbone (2026-06-18)

Status: COMPLETE
Owner: Developer (Sonnet)
Dispatched by: Leader
Started: 2026-06-18
Completed: 2026-06-18

## 最終實作摘要 (Final implementation — supersedes some early decisions below)

- **ATTPrimerCoordinator → MonetizationUI** (NOT AdsAdMob as first planned). `foundations.md §9.1` forbids SudokuUI importing AdsAdMob; SudokuUI already does `public import MonetizationUI`, so MonetizationUI is the cycle-free home. AdsAdMob stays a GameAppKit dep only for `LiveAdMobAdProvider` + `ATTPresenter`. GoogleMobileAds remains confined to AdsAdMob.
- **ReminderPrimerCoordinator → SettingsUI** + **ReminderSettingsEntry → SettingsUI** (as planned). SettingsKit gained a `TelemetryKit` dep (the coordinator emits `TelemetryEvent` via an injected closure). The coordinator's `settingsStore: ReminderSettingsStore` param was replaced with a game-agnostic `getFireTime: () -> (hour,minute)` closure so SettingsUI need not import the Sudoku-only `ReminderSettingsStore` (which stays in SudokuUI, untouched).
- **AppComposition kept its FULL public field shape** (NOT slimmed to 3 fields). Audit showed `CompositionTests` + `BootOrderTests` read `adProvider`/`iapClient`/`adGate`/`routeFactory`/`monetizationController`/etc. and call `bootMonetization()`. `live()` now builds a `GameConfig<AppRoute>`, calls the new `makeGameAppWithDeps(config:)` (returns `GameAppHandle<Route>` = view + GameDeps + rootVM + routeFactory), and assembles `AppComposition` from that single wired bag. `MonetizationStateController.startListeningForLifetimeOfApp()` runs exactly once (inside makeGameApp); no double construction.
- **`rootView` unchanged** — still builds the Sudoku `RootView` (ATT sheet, GC alert, ResumePill, `\.sudokuCell`, `#if DEBUG SudokuNearWinModifier`). Snapshot tests construct views directly (not via `live()`/`rootView`), so the `live()` migration moves zero snapshot baselines. Confirmed: 0 PNGs changed.
- **Reminder tap routing preserved** — added `GameConfig.reminderTapRoute: (@MainActor (String, GameRootViewModel<Route>) -> Void)?`; `makeGameApp` wires it into the (relocated) `GameReminderDelegateRetainer`. Sudoku passes the exact former routing (`dailyReady` → push `.daily`). Old `SudokuAppComposition/ReminderNotificationDelegate.swift` deleted (its only caller was the old `live()`).
- **MetricKit retainer + reminder delegate** moved into GameAppKit (`MakeGameApp+Retainers.swift`); audio + boot helpers in `MakeGameApp+Helpers.swift` (keeps each file < 400-line gate). `bootMonetization()` also remains a public method on `AppComposition` for `BootOrderTests`.
- **Verification**: GameAppKit build+tests green (18); SudokuKit build+tests green (255); SettingsKit/AppMonetizationKit build green; swiftlint --strict clean on all changed files; no snapshot PNG drift.

## 設計決定 (Design decisions)

- **ATTPrimerCoordinator relocation** — Spec `meetings/2026-06-18_556-gameconfig-backbone.md §Target shapes` declares `GameDeps.attPrimer: ATTPrimerCoordinator`. But `ATTPrimerCoordinator` currently lives in `SudokuKit/Sources/SudokuUI/Monetization/ATTPrimerCoordinator.swift` and only imports `SwiftUI`. `GameAppKit` cannot import `SudokuUI` (that would be a cycle: SudokuUI → GameAppKit → SudokuUI). Chosen fix: **move `ATTPrimerCoordinator` into `AppMonetizationKit/Sources/AdsAdMob/`** — it only needs SwiftUI, it's fundamentally about ads/ATT, and AdsAdMob is already a dep GameAppKit will gain. SudokuUI re-exports it via `public import AdsAdMob`. Downstream: `SudokuUI/Monetization/ATTPrimerCoordinator.swift` file removed; consumers that already import AdsAdMob (AppComposition) get it for free; SudokuUI needs `public import AdsAdMob`.

- **ReminderPrimerCoordinator relocation** — Similarly `GameDeps.makeDailyReminderPrimer: @MainActor () -> ReminderPrimerCoordinator`. `ReminderPrimerCoordinator` is in SudokuUI, uses only `SettingsUI + Reminders + Telemetry + SwiftUI`. GameAppKit will depend on SettingsUI. **Move `ReminderPrimerCoordinator` from SudokuUI into `SettingsKit/Sources/SettingsUI/`**. SudokuUI drops its own file; callers get it via `import SettingsUI`.

- **ReminderSettingsEntry relocation** — `GameDeps.makeReminderSettings: @MainActor () -> ReminderSettingsEntry`. `ReminderSettingsEntry` is defined at line 149 of `SudokuKit/Sources/SudokuUI/Settings/SettingsView.swift`. It only uses `SettingsUI` types (`ReminderSettingsModel`, `ReminderSettingsCopy`, `ReminderPrimerCopy`, `ReminderDeniedCopy`). **Move `ReminderSettingsEntry` into `SettingsKit/Sources/SettingsUI/`** (alongside the types it wraps). SudokuUI's `SettingsView.swift` drops the definition; callers get it from `import SettingsUI`.

- **App-target public surface choice (spec §2b)** — The spec says "wrap `makeGameApp` behind `AppComposition.rootView` OR have the App call `makeGameApp` directly". Chosen: **keep `AppComposition.rootView` as the public surface the App consumes**. The `live()` factory rebuilds as: create `GameConfig`, call `makeGameApp(config:)`, wrap the returned View behind a lazy `rootView` computed var (which also runs `bootMonetization`, attaches `#if DEBUG SudokuNearWinModifier`, etc.). Rationale: zero churn to `App/Sudoku/SudokuApp.swift`; it already calls `.rootView`. The `AppComposition` struct becomes leaner — most fields move into `makeGameApp`'s local scope.

- **AppComposition stored fields after migration** — Post-migration `AppComposition` struct keeps only: `rootViewModel` (needed by callers that call `.bootstrap()`, `.bootMonetization()` etc.), `telemetry`, `errorReporter`. The `rootView` computed property assembles from a stored `_rootView: AnyView` (the output of `makeGameApp`) plus the bootMonetization+NearWin wrappers. Most other fields (`routeFactory`, `adProvider`, `iapClient`, `adGate`, `monetizationStateStore`, `monetizationController`, `toastController`, `attPrimer`) are local to `makeGameApp` and no longer stored on the struct. **Risk:** tests or callers that directly access these fields. Need to audit callers of `AppComposition` before deleting fields.

- **GameDeps + GameConfig location** — New file `Packages/GameAppKit/Sources/GameAppKit/GameConfig.swift` holds both `GameDeps` and `GameConfig<Route>`. `makeGameApp` goes in `MakeGameApp.swift`.

- **AudioConfig / ReminderContentConfig subtypes** — The spec mentions `audio: AudioConfig` and `reminders: ReminderContentConfig` as sub-structs in `GameConfig`. These are new value types. **Define them in `GameAppKit/Sources/GameAppKit/GameConfig.swift`**. `AudioConfig` carries: subsystem key prefix (`String`), and the UserDefaults keys are derived from it (matches the existing `com.wei18.sudoku.audio.*` prefix pattern). `ReminderContentConfig` carries: `dailyReadyTitle: String`, `dailyReadyBody: String`, `subsystem: String` for the reminder authorizer/scheduler.

- **GameAppKit new package deps** — Per spec, GameAppKit gains: `GameAudio` (GameAudioKit), `Reminders` (RemindersKit), `AdsAdMob` (AppMonetizationKit), `IAPStoreKit2` (AppMonetizationKit), `MonetizationCore` (AppMonetizationKit, already indirect), `SettingsUI` (SettingsKit). The package deps already include `AppMonetizationKit` and `GameShellKit`; need to add `GameAudioKit`, `RemindersKit`, `SettingsKit`.

## 偏離 (Deviations)

- **ATTPrimerCoordinator move scope** — The spec says GameAppKit gains deps on `AdsAdMob` etc. It does not explicitly say "move ATTPrimerCoordinator". This move is *necessary* to resolve the module cycle. Downstream: SudokuUI's `ATTPrimerCoordinator.swift` is deleted; one file added to AdsAdMob. SudokuUI gets `public import AdsAdMob` in the imports of files that reference `ATTPrimerCoordinator`. AppComposition already does `internal import AdsAdMob`.

- **ReminderPrimerCoordinator move scope** — Same logic. Currently in SudokuUI; must move to SettingsUI for GameAppKit to reference it. The coordinator imports `SettingsUI + Reminders + Telemetry + SwiftUI` — SettingsUI already depends on RemindersKit and Telemetry, so no new deps for SettingsKit.

- **ReminderSettingsEntry move scope** — Move from SudokuUI's `SettingsView.swift` into SettingsKit/SettingsUI. Clean split: the entry struct only wraps SettingsUI types.

## 折衷 (Tradeoffs)

- **Move types vs use AnyView/closures in GameDeps** — Alternative: keep coordinators in SudokuUI and have `GameDeps` hold opaque closures (`makeATTPrimer: () -> AnyObject`). Rejected: defeats type safety, makes callers cast, harder to test. Moving types to their natural home (AdsAdMob for ATT, SettingsUI for reminder coordination) is cleaner.

- **rootView wrapper vs direct makeGameApp** — Could have App call `makeGameApp(config:)` directly and fold `bootMonetization` + `NearWinModifier` into GameAppKit's `makeGameApp`. Rejected for this PR: changes App/Sudoku/SudokuApp.swift (more churn, App target is Tuist-generated). Keep `AppComposition.rootView` bridge for now; #557 can clean up if desired.

## 未決 (Open questions)

- **AppComposition.tests() / AppComposition.preview() after migration** — These fakes construct `LiveRouteFactory` and `RootViewModel` directly, not via `makeGameApp`. They can stay as-is for now (they already bypass the full live wiring). No behavioral regression since tests use `.tests()`, not `.live()`. Confirmed: keeping fake factories untouched is correct — they provide test-injectable fakes that bypass the full live stack.

- **MinesweeperSettingsView uses `MinesweeperReminderSettingsEntry`** — If `ReminderSettingsEntry` moves to SettingsUI, MS must be checked. Currently MS has its own `MinesweeperReminderSettingsEntry` (possibly identical). Filed as out-of-scope for this PR; migration spec says MS migration is a follow-up (#557–#560).
