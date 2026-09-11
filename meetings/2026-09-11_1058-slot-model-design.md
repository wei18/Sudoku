# #1058 banner slot model — approved spec (rev 3.1)

PR #1062 · red base 85c65cb4 · Phase 1 latch e383fa1a · Phase 1b 553b8fcc · rev 2 approved (7c3946ba) · rev 3 = PM's final list + S1 · rev 3.1 = S1 findings + P3a disposition · 2026-09-11

## Shape
- **`MonetizationUI.BannerSessionModel`** is a `@MainActor @Observable final class`, one per app session, built in `makeGameAppCore` step 5.
  - Observed state: `shouldShow: Bool?` (nil means pending), `providerSuppressed`, and `slots: [BannerSlotID: AdBannerStatus]`.
  - Unobserved state: `adProvider`, `adGate`, `onAdContext`, `sessionReady: ReadinessLatch`, `readyTask`, per-slot load `Task`s, and the set of registered IDs.
- **`BannerSlotView` is a pure renderer.** Its whole body is `if session.isVisible, !isSuppressed { banner(status: session.status(for: id)).padding(h).padding(v) }`.
  - It has no `ZStack`, `.task`, `.onAppear`, `.onChange`, `@State` or `scenePhase`.
  - When hidden or suppressed it produces zero subviews (B1).
  - The ✕ button calls `session.dismiss()`.

## PM 2 — the provider, and one readiness wait per session
- **Who holds the provider:** `BannerSessionModel.adProvider`, the same constant `makeGameAppCore` hands to `bootMonetization` (MakeGameApp.swift:146 and :382).
- **The only `awaitReady()` call in the app** is `beginReadinessOnce()`:
  - `readyTask ??= Task { do { try await adProvider.awaitReady() } catch { return }; await onAdContext?(); sessionReady.open() }`
  - It is called the first time the gate resolves open with the provider not suppressed.
- **How slots reuse it:** `load(id)` waits on the model-owned `sessionReady` latch, which is cancellable per slot.
- **`readyTask`'s silent catch, an accepted failure mode:**
  - Nothing cancels `readyTask`.
  - If it ever were cancelled, `sessionReady` would stay closed and every visible slot would sit at `.notInitialized` in its reserved 50pt, indefinitely.
  - That means no ad, and also no false "Ad unavailable".

## PM 1 — telling cancellation apart from failure, at every catch
A cancelled wait or load produces **no status change**.
1. **`BannerSessionModel.load(id)`:** `catch is CancellationError { return }`, with no write to `slots`. Loads are cancelled only by `unregister(id)` or `hideAll()`.
2. **`BannerReloadCoordinator.reloadIfGateOpen`:** becomes `async throws(CancellationError)` and re-throws before the generic catch that maps to `.failed`. Phase 1b's comment discloses that today's gap is still open.
3. **`LiveAdMobAdProvider.refreshBanner`:** the readiness wait happens before any status write (pinned in Phase 1). The load's `do/catch` gains `catch is CancellationError { lastKnownStatus = previous; throw }`.
4. **`LiveAdMobBridge.loadBanner`:** its catch-all (:158-162) re-throws `CancellationError()` when `Task.isCancelled`, after the existing view cleanup.

## Slot registration without depending on the rendered subtree (S1: PASS)
`BannerSlotView` stores `BannerSlotRegistration: DynamicProperty`, which holds `@Environment(\.bannerSession)` and `@StateObject var lease = BannerSlotLease()`.
- **Required code shape:**
  - `BannerSlotRegistration` is a **nonisolated** struct with a `@MainActor init`, and `nonisolated func update() { MainActor.assumeIsolated { lease.attach(to:) … } }`.
  - Why: `DynamicProperty.update()` is nonisolated in the Swift 6.3 SDK, so a `@MainActor struct` conformance fails to compile under #ConformanceIsolation.
  - Consequence: if SwiftUI ever called `update()` off the main thread, `assumeIsolated` (checked in every build configuration) would **trap loudly**. That is the acceptable failure mode, and it can never become a silent race.
  - Not used: an isolated conformance (`@MainActor DynamicProperty`). **This is reasoning only; it was not tried in S1.** SwiftUI installs dynamic properties through runtime metadata, and per SE-0470 a dynamic lookup of an isolated conformance can fail off the actor, which would silently leave the property uninstalled.
- **Idempotent `attach(to:)` is a tested invariant, not an implementation detail.** `update()` runs more than once per mount (S1: 2 on first mount, 12 across 11 renders), so a second `attach` must never register again. Test I1 pins it.
- **The lease's `isolated deinit`** calls `unregister(id)`, which cancels the slot's load and disposes its handle.
- **Why this option:**
  - The `@StateObject` thunk runs once per identity.
  - Dynamic properties install even when the body renders nothing.
  - Host-side registration would copy four hosts' mount conditions, which is the #448 drift class.
- **A missing model fails loudly:**
  - `update()` with no session calls `BannerSessionModel.onMissingSession`: `assertionFailure` in DEBUG, and the slot renders nothing in Release. That assertion is the regression signal for a lost injection.
  - Previews and snapshots inject `BannerSessionModel.disabled`.

## Start, ordering, repoll
- **Environment injection (P3a disposition, PM-approved):** `.environment(\.bannerSession, bannerSession)` goes on the **`GameRoot(…)` value inside `makeGameApp`, right next to `.environment(\.theme, config.theme)`** (MakeGameApp.swift:374).
  - It does **not** go on `shellContent` inside `GameRoot.body`. That placement sits inside the chain, with `.fullScreenCover` applied outside it, which is S1's `innerChain` variant.
  - The `\.theme` level is S1's `outer` variant, which production already proves reaches the cover (P3a below).
- **GameRoot still takes `bannerSession` as an init parameter** (the same step-5 constant). It uses it for three things:
  - to start the model in the existing `.onAppear { Task { … } }` (#361);
  - to observe `.onChange(of: scenePhase)` on `shellContent` (the boards' flush observers are untouched);
  - to **explicitly re-inject it on the cover content** next to `\.gameChrome` (GameRoot.swift:173), as belt-and-braces.
- **`start()`** is idempotent:
  1. Resolve the gate. If closed, stop.
  2. If `adProvider.bannerStatus == .suppressed`, set `providerSuppressed` and stop. macOS Noop never waits and never shows the primer (#968).
  3. `beginReadinessOnce()`.
  4. `ensureLoads()`.
- **`load(id)` is the only code that touches the provider:**
  1. `sessionReady.wait()`
  2. `checkCancellation`
  3. `reloadIfGateOpen`
  4. Dispose the handle if the slot unregistered; run `hideAll()` on `.suppressed`; otherwise store `slots[id]`.
- **`NoopAdProvider.refreshBanner()` throwing `AdProviderError.unsupported` is unreachable because of ordering, not because of types.** Only start step 2 keeps a suppressed provider out of `load`.
- **Primer vs. load timing:**
  - `maybePresentOnAdContext` requests the sheet and returns (ATTPrimerCoordinator.swift:58-67), so loads start while the sheet is up and the first ad may be non-personalised until ATT is answered.
  - This matches today's `resolveGateAndLoad`.
  - C-33 still holds: `readyTask` requests the primer before it opens `sessionReady`, and every load waits on `sessionReady`.
- **What repoll adds beyond the latch** (`sceneDidBecomeActive()`):
  1. Join `start()`.
  2. Re-resolve the gate. Closed runs `hideAll()` without touching the provider. Open while `shouldShow != true` sets `shouldShow = true` (Gap 1).
  3. `beginReadinessOnce()`, then `ensureLoads()` for slots with no live handle. A loaded handle is not reloaded.

## PM 3 — the #723 seed (known limit)
- **Object:** `BannerSessionModel`. **Property:** `shouldShow: Bool?`.
- **Who reads it:** `BannerSlotView.body`, synchronously, through `@Environment(\.bannerSession)`, in the slot's first body evaluation, before its first frame.
- **Where it's set:** `nil` in `BannerSessionModel.init` (step 5). The resolved value is written by `start()` step 1, from GameRoot's `.onAppear`.
- **Known limit:** a slot that mounts before the session's first gate read finishes renders nothing and reflows once.
- **Why it's accepted:**
  - #723 fixed a reservation that waited on the ad *load*.
  - Its shipped seed, `AdGate.lastKnownShouldShowBanner`, was `nil` until the first resolution, so it carried the identical window and was accepted with it.
  - Rev 3 matches #723 and doesn't regress it.
- `lastKnownShouldShowBanner`, its `Mutex` and `AdGateLayoutHintTests` are deleted.

## Split state (Gap 2), dismiss, purchase
- **Session-wide:** gate, suppressed flag, readiness plus primer, and dismissed. **Per slot**, by lease UUID: status, handle, load Task, and dispose.
- **Handle:** `refreshBanner()` returns `AdBannerHandle`, so no caller reads the shared `bannerStatus` after a load.
- **Dismiss:** hides every slot and disposes every handle.
- **Purchase:** `markPurchased` calls `bannerSession.refreshGate()`.

## Pause (rev 2 as approved)
- **Hosts:** they always build the slot and pass `isSuppressed: viewModel.isPaused`; MS adds `|| viewModel.isTerminal`.
- **Rendering:** while suppressed the slot renders zero subviews, which looks identical to shipped v2.3.5 (the calm contract). The identity, lease and handle survive, and there's no re-request on resume.
- **`BoardViewBannerTests` (lead ruling):** "untouched" means **its assertions and PNG baselines are untouched**.
  - The running/paused visual outcomes and the `Board-iPhone-{light,dark}-banner-reserved` snapshots must stay byte-identical.
  - Only the construction lines (`BoardView(viewModel:adProvider:adGate:)`) and the `lastKnownShouldShowBanner` warm-up change, to injecting a `BannerSessionModel` with `shouldShow == true`. The approved spec deletes those parameters and that property.
  - **If any baseline moves after that adaptation, stop and report. Do not re-record.**
- **Considered and deferred, alternative (C):**
  - While paused, keep an empty 50pt rect instead of zero subviews. That would remove the pause/resume reflow and still honour the calm contract.
  - But it changes v2.3.5's layout contract and the paused snapshot baselines. That's a product layout decision, not something for a release blocker.
  - Deferred; no issue filed.

## #931 E2E (test code unchanged)
- **Banner case:** at launch the fake store throws and the slot is hidden. After Home → activate, the root `scenePhase` observer runs a repoll, the gate opens, and the Today slot (registered while hidden, proven by S1 P1b) shows `monetization.banner.slot`.
- **N15:** the first `beginReadinessOnce()` presents the primer; a second cycle doesn't re-present it.
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
- **Retarget** to an injected session, with baselines byte-identical: TodayTabHostTests, BoardViewBannerTests (construction only), BannerSlotDarkBandRegressionTests, MinesweeperBoardSnapshotTests, and HubSettingsBannerTests.
- **Padding:** `BoardView+Layout.swift:51` and `MinesweeperBoardView.swift:534` move their external padding to `horizontalPadding:`.
- **Collapsed-height test:** the header names both `themedBanner`s, and the rows use the real per-layout configs.
- **Test support:** `FakeAdProvider.awaitReadyCallCount` and a `loadGate` on `FakeAdMobBridge`.

## Prerequisites
| # | Assumption | Status |
|---|---|---|
| P1 | `@StateObject` lease inside a `DynamicProperty` | ✓ S1, on macOS and iOS 26.4, and again under AppMonetizationKit's exact Swift 6 settings with warnings as errors (0 warnings, 0 errors). The lease init ran exactly once across 10 re-renders (`slotInits=11 leaseInits=1 registerCalls=1`). `update()` ran for a hidden slot (`updates=2 registered=1`). Deinit ran synchronously on identity removal (`leaseDeinits=1 deinitWasOnMain=true registered=0`). A missing session was detected in `update()` (`missingSession=2`) |
| P2 | `isolated deinit` | ✓ Xcode 26.5 (17F42) / Swift 6.3.2: it compiles and runs on the main actor. The Task-hop fallback is **not needed** |
| P3a | Environment reaches `fullScreenCover` content | ✓ **by production evidence**, with injection at the `\.theme` level (not by a SwiftPM test). See the three facts below this table |
| P3b | Environment reaches a `NavigationStack` push destination | ✓ S1 on macOS and iOS (`push=root`) |
| P4 | UMP's completion handler fires after the form is dismissed | ✓ UMPConsentForm.h:22-26 |
| P5 | The primer requests the sheet and returns | ✓ ATTPrimerCoordinator.swift:58-67 |

The P3a evidence:
1. `.environment(\.theme, config.theme)` is applied to the `GameRoot(…)` value (MakeGameApp.swift:374), above the `.fullScreenCover` in `GameRoot.body`. GameRoot.swift, which also holds `GameModalContent`, re-injects theme nowhere.
2. `ThemeKey.defaultValue` is `NeutralTheme()` (Theme.swift:391), documented as grayscale with no brand colours (Theme.swift:327-334).
3. The boards inside the cover read `@Environment(\.theme)` (BoardView.swift:57, MinesweeperBoardView.swift:45) and ship in brand colours. So environment applied outside `GameRoot` demonstrably reaches cover content.

The MS near-win cover re-injects `\.theme` by hand (MinesweeperNearWinModifier.swift:77). The likely reason is that the modifier is applied in `MinesweeperAppComposition` around `makeGameApp`'s output, above the theme injection. **? unverified inference**, and not load-bearing.

## Test plan (bounded waits; no baseline re-records)
Model tests can't compile at 85c65cb4, so their red is a recorded mutation run with the mutation named. Tests marked "direct" are red on the base.

| Test | Red |
|---|---|
| **B1:** `VStack(spacing:16)` bookends plus a hidden slot equal the bookends alone. S1 measured, macOS: 216 alone / 216 hidden slot / 232 ZStack control (iOS `sizeThatFits`: 282/282/298). All four board layouts, gate-denied vs ads-absent, compare pixel-equal in-test | Direct (ZStack at 85c65cb4) |
| **C1:** the coordinator with `FakeAdProvider(refreshThrows: CancellationError())` throws and does not return `.failed` | Direct |
| **C2:** cancel the Live provider's refresh while `loadGate` holds it in flight. It throws `CancellationError`, and `bannerStatus` equals its value before the call | Direct |
| **C3:** unregister A while `sessionReady` is held. B's status and `shouldShow` record zero observation changes until `markReady()`. There is never a `.failed` | Mutation: drop the `CancellationError` catch in `load` |
| **R1:** three slots; `awaitReadyCallCount == 1`; the primer runs once | Mutation: per-slot `awaitReady` |
| **I1:** one slot re-rendered ≥10 times, so `update()` runs repeatedly; `registerCalls == 1` and one lease | Mutation: `attach(to:)` without its already-attached guard |
| **M1:** a slot mounted without `\.bannerSession` fires `onMissingSession` (test-swapped handler) and renders nothing | Mutation: drop the nil-session branch in `update()` |
| **B2:** open gate, readiness held, repoll. After 500ms there are 0 refreshes and no primer, then both happen | Mutation: bypass `sessionReady` |
| **B2′:** events arrive as `["ready","primer","adLoadStarted"]` with ready delayed 500ms | Mutation: primer before `awaitReady`. The base also encodes the wrong order at BannerSlotColdLaunchTests.swift:166 |
| **Gap 2:** two leases with interleaved loads get two distinct handles; unregistering A disposes only hA | Mutation: read the shared `bannerStatus` |
| **Gap 1:** dismissed today; clock +1 day; a repoll makes the slot visible and loaded | Mutation: drop repoll step 2 |
| **Pause:** pause then resume keeps the same lease (same `BannerSlotID`) and makes no second refresh call | Mutation: the host removes the slot while paused (v2.3.5 `if !isPaused`) |
| **Seed:** after `start()` resolves true, a newly mounted slot's first body renders the 50pt branch | Mutation: seed read from `slots` |
| **Cover env, E2E (lands with Phase 2):** with the gate open, open a board in the iOS cover and assert `monetization.banner.slot` inside the board's root element, so Today's slot under the cover can't satisfy it. It can't be a SwiftPM test: no connected `UIWindowScene` | Mutation: drop both the `\.theme`-level injection and the cover re-injection |
| **Cold launch:** fresh gate, no view mounted; `start()` makes `store.loadCallCount > 0` | Replaces BannerSlotColdLaunchTests test 1 |
| **#931 banner repoll + N15 (XCUITest)** | Regression; unchanged |
