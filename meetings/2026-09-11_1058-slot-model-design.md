# #1058 banner slot model — approved spec (rev 3)

PR #1062 · red base 85c65cb4 · Phase 1 latch e383fa1a · rev 2 approved by PM (7c3946ba) · rev 3 = PM's final list plus S1 results · 2026-09-11

## Shape
- **`MonetizationUI.BannerSessionModel`** is a `@MainActor @Observable final class`, one per app session, built in `makeGameAppCore` step 5.
  - Observed state: `shouldShow: Bool?` (nil means pending), `providerSuppressed`, and `slots: [BannerSlotID: AdBannerStatus]`.
  - Unobserved state: `adProvider`, `adGate`, `onAdContext`, `sessionReady: ReadinessLatch`, `readyTask`, per-slot load `Task`s, and the set of registered IDs.
- **`BannerSlotView` is a pure renderer.** Its whole body is `if session.isVisible, !isSuppressed { banner(status: session.status(for: id)).padding(h).padding(v) }`.
  - It has no `ZStack`, `.task`, `.onAppear`, `.onChange`, `@State` or `scenePhase`.
  - When hidden or suppressed it produces zero subviews, so a parent with non-zero spacing adds no gap (B1).
  - The ✕ button calls `session.dismiss()`, which is a user action, not a lifecycle hook.

## PM 2 — the provider, and one readiness wait per session
- **Who holds the provider:** `BannerSessionModel.adProvider`. It is the same `adProvider` constant that `makeGameAppCore` hands to `bootMonetization` (MakeGameApp.swift:146 and :382).
- **The only `awaitReady()` call in the app** is `beginReadinessOnce()`:
  - `readyTask ??= Task { do { try await adProvider.awaitReady() } catch { return }; await onAdContext?(); sessionReady.open() }`
  - It is called the first time the gate resolves open with the provider not suppressed, from `start()` or a repoll.
- **How slots reuse it:** `load(id)` calls `try await sessionReady.wait()` on the model-owned latch, which is cancellable per slot, and never calls the provider's readiness itself.
- **`readyTask`'s silent catch, an accepted failure mode (PM):**
  - Nothing cancels `readyTask`: no one holds a handle to it, and the model lives as long as the process.
  - If it ever were cancelled, `sessionReady` would stay closed. Every visible slot would then sit at `.notInitialized` in its reserved 50pt, indefinitely.
  - That means no ad, and also no false "Ad unavailable". This is written down on purpose.

## PM 1 — telling cancellation apart from failure, at every catch
A cancelled wait or load produces **no status change**.
1. **`BannerSessionModel.load(id)`:** `catch is CancellationError { return }`, with no write to `slots`. Loads are cancelled only by `unregister(id)` (the entry is already gone) or `hideAll()` (which resets to `.notInitialized` itself).
2. **`BannerReloadCoordinator.reloadIfGateOpen`:** becomes `async throws(CancellationError)` and re-throws before the generic catch that maps to `.failed`. Phase 1b adds a comment at today's catch disclosing that this gap is still open.
3. **`LiveAdMobAdProvider.refreshBanner`:** waiting for readiness already happens before any status write (pinned in Phase 1). The load's `do/catch` gains `catch is CancellationError { lastKnownStatus = previous; throw }`.
4. **`LiveAdMobBridge.loadBanner`:** today its catch-all (:158-162) wraps its own `onCancel` cancellation as `loadFailed`. After the existing view cleanup it will throw `CancellationError()` when `Task.isCancelled`.

## Slot registration without depending on the rendered subtree (S1: PASS)
`BannerSlotView` stores `BannerSlotRegistration: DynamicProperty`, which holds `@Environment(\.bannerSession)` and `@StateObject var lease = BannerSlotLease()`.
- **Code shape required by Swift 6:** a `@MainActor struct … : DynamicProperty` is a hard error ("conformance crosses into main actor-isolated code"), because `DynamicProperty.update()` is nonisolated. So:
  - The struct is nonisolated and its `init` is `@MainActor`.
  - `nonisolated func update() { MainActor.assumeIsolated { lease.attach(to:) … } }`.
  - `SwiftUI` calls `update()` only during the view-graph pass on the main thread. `assumeIsolated` is a precondition checked in every build configuration: if that ever changes it traps, it never races.
  - I didn't use an isolated conformance (`@MainActor DynamicProperty`). SwiftUI installs dynamic properties through runtime metadata, and an isolated conformance can fail that lookup when the caller isn't on the actor.
- **`attach` is idempotent.** `update()` runs more than once per mount (S1 measured 2 on first mount and 12 across 11 renders).
- **The lease's `isolated deinit`** calls `unregister(id)`, which cancels the slot's load and disposes its handle.
- **Why this option:**
  - The `@StateObject` thunk runs once per identity.
  - Dynamic properties install even when the body renders nothing.
  - Host-side registration would copy four hosts' mount conditions, which is the #448 drift class.

## Start, ordering, repoll
- **GameRoot's role:**
  - It takes `bannerSession` as an init parameter and injects `.environment(\.bannerSession, …)` on `shellContent`.
  - It re-injects the value on the cover content next to `\.gameChrome` (GameRoot.swift:173).
  - It starts the model in the existing `.onAppear { Task { … } }` (#361) and observes `.onChange(of: scenePhase)` on `shellContent`. The boards' flush observers are untouched.
- **`start()`** is idempotent:
  1. Resolve the gate. If closed, stop.
  2. If `adProvider.bannerStatus == .suppressed`, set `providerSuppressed` and stop. macOS Noop never waits and never shows the primer (#968).
  3. `beginReadinessOnce()`.
  4. `ensureLoads()`.
- **`load(id)` is the only code that touches the provider:**
  1. `sessionReady.wait()`
  2. `checkCancellation`
  3. `reloadIfGateOpen`
  4. Dispose the handle if the slot unregistered in the meantime; run `hideAll()` on `.suppressed`; otherwise store `slots[id]`.
- **`NoopAdProvider.refreshBanner()` throwing `AdProviderError.unsupported` is unreachable because of ordering, not because of types** (PM). Only start step 2 stops a suppressed provider before any `load`. Nothing in the type system prevents a Noop provider from reaching `refreshBanner()` if that step were ever reordered.
- **Primer vs. load timing (PM):**
  - `maybePresentOnAdContext` sets `isPrimerPresented = true` and returns without waiting for the sheet (ATTPrimerCoordinator.swift:58-67). So `sessionReady` opens and loads start while the sheet is still up, and the first ad may be non-personalised until the user answers ATT.
  - This matches today: `BannerSlotView.resolveGateAndLoad` also calls `onAdContext`, which returns right away, and then reloads.
  - C-33's contract, that the primer is requested before any ad load, still holds: `readyTask` requests it before it opens `sessionReady`, and every load waits on `sessionReady`.
- **What repoll adds beyond the latch** (`sceneDidBecomeActive()`):
  1. Join `start()`.
  2. Re-resolve the gate. Closed runs `hideAll()` without touching the provider. Open while `shouldShow != true` sets `shouldShow = true`, so a banner dismissed yesterday comes back (Gap 1).
  3. `beginReadinessOnce()`, then `ensureLoads()` for slots with no live handle. A handle that is already loaded is not reloaded (approved).

## PM 3 — the #723 seed (known limit)
- **Object:** `BannerSessionModel`. **Property:** `shouldShow: Bool?`.
- **Who reads it:** `BannerSlotView.body`, synchronously, through `@Environment(\.bannerSession)`. Environment can't be read in `init`, so the read happens in the first body evaluation, before the first frame.
- **Where it's set:** `nil` in `BannerSessionModel.init` (`makeGameAppCore` step 5, before `GameRoot` exists). The resolved value is written by `start()` step 1, launched from GameRoot's `.onAppear`.
- **Known limit:** a slot that mounts before the session's first gate read finishes renders nothing (0pt) and reflows once when the value lands.
- **Why it's accepted:**
  - #723's defect was the reservation waiting on the ad *load*.
  - Its shipped fix seeded from `AdGate.lastKnownShouldShowBanner`, which is `nil` until the first resolution. So #723 carried the identical pre-first-read window, and it was accepted with it.
  - Rev 3 matches #723 and does not regress it.
- `lastKnownShouldShowBanner`, its `Mutex` and `AdGateLayoutHintTests` lose their only consumer, so they are deleted.

## Split state (Gap 2), dismiss, purchase
- **Session-wide:** gate, suppressed flag, readiness plus primer, and dismissed. **Per slot**, by lease UUID: status, handle, load Task, and dispose.
- **Handle:** `refreshBanner()` returns `AdBannerHandle`, so concurrent slots never read the provider's single shared `bannerStatus`.
- **Dismiss:** hides every slot and disposes every handle.
- **Purchase:** `markPurchased` calls `bannerSession.refreshGate()`.

## Pause (rev 2 as approved)
- **Hosts:** they always build the slot and pass `isSuppressed: viewModel.isPaused`; MS adds `|| viewModel.isTerminal`.
- **Rendering:** while suppressed the slot renders zero subviews. That looks identical to shipped v2.3.5, whose hosts' `if !viewModel.isPaused` removes the slot (the deliberate "calm contract").
- **Why:** the identity, lease and handle survive, and the re-request on every resume goes away.
- **`BoardViewBannerTests`:** its assertions and its PNG baselines stay untouched. But it builds `BoardView(viewModel:adProvider:adGate:)` and warms `lastKnownShouldShowBanner`, and both go away under this spec. So only its construction and seed lines change: inject a session whose `shouldShow == true`.
- **Considered and deferred, alternative (C):**
  - While paused, keep an empty 50pt rect instead of zero subviews. That would remove the pause/resume reflow and still honour the calm contract, since no ad shows.
  - But it changes v2.3.5's layout contract and the paused snapshot baselines. That is a product layout decision and doesn't belong in a release blocker.
  - Deferred; no issue filed.

## #931 E2E (test code unchanged)
- **Banner case:** at launch the fake store throws and the slot is hidden. After Home → activate, the root `scenePhase` observer runs a repoll, the gate opens, and the Today slot (registered while hidden, proven by S1 P1b) shows `monetization.banner.slot`.
- **N15:** the first `beginReadinessOnce()` presents the primer. A second cycle doesn't re-present it.
- Only the comments naming `BannerSlotView`'s `.onChange` change.

## Deletions and batch items
- **Delete in `BannerSlotView`:** the `ZStack`, `.task`, three `.onChange`s, `scenePhase`, three `@State`s, the lifecycle methods, and five init parameters.
- **Delete elsewhere:**
  - `MonetizationBootSignal`, `GameDeps.bootSignal`, and `bootMonetization`'s `bootSignal` parameter along with both `markReady` calls.
  - `TodayTabHost`'s monetization parameters and `todayTabHostFireOnAdContext`.
  - The board, loader and route-factory `adProvider/adGate/bootSignal` parameters (20 files).
  - `scan/bannerslot_bootsignal` plus its `lint.yml` job, header item 7 and "seven job names".
  - `BannerSlotColdLaunchTests`.
- **Keep:** the in-view padding, `BannerSlotCollapsedHeightTests`, the CLAUDE.md commit, and the latch.
- **Retarget** to an injected session, with baselines byte-identical: TodayTabHostTests, BoardViewBannerTests (construction only, see Pause), BannerSlotDarkBandRegressionTests, MinesweeperBoardSnapshotTests, and HubSettingsBannerTests.
- **Padding:** `BoardView+Layout.swift:51` and `MinesweeperBoardView.swift:534` move their external padding to `horizontalPadding:`.
- **Collapsed-height test:** the header names both `themedBanner`s, and the rows use the real per-layout configs.
- **Test support:** `FakeAdProvider.awaitReadyCallCount` and a `loadGate` on `FakeAdMobBridge`.

## Prerequisites
| # | Assumption | Status |
|---|---|---|
| P1 | For `@StateObject` inside a `DynamicProperty`: the thunk runs once per identity, `update()` runs even when the body renders nothing, and deinit runs on removal | ✓ S1 on macOS and iOS 26.4. Re-run under AppMonetizationKit's exact settings (tools 6.2, Swift 6 mode, StrictConcurrency/ExistentialAny/InternalImportsByDefault) with warnings as errors: 0 warnings, 0 errors, P1a–d pass |
| P2 | `isolated deinit` works | ✓ Xcode 26.5 (17F42) / Swift 6.3.2; it runs on main. The fallback is not needed |
| P3 | Environment reaches pushes and the cover | Push ✓ (S1 P3b). Cover: not measurable in a SwiftPM iOS test bundle (no `UIWindowScene`, so no presentation). Explicit cover re-injection stays, pinned by an app-hosted or E2E test |
| P4 | UMP's completion handler fires after the form is dismissed | ✓ UMPConsentForm.h:22-26 |
| P5 | The primer requests the sheet and returns | ✓ ATTPrimerCoordinator.swift:58-67 |

## Test plan (bounded waits; no baseline re-records)
Model tests can't compile at 85c65cb4, so their red is a recorded mutation run with the mutation named. Tests marked "direct" are red on the base.

| Test | Red |
|---|---|
| **B1:** `VStack(spacing:16)` bookends plus a hidden slot equal the bookends alone. All four board layouts, gate-denied vs ads-absent, compare pixel-equal in-test | Direct (ZStack at 85c65cb4) |
| **C1:** the coordinator with `FakeAdProvider(refreshThrows: CancellationError())` throws and does not return `.failed` | Direct |
| **C2:** cancel the Live provider's refresh while `loadGate` holds it in flight. It throws `CancellationError`, and `bannerStatus` equals its value before the call | Direct |
| **C3:** unregister A while `sessionReady` is held. B's status and `shouldShow` record zero observation changes until `markReady()`. There is never a `.failed` | Mutation: drop the `CancellationError` catch in `load` |
| **R1:** three slots; `awaitReadyCallCount == 1`; the primer runs once | Mutation: per-slot `awaitReady` |
| **B2:** open gate, readiness held, repoll. After 500ms there are 0 refreshes and no primer, then both happen | Mutation: bypass `sessionReady` |
| **B2′:** events arrive as `["ready","primer","adLoadStarted"]` with ready delayed 500ms | Mutation: primer before `awaitReady`. The base also encodes the wrong order at BannerSlotColdLaunchTests.swift:166 |
| **Gap 2:** two leases with interleaved loads get two distinct handles; unregistering A disposes only hA | Mutation: read the shared `bannerStatus` |
| **Gap 1:** dismissed today; clock +1 day; a repoll makes the slot visible and loaded | Mutation: drop repoll step 2 |
| **Pause:** pause then resume keeps the same lease (same `BannerSlotID`) and makes no second refresh call | Mutation: the host removes the slot while paused (v2.3.5 `if !isPaused`) |
| **Seed:** after `start()` resolves true, a newly mounted slot's first body renders the 50pt branch | Mutation: seed read from `slots` |
| **Cover env:** a board inside GameRoot's cover reads `\.bannerSession` (app-hosted or E2E) | Mutation: drop the cover re-injection |
| **Cold launch:** fresh gate, no view mounted; `start()` makes `store.loadCallCount > 0` | Replaces BannerSlotColdLaunchTests test 1 |
| **#931 banner repoll + N15 (XCUITest)** | Regression; unchanged |
