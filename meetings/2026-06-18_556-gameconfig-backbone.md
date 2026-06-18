# #556 — GameConfig + makeGameApp backbone (SDD-005 Pillar B)

**Date:** 2026-06-18 · **Status:** design RESOLVED → implementing
**Spec:** SDD-005 §2(B)/§4/§5.1 (`docs/superpowers/specs/2026-06-17-sdd-005-platform-convergence-rfc.md`)
**Decisions (user, 2026-06-18):**
1. API shape = **`GameConfig<Route>` = values + builder closures receiving a `GameDeps` bag** (matches the codebase's closure-injection idiom; keeps GameAppKit free of per-game types; GameShellUI stays zero-dep).
2. **Capabilities are universal, not optional.** Every game gets audio + reminders + ATT + MetricKit. MS missing ATT and 2048 missing audio/reminders are **bugs/gaps**, filled during *their* migration — NOT modelled as `Optional` in `GameConfig`. `GameConfig` carries only the per-game *content* (copy, key prefix, IDs, ckConfig).
3. Migration order **Sudoku → MS → 2048.** Sudoku is the most-complete template → its migration is refactor-only and exercises the full `GameConfig` surface. MS/2048 migrations also fill their capability gaps.

## [OQ-B1] audit (resolved) — what's identical vs per-game

**Identical wiring across all 3 `live()` (→ moves into `makeGameApp`):**
Telemetry base (OSLog+NoOp), `LiveErrorReporter`, `LiveGameCenterClient(GKAuthDriver())`,
`LivePersistence(telemetry, ckConfig, puzzleLoader)`, `monetizationStateStore`,
`AdGate`+onPersistenceError funnel, AdMob/Noop `adProvider` guard (reads `GADBannerUnitID`),
`LiveStoreKit2IAPClient`+onCatalogDesync funnel, `ToastController`,
`MonetizationStateController`+`startListeningForLifetimeOfApp()`, `onPresentBoard` iOS-modal
closure, `GameRootViewModel` assembly, `GameRoot` rootView assembly. **+ universal capabilities:**
audio (LiveAudioSession+LiveSoundPlayer+LiveHaptics+AudioSettingsModel), reminders
(authorizer+scheduler+settingsStore+delegate retainer+primer/settings builders), ATT
(ATTPrimerCoordinator over ATTPresenter), MetricKit (MetricKitSink+retainer).

**Per-game (→ `GameConfig` values/closures):** subsystem string, `ckConfig`, `removeAdsProductId`,
`puzzleLoader`, `theme`, `title`, `sidebarItems`, success/failure tints, reminder copy/content,
audio key-prefix + defaults, per-game `routeFactory` (builds gameplay/hub views), per-game
`savedGameStore` type, rootContent (Home).

## Target shapes (GameAppKit)

```swift
@MainActor public struct GameDeps {          // the wired bag handed to per-game closures
    public let telemetry: Telemetry
    public let errorReporter: any ErrorReporter
    public let gameCenter: any GameCenterClient
    public let persistence: any PersistenceProtocol
    public let adProvider: any AdProvider
    public let adGate: AdGate
    public let monetizationStateStore: any AdGateStateStore
    public let monetizationController: MonetizationStateController
    public let toastController: ToastController
    public let soundPlayer: any SoundPlaying            // universal audio
    public let audioSettings: AudioSettingsModel
    public let attPrimer: ATTPrimerCoordinator          // universal ATT
    public let makeDailyReminderPrimer: @MainActor () -> ReminderPrimerCoordinator
    public let makeReminderSettings: @MainActor () -> ReminderSettingsEntry
}

@MainActor public struct GameConfig<Route: Hashable & Sendable> {
    // values
    public let subsystem: String                 // "com.wei18.sudoku"
    public let ckConfig: PrivateCKConfig          // .sudoku
    public let removeAdsProductId: String
    public let puzzleLoader: LivePersistence.PuzzleLoader
    public let theme: <GameShellUI Theme value>   // injected at .environment(\.theme,)
    public let title: LocalizedStringKey
    public let sidebarItems: [SidebarItem<Route>]
    public let successTint: Color
    public let failureTint: Color
    public let audio: AudioConfig                  // key prefix + spec defaults (universal)
    public let reminders: ReminderContentConfig    // copy/content (universal)
    // builder closures (run after makeGameApp wires GameDeps)
    public let fetchResume: @MainActor (GameDeps) -> (() async throws -> ResumeCandidate<Route>?)?
    public let makeRouteFactory: @MainActor (GameDeps, GameRootViewModel<Route>) -> any RouteFactory<Route>
    public let makeHome: @MainActor (GameDeps, GameRootViewModel<Route>) -> AnyView
}

@MainActor public func makeGameApp<Route>(config: GameConfig<Route>) -> some View
```

`makeGameApp` steps: build telemetry(subsystem)+MetricKit retainer → errorReporter → gameCenter
→ persistence(ckConfig, puzzleLoader) → monetization stack (store/adGate/adProvider/iap/controller
/toast) → audio stack → ATT primer → reminder builders → assemble `GameDeps` → `rootVM =
GameRootViewModel(... fetchResume: config.fetchResume(deps))` → `routeFactory =
config.makeRouteFactory(deps, rootVM)` → `GameRoot(viewModel: rootVM, title, sidebarItems,
routeFactory, toast, tints, rootContent: { config.makeHome(deps, rootVM) }).environment(\.theme,
config.theme)`.

`savedGameStore` is an app-internal detail: the app's `fetchResume`/`makeRouteFactory` closures
build it from `PrivateCKGatewayFactory.live(config:)` (they know the per-game type). GameAppKit
never sees it.

## GameAppKit dependency expansion (CR watch-item)
Library gains: GameAudio, Reminders, AdsAdMob, IAPStoreKit2, MonetizationCore, SettingsUI.
GameAppKit is "shared composition (deps allowed)" — correct home. Invariants to keep green:
GameShellUI stays zero-dep; GoogleMobileAds stays encapsulated behind AdsAdMob's live bridge;
no eager `CKContainer.default()` (lazy gateway preserved).

## #556 PR scope (this PR)
1. Add `GameDeps` + `GameConfig<Route>` + `makeGameApp(config:)` to GameAppKit; expand deps.
2. Rewrite Sudoku `AppComposition.live()` → builds a `GameConfig` + returns `makeGameApp(config:)`;
   delete the duplicated wiring. Keep `.preview()` and the public `AppComposition` struct surface
   the App target consumes (or have the App call `makeGameApp` directly — Developer picks the
   lower-churn path; document it in impl-notes).
3. MetricKit/audio/reminders/ATT all flow through `makeGameApp` for Sudoku (it already had them →
   behaviour-preserving).

## Verification (behaviour-preserving refactor)
- `swift build --package-path Packages/GameAppKit` + `Packages/SudokuKit` green.
- `swift test --package-path Packages/SudokuKit` — AppComposition boot/order tests + **all snapshot
  baselines unchanged** (this is the gate: any moved PNG = behaviour changed → STOP).
- `swift test --package-path Packages/GameAppKit`.
- swiftlint --strict clean.
- Sim smoke (Leader, post-merge): Sudoku boots, Home→Daily→board→completion, resume pill, ads,
  ATT prompt fires, reminders settings, audio settings.

## Follow-ups (separate issues, not this PR)
- #557–#560 consume `GameConfig`. MS migration (#?) also adds the missing ATTPrimer (5.1.2 bug).
  2048 migration also adds audio + reminders. Track capability-gap fills as part of each migration.
