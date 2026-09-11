# #1058 banner slot model — design for PM review (no code yet)

PR #1062 · red base 85c65cb4 · Phase 1 provider latch e383fa1a · 2026-09-11

## Shape
- **`MonetizationUI.BannerSessionModel`** is a `@MainActor @Observable final class`, one per app session. It is built in `makeGameAppCore` step 5 from `adProvider`, `adGate`, `bannerHost`, `onAdContext = attPrimer.maybePresentOnAdContext`, and `now: () -> Date`.
  - Observed state: `shouldShow: Bool?` (nil means pending), `providerSuppressed`, and `slots: [BannerSlotID: AdBannerStatus]`.
  - Unobserved state: `startTask`, `primerTask` (runs once per session), per-slot load `Task`s, and the set of registered IDs.
- **`BannerSlotView` is a pure renderer.** Its whole body is `if session.isVisible, !isSuppressed { banner(status: session.status(for: id)).padding(h).padding(v) }`.
  - It has no `ZStack`, `.task`, `.onAppear`, `.onChange`, `@State` or `scenePhase`.
  - When hidden it produces zero subviews, so a parent with non-zero spacing adds no gap. That fixes B1.
  - Parameters: theme colours, `horizontalPadding`/`verticalPadding`, and `isSuppressed` (the host's paused or terminal state).
  - The ✕ button calls `session.dismiss()`. That is a user action, not a lifecycle hook.

## Slot registration without depending on the rendered subtree: a `@StateObject` lease
`BannerSlotView` stores a `BannerSlotRegistration: DynamicProperty` that contains `@Environment(\.bannerSession)` and `@StateObject var lease = BannerSlotLease()`.

- SwiftUI calls `update()` on the view node before every body evaluation. It calls `lease.attach(to:)`, which is idempotent. The first call adds the ID to the unobserved set and schedules `ensureLoads()` for the next main-actor turn, so nothing observed is mutated during a view update.
- The lease's `isolated deinit` calls `unregister(id)`, which cancels the slot's load and disposes its handle.

Why this option:
- The `@StateObject` autoclosure runs once per view identity. A `@State` initial value is rebuilt and thrown away on every parent re-render, which would churn register/unregister.
- Dynamic properties are installed whether or not the body renders anything. A modifier on a `Group` is not, and that was the original defect.
- Host-side registration would copy every host's mount condition (`!isPaused`, `!isTerminal`, the size-class branch) into four places. That is the #448 drift class.

**This is unconfirmed until spike S1 passes, and S1 gates the build.**

## Start and ordering
- `GameRoot` takes `bannerSession` as an init parameter.
  - It injects `.environment(\.bannerSession, …)` on `shellContent`, which covers the tabs and the macOS push destinations.
  - It also re-injects it on the cover content next to `\.gameChrome` (GameRoot.swift:173).
  - It starts the model inside the existing `.onAppear { Task { … } }` (#361), next to `bootstrap()`.
- `bootMonetization` keeps its own Task (MakeGameApp.swift:381) and runs concurrently. The gate resolves while UMP is still up; loads wait for readiness.
- **`start()`** is idempotent through `startTask`:
  1. `shouldShow = await adGate.shouldShowBanner(now())`. If closed, stop.
  2. If `bannerStatus == .suppressed`, set `providerSuppressed` and stop. The macOS Noop provider never waits and never shows the primer (#968).
  3. `ensureLoads()`.
- **`load(id)` is the only code that touches the provider.** Cold launch, a new registration and a repoll all go through it:
  1. `try await adProvider.awaitReady()`
  2. `await primerOnce()`. This uses `primerTask ??= Task { await onAdContext?() }`. `maybePresentOnAdContext` only requests the sheet and returns; it does not wait for it (ATTPrimerCoordinator.swift:58-67).
  3. `try Task.checkCancellation()`
  4. `try await reloadCoordinator.reloadIfGateOpen(now:)`
  5. If the slot unregistered in the meantime, dispose the returned handle. If the result is `.suppressed`, run `hideAll()`. Otherwise store `slots[id] = status`.
- #940 is fixed by ordering alone. Readiness can only open after `initialize()`, which the boot sequence calls after the UMP form is dismissed, and readiness comes before the primer in the same function.

## CancellationError (addendum 1)
- Only two things cancel a load: `unregister` (the slot's identity ended) and `hideAll` (dismiss or purchase).
- A cancelled `awaitReady()` leaves `load` before the primer and before the provider. The slot's entry has then either been removed (unregister) or reset to `.notInitialized` (hideAll). It is never `.failed`.
- `BannerReloadCoordinator.reloadIfGateOpen` becomes `async throws(CancellationError)`. It re-throws `CancellationError` before the generic catch that maps to `.failed`, so "Ad unavailable" only ever means a real load failure.

## Repoll: what the model guarantees beyond the latch (addendum 2)
The latch only stops the provider's network call before `initialize()` completes. It knows nothing about the primer, the gate, dismissal, or which slots are mounted.

`GameRoot` observes `.onChange(of: scenePhase)` on `shellContent`. That view is always mounted and never renders `EmptyView`. The boards' flush handlers are separate observers on other views, and nothing in this design touches them. On `.active` it calls `sceneDidBecomeActive()`:
1. `await start()`. A cold-launch `.active` that arrives before `.onAppear` joins `start()` instead of opening a second path.
2. Re-resolve the gate.
   - Closed: `hideAll()`. Remove Ads, dismissed-today and clock-tamper decisions never touch the provider.
   - Open while `shouldShow != true`: set `shouldShow = true`. A banner dismissed yesterday comes back (Gap 1).
3. `ensureLoads()`. Every slot without a live handle goes through `load(id)`, so the primer ordering is the same as at cold launch.
   - A handle that is already loaded is not reloaded. Today every foreground requests a new banner, even though `GADBannerView` refreshes itself.
   - **Please confirm this change.**

## Split state (Gap 2), dismiss and purchase
- **Session-wide:** the gate decision, the suppressed flag, readiness (owned by the provider), the primer (`primerTask` plus `hasOffered`), and dismissed (`shouldShow = false`).
- **Per slot**, keyed by the lease UUID: status, handle, load Task, and dispose.
- Two slots mounted together (Today under the cover, plus the board) mean two leases, two loads and two handles. That keeps one `BannerView` per superview.
- **Handle race:** today a caller runs `refreshBanner()` and then reads the actor's single shared `bannerStatus`, and concurrent slots can interleave there. Fix: `refreshBanner()` returns `AdBannerHandle` (`@discardableResult`), and the coordinator builds `.loaded(handle)` from the return value.
  - That touches all 6 conformers again. `Noop` throws `AdProviderError.unsupported`, which is unreachable behind start step 2.
- **Dismiss** hides all slots at once and disposes every handle. Today other mounted slots stay visible until they next resolve the gate.
- **Purchase:** `MonetizationStateController.markPurchased` also calls `bannerSession.refreshGate()`, which runs `hideAll()`.

## Pause churn
- Today, `if !viewModel.isPaused` (Sudoku :49/:80; MS :646, which also checks `!isTerminal`) destroys the slot. Every resume re-requests a banner, and backgrounding auto-pauses, so every app switch costs a request.
- Design: hosts always build the slot and pass `isSuppressed: viewModel.isPaused`; MS adds `|| isTerminal`.
  - The identity, the lease and the handle survive the pause, and resume shows the same banner again.
  - A hidden slot has zero subviews, so spacing doesn't change.
  - A size-class switch still creates a new identity and a new load, which is acceptable.

## #723 seed and the pending window
- The seed is `session.shouldShow`, read synchronously in `body`.
- The model is built before `GameRoot` exists, so in production no slot can find the model missing.
- After the session's first gate resolution, every newly mounted slot (board, hub or Settings) reserves 50pt from its first frame.
- While pending (`nil`) the slot renders nothing: 0pt and no spacing.
- One reflow is still possible: a slot that mounts during the session's first gate read, such as a board deep-linked at cold launch or a slow CloudKit read. That matches today's pending behaviour. I can't prove no board is reachable in that window, only that the window ends with the first read.
- `AdGate.lastKnownShouldShowBanner`, its `Mutex` and `AdGateLayoutHintTests` lose their only consumer, so they are deleted.

## A missing model fails loudly
- `update()` with no session calls `BannerSessionModel.onMissingSession`. That is `assertionFailure` in DEBUG, and the slot renders nothing in Release.
- A test swaps the handler and asserts it fires for a slot mounted without the environment.
- Previews and snapshots inject `BannerSessionModel.disabled`, which never shows and has no provider.

## #931 E2E: the test code doesn't change
- **Banner case (`-uitest-fake-ad-gate-repoll`):**
  1. At launch, the fake store throws, so `shouldShow` is false and the slot anchor is absent.
  2. Home button, then activate: the `scenePhase` observer runs a repoll, and the gate is now open.
  3. The Today slot, registered while hidden (this is what S1 must prove), becomes visible, and `monetization.banner.slot` appears.
- **N15:** that same repoll's first load awaits readiness (immediate for UITestNoop) and then presents the primer. On the second background/foreground cycle, the loaded slot is not reloaded, and `primerTask` plus `hasOffered` prevent a second presentation.
- Only comments that name `BannerSlotView`'s `.onChange` need edits: ScenePhaseRepollE2ESupport, UITestFakeSeams, UITestOverrides, and UITestLaunchArg:81.

## Deletion list for the build
- **`BannerSlotView`:** the `ZStack`, `.task`, the three `.onChange`s, `scenePhase`, the three `@State`s, the three lifecycle methods, and the `adProvider/adGate/bannerHost/onAdContext/bootSignal` init parameters.
- **Boot signal:** `MonetizationBootSignal.swift`, `GameDeps.bootSignal`, the `bootSignal` parameter of `bootMonetization` and both `markReady` calls.
- **`TodayTabHost`:** its four monetization parameters and `todayTabHostFireOnAdContext`.
- **Threading:** the board, loader and route-factory `adProvider/adGate/bootSignal` parameters, which are the 20 Swift files in the bootSignal grep across both apps.
- **Scan gate:** `mise-tasks/scan/bannerslot_bootsignal`, plus the `lint.yml` job, header item 7 and the "seven job names" line.
- **Tests and hint:** `BannerSlotColdLaunchTests.swift` and `AdGate.lastKnownShouldShowBanner`.
- **Keep:** the padding inside the view, `BannerSlotCollapsedHeightTests`, the CLAUDE.md commit, and the Phase 1 latch.
- **Retarget** to an injected session, with baselines staying byte-identical: TodayTabHostTests, BoardViewBannerTests, BannerSlotDarkBandRegressionTests, MinesweeperBoardSnapshotTests, and HubSettingsBannerTests.

## Batch items
- `BoardView+Layout.swift:51` and `MinesweeperBoardView.swift:534`: replace the external `.padding(.horizontal, theme.spacing.medium)` with `horizontalPadding: theme.spacing.medium`.
- `BannerSlotCollapsedHeightTests`:
  - The header at :42-46 mixes up two functions: Sudoku's static `LiveRouteFactory.themedBanner` (Today, Practice and Settings, 16/12) and the private `BoardView+Layout.themedBanner` (the board). The fix names both.
  - Rows :86-87 become the real per-layout configs: Sudoku compact medium/0, Sudoku mac 0/0, MS compact medium/0, MS regular 0/0.
  - The header should say this suite pins height only. Spacing is B1's job.

## Prerequisites (any ? blocks the build)
| # | Assumption | Status |
|---|---|---|
| P1 | For `@StateObject` inside a `DynamicProperty`: the thunk runs once per identity, `update()` runs even when the body renders nothing, and deinit runs when the identity is removed | ? spike S1 |
| P2 | `isolated deinit` (SE-0371) compiles on the CI toolchain (local: Swift 6.3.2, tools 6.2) | ? S1 compile check; fallback is a `deinit` that hops to MainActor in a Task |
| P3 | Environment set on `GameRoot` reaches the iOS cover and the macOS push destinations | ? the near-win modals re-inject `\.theme` by hand, so this isn't assumed; explicit cover injection plus a test |
| P4 | UMP's completion handler fires only after the form is dismissed | ✓ UMPConsentForm.h:22-26 (verified by the lead) |
| P5 | The primer requests the sheet and returns without waiting for it | ✓ ATTPrimerCoordinator.swift:58-67 |

## Test plan (bounded waits, no baselines re-recorded)
Model-level tests can't compile against 85c65cb4. Their "red" is a mutation run recorded in the PR, which reverts exactly the guarantee being tested. Tests marked "direct" are red on the base itself.

| Test | Level | Red evidence |
|---|---|---|
| **S1:** a hidden slot in a `VStack` registers exactly once; 10 parent re-renders still leave one lease; removing the slot unregisters it; a missing environment fires the handler | iOS simulator host + NSHostingView | Gate: runs first |
| **B1:** bookends in `VStack(spacing:16)` with a hidden slot are the same height as the bookends alone (216 vs 232). Also all four real board layouts, rendered gate-denied vs ads-absent, compare pixel-equal inside the test | NSHostingView | Direct (ZStack at 85c65cb4) |
| **B2:** gate open, `FakeAdProvider(readinessHeld:)`, `sceneDidBecomeActive()`. After 500ms, `refreshCallCount == 0` and the primer hasn't run. After `markReady()`, both happen | model | Mutation: remove `awaitReady` from `load` |
| **B2′:** events arrive as `["ready","primer","adLoadStarted"]` with ready delayed 500ms | model | Mutation: swap the order. The base itself encodes the wrong order at BannerSlotColdLaunchTests.swift:166 |
| **Gap 2:** two leases with interleaved delayed loads get two distinct handles. Unregistering A disposes only hA; B stays `.loaded(hB)` | model | Mutation: go back to reading the shared `bannerStatus` |
| **Gap 1:** `dismissedDate` is today; move the clock forward one day; a repoll makes the slot visible and loads it | model | Mutation: drop repoll step 2 |
| **Cancel:** unregister while readiness is held. After `markReady()` there is no refresh and never `.failed`. The coordinator re-throws `CancellationError` | model + coordinator | Coordinator part is direct: on the base, a thrown `CancellationError` becomes `.failed` |
| **Cold launch:** fresh gate, no view mounted; `start()` makes `store.loadCallCount > 0` | model | Replaces BannerSlotColdLaunchTests test 1 |
| **#931 banner repoll + N15** | XCUITest | Regression; unchanged |
