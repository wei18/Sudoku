# #1058 banner slot model — design for PM review (rev 2, no code yet)

PR #1062 · red base 85c65cb4 · Phase 1 provider latch e383fa1a · rev 2 adds PM items 1–3 · 2026-09-11

## Shape
- **`MonetizationUI.BannerSessionModel`** is a `@MainActor @Observable final class`, one per app session, built in `makeGameAppCore` step 5.
  - Observed state: `shouldShow: Bool?` (nil means pending), `providerSuppressed`, and `slots: [BannerSlotID: AdBannerStatus]`.
  - Unobserved state: `adProvider`, `adGate`, `onAdContext`, `sessionReady: ReadinessLatch`, `readyTask`, per-slot load `Task`s, and the set of registered IDs.
- **`BannerSlotView` is a pure renderer.** Its whole body is `if session.isVisible, !isSuppressed { banner(status: session.status(for: id)).padding(h).padding(v) }`.
  - It has no `ZStack`, `.task`, `.onAppear`, `.onChange`, `@State` or `scenePhase`.
  - When hidden it produces zero subviews, so a parent with non-zero spacing adds no gap. That fixes B1.
  - Parameters: theme colours, `horizontalPadding`/`verticalPadding`, and `isSuppressed` (the host's paused or terminal state).
  - The ✕ button calls `session.dismiss()`, which is a user action, not a lifecycle hook.

## PM 2 — the provider, and one readiness wait per session
- **Who holds the provider:** `BannerSessionModel.adProvider` (`private let`). It is passed the same `adProvider` constant that `makeGameAppCore` hands to `bootMonetization` (MakeGameApp.swift:146 and :382). So the latch the model waits on is the one boot's `initialize()` opens.
- **The only `awaitReady()` call in the app** is `BannerSessionModel.beginReadinessOnce()`:
  - `readyTask ??= Task { do { try await adProvider.awaitReady() } catch { return }; await onAdContext?(); sessionReady.open() }`
  - It is called the first time the gate resolves open with the provider not suppressed, from either `start()` or a repoll.
  - The `??=` makes it idempotent: one wait and one primer per session.
- **How slots reuse it:** `load(id)` never calls the provider's readiness. It calls `try await sessionReady.wait()`. That is a model-owned `ReadinessLatch` (the Phase 1 type): cancellable per slot, opened once, never closed again.
- **What cancels `readyTask`:** nothing. No one holds a handle to cancel it, and the model lives as long as the process. If it were ever cancelled, `sessionReady` would stay closed and slots would keep their reserved `.notInitialized` state. Nothing would ever be written as `.failed`.

## PM 1 — telling cancellation apart from failure, at every catch
A cancelled wait or load must produce **no status change**. The seams, in call order:
1. **`BannerSessionModel.load(id)`:** `catch is CancellationError { return }`. It writes nothing to `slots`. Loads are cancelled only by `unregister(id)` (the entry is already gone) or `hideAll()` (which resets to `.notInitialized` itself).
2. **`BannerReloadCoordinator.reloadIfGateOpen`:** becomes `async throws(CancellationError) -> AdBannerStatus`. It adds `catch let e as CancellationError { throw e }` before the generic catch that maps to `.failed`. Today's catch-all (BannerReloadCoordinator.swift:48) is the "Ad unavailable" lie.
3. **`LiveAdMobAdProvider.refreshBanner`:**
   - Waiting for readiness already happens before any status write. Phase 1 pins that: `refreshBeforeInitializeWaitsWithoutReachingBridge` asserts the status is still `.notInitialized` after cancellation.
   - The load's `do/catch` sets `.loading` and then `.failed` on any error. It gains `catch is CancellationError { lastKnownStatus = previous; throw }`.
4. **`LiveAdMobBridge.loadBanner`:** its catch-all (LiveAdMobBridge.swift:158-162) wraps every error, including the cancellation from its own `onCancel`, as `AdMobBridgeError.loadFailed`. That makes seams 2 and 3 blind. After the existing view cleanup it will throw `CancellationError()` whenever `Task.isCancelled`.
- `readyTask`'s catch writes nothing (see PM 2). The `scenePhase` observer Task has no catch.
- Seams 3 and 4 sit in the provider's load path, not in the Phase 1 latch, so they don't overlap the PM's concurrency review of the latch.

## Slot registration without depending on the rendered subtree
`BannerSlotView` stores `BannerSlotRegistration: DynamicProperty`, which holds `@Environment(\.bannerSession)` and `@StateObject var lease = BannerSlotLease()`.
- `update()` runs on the view node before each body evaluation. It calls `lease.attach(to:)`, which is idempotent: it adds the ID to the unobserved set and schedules `ensureLoads()` for the next main-actor turn.
- The lease's `isolated deinit` calls `unregister(id)`, which cancels the slot's load and disposes its handle.

Why:
- The `@StateObject` autoclosure runs once per identity. A `@State` initial value is rebuilt and thrown away on every parent re-render.
- Dynamic properties are installed even when the body renders nothing. A modifier on a `Group` is not, which was the original defect.
- Host-side registration would copy four hosts' mount conditions, which is the #448 drift class.

**Spike S1 gates the build.**

## Start, ordering, repoll
- **GameRoot's role:**
  - It takes `bannerSession` as an init parameter.
  - It injects `.environment(\.bannerSession, …)` on `shellContent` (the tabs and macOS push destinations) and again on the cover content next to `\.gameChrome` (GameRoot.swift:173).
  - It starts the model in the existing `.onAppear { Task { … } }` (#361).
  - It observes `.onChange(of: scenePhase)` on `shellContent`, which is always mounted and never `EmptyView`. The boards' flush observers are on other views and untouched.
- **`start()`** is idempotent through `startTask`:
  1. `shouldShow = await adGate.shouldShowBanner(now())`. If closed, stop.
  2. If `adProvider.bannerStatus == .suppressed`, set `providerSuppressed` and stop. macOS Noop never waits and never shows the primer (#968).
  3. `beginReadinessOnce()`.
  4. `ensureLoads()`.
- **`load(id)` is the only code that touches the provider:**
  1. `try await sessionReady.wait()`
  2. `try Task.checkCancellation()`
  3. `try await reloadCoordinator.reloadIfGateOpen(now:)`
  4. If the slot unregistered in the meantime, dispose the returned handle. If the result is `.suppressed`, run `hideAll()`. Otherwise store `slots[id]`.
- The order is fixed per session: gate, suppressed check, `awaitReady`, primer, then loads. That fixes #940 by ordering alone, because readiness means `initialize()` finished, which happens after the UMP form is dismissed.
- **What repoll guarantees beyond the latch** (`sceneDidBecomeActive()`):
  1. `await start()`, so an `.active` that arrives before `.onAppear` joins it.
  2. Re-resolve the gate. Closed runs `hideAll()` without touching the provider. Open while `shouldShow != true` sets `shouldShow = true`, so a banner dismissed yesterday comes back (Gap 1).
  3. `beginReadinessOnce()` (a no-op if it already ran), then `ensureLoads()`. Only slots without a live handle load, so the primer ordering matches cold launch. **Please confirm:** a loaded handle is not reloaded on foreground, which is a change from today.

## PM 3 — the #723 seed
- **Object:** `BannerSessionModel`. **Property:** `shouldShow: Bool?`.
- **Who reads it:** `BannerSlotView.body`, synchronously, through `@Environment(\.bannerSession)`. Environment isn't readable in a View's `init`, so the read happens in the slot's first body evaluation, which is before its first frame. That is where the 50pt reservation is decided.
- **Where it's set:**
  - `BannerSessionModel.init` sets it to `nil` in `makeGameAppCore` step 5, before `GameRoot` exists. Every slot therefore reads a defined model, and `.disabled` is only for previews and tests.
  - `start()` step 1 writes the resolved value. `start()` launches from GameRoot's `.onAppear`, the first code that runs once the root is on screen.
  - After that, every newly mounted board, hub or Settings slot reserves 50pt from its first frame.
- **Honest limit:** a board presented during the session's first gate read (a reminder deep link at cold launch, or a slow CloudKit read) still sees `nil` and renders nothing (0pt). It reflows once when the value lands, the same as today.
  - A hard guarantee would mean making board presentation wait on `start()`. I don't recommend that, because a signed-out CloudKit read can hang.
- `AdGate.lastKnownShouldShowBanner`, its `Mutex` and `AdGateLayoutHintTests` lose their only consumer, so they are deleted. At model construction the hint is always `nil` anyway.

## Split state (Gap 2), dismiss, purchase, pause
- **Session-wide:** gate, suppressed flag, readiness plus primer (`readyTask`, `sessionReady`, `hasOffered`), and dismissed. **Per slot**, by lease UUID: status, handle, load Task, and dispose.
- **Handle race:** today concurrent slots read the provider's single shared `bannerStatus`. `refreshBanner()` will return `AdBannerHandle` instead. That touches all 6 conformers; `Noop` throws `AdProviderError.unsupported`, which is unreachable behind start step 2.
- **Dismiss and purchase:** dismiss hides every slot and disposes every handle. `MonetizationStateController.markPurchased` calls `bannerSession.refreshGate()`.
- **Pause:** hosts always build the slot with `isSuppressed: isPaused` (MS also `|| isTerminal`). The identity, lease and handle survive, so resume doesn't re-request a banner. Today every app switch re-requests one.

## #931 E2E (test code unchanged)
- **Banner case:** at launch the fake store throws and the slot is hidden. After Home → activate, the root `scenePhase` observer runs a repoll, the gate is open, and the Today slot (registered while hidden, which S1 must prove) shows `monetization.banner.slot`.
- **N15:** that repoll's `beginReadinessOnce()` presents the primer. A second cycle doesn't re-present it, because of the `readyTask ??=` plus `hasOffered`.
- Only comments naming `BannerSlotView`'s `.onChange` change: ScenePhaseRepollE2ESupport, UITestFakeSeams, UITestOverrides, and UITestLaunchArg:81.

## Deletions and batch items
- **Delete in `BannerSlotView`:** the `ZStack`, `.task`, three `.onChange`s, `scenePhase`, three `@State`s, the lifecycle methods, and the `adProvider/adGate/bannerHost/onAdContext/bootSignal` parameters.
- **Delete elsewhere:**
  - `MonetizationBootSignal`, `GameDeps.bootSignal`, and `bootMonetization`'s `bootSignal` parameter along with both `markReady` calls.
  - `TodayTabHost`'s four monetization parameters and `todayTabHostFireOnAdContext`.
  - The board, loader and route-factory `adProvider/adGate/bootSignal` parameters (20 files).
  - `scan/bannerslot_bootsignal` plus its `lint.yml` job, header item 7 and "seven job names".
  - `BannerSlotColdLaunchTests`.
- **Keep:** the in-view padding, `BannerSlotCollapsedHeightTests`, the CLAUDE.md commit, and the latch.
- **Retarget** to an injected session, with baselines byte-identical: TodayTabHostTests, BoardViewBannerTests, BannerSlotDarkBandRegressionTests, MinesweeperBoardSnapshotTests, and HubSettingsBannerTests.
- **Padding:** `BoardView+Layout.swift:51` and `MinesweeperBoardView.swift:534` move their external padding to `horizontalPadding: theme.spacing.medium`.
- **Collapsed-height test:**
  - The header at :42-46 should name both `themedBanner`s: Sudoku's static `LiveRouteFactory` one (Today, Practice, Settings, 16/12) and the private `BoardView+Layout` one.
  - Rows :86-87 become the real per-layout configs: Sudoku compact medium/0, Sudoku mac 0/0, MS compact medium/0, MS regular 0/0.
  - The header should say it pins height only.
- **Test support:** add `FakeAdProvider.awaitReadyCallCount`, and add a `loadGate` to `FakeAdMobBridge`.

## Prerequisites (any ? blocks the build)
| # | Assumption | Status |
|---|---|---|
| P1 | For `@StateObject` inside a `DynamicProperty`: the thunk runs once per identity, `update()` runs even when the body renders nothing, and deinit runs on removal | ? spike S1 |
| P2 | `isolated deinit` compiles on CI (local: Swift 6.3.2, tools 6.2) | ? S1; fallback is a `deinit` that hops to MainActor in a Task |
| P3 | Environment on `GameRoot` reaches the cover and the push path | ? the near-win modals re-inject `\.theme` by hand, so it isn't assumed; explicit injection plus a test |
| P4 | UMP's completion handler fires after the form is dismissed | ✓ UMPConsentForm.h:22-26 |
| P5 | The primer requests the sheet and returns | ✓ ATTPrimerCoordinator.swift:58-67 |

## Test plan (bounded waits; no baseline re-records)
Model tests can't compile at 85c65cb4, so their red is a recorded mutation run. Tests marked "direct" are red on the base.

| Test | Red |
|---|---|
| **S1:** a hidden slot registers once; 10 parent re-renders still leave one lease; removal unregisters it; a missing environment fires the `onMissingSession` handler | Gate |
| **B1:** `VStack(spacing:16)` bookends plus a hidden slot equal the bookends alone (216 vs 232). All four board layouts, gate-denied vs ads-absent, compare pixel-equal in-test | Direct |
| **C1 (PM 1):** the coordinator with `FakeAdProvider(refreshThrows: CancellationError())` throws `CancellationError` and does not return `.failed` | Direct |
| **C2 (PM 1):** the Live provider's in-flight load is held by `loadGate`, then the refresh is cancelled. It throws `CancellationError`, and `bannerStatus` equals its value before the call | Direct (it is `.failed` today) |
| **C3 (PM 1):** slots A and B registered, `sessionReady` held. Unregistering A cancels its wait. `withObservationTracking` on B's status and `shouldShow` records **zero changes** until `markReady()`. Then B loads, with 1 refresh and no `.failed` anywhere | Mutation: remove the catch in `load` |
| **R1 (PM 2):** two slots register before readiness and a third after; `awaitReadyCallCount == 1` and the primer runs once | Mutation: per-slot `awaitReady` |
| **B2:** open gate, readiness held, `sceneDidBecomeActive()`. After 500ms there are 0 refreshes and no primer; after `markReady()` both happen | Mutation: bypass `sessionReady` |
| **B2′:** events arrive as `["ready","primer","adLoadStarted"]` with ready delayed 500ms | Mutation. The base also encodes the wrong order at BannerSlotColdLaunchTests.swift:166 |
| **Gap 2:** interleaved loads for two leases give two distinct handles. Unregistering A disposes only hA | Mutation: shared `bannerStatus` read |
| **Gap 1:** `dismissedDate` is today; clock +1 day; a repoll makes the slot visible and loaded | Mutation: drop repoll step 2 |
| **Seed (PM 3):** after `start()` resolves true, a newly mounted slot's first body renders the 50pt branch with no async hop | Mutation: seed read from `slots` instead |
| **Cold launch:** fresh gate, no view mounted; `start()` makes `store.loadCallCount > 0` | Replaces BannerSlotColdLaunchTests test 1 |
| **#931 banner repoll + N15 (XCUITest)** | Regression; unchanged |
