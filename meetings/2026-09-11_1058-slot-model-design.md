# #1058 banner slot model — approved spec (rev 3.2)

PR #1062 · red base 85c65cb4 · Phase 1 latch e383fa1a · Phase 1b 553b8fcc · rev 2 approved (7c3946ba) · rev 3 = PM's final list + S1 · rev 3.1 = S1 findings + P3a disposition · rev 3.2 = Phase 2b.1 checkpoint follow-ups and rulings (a)(b)(c) · 2026-09-12

## Shape
- **`MonetizationUI.BannerSessionModel`** is a `@MainActor @Observable final class`, one per app session, built in `makeGameAppCore` step 5.
  - Observed state: `shouldShow: Bool?` (nil means pending), `providerSuppressed`, and `slots: [BannerSlotID: AdBannerStatus]`.
  - Read API: `isVisible`, `status(for:)`, and **`bannerView(for:) -> AnyView?`** (ruling b). It returns the provider's view for the slot's `.loaded` handle via `adProvider as? any BannerViewProviding`, and `nil` otherwise.
  - Unobserved state: `adProvider`, `adGate`, `onAdContext`, `sessionReady: ReadinessLatch`, `readyTask`, per-slot load `Task`s, and the set of registered IDs.
  - **Benign deviations in the 2b code, recorded here:**
    - `BannerReloadCoordinator` is built inside `init` from the same `adProvider`/`adGate`.
    - An extra `startTask` makes `start()` idempotent, so every caller joins the first run.
    - `now: @Sendable () -> Date` is injected so day-rollover tests can drive a clock.
  - `BannerSessionModel.disabled` is a `static let`, MainActor-isolated because the class is `@MainActor`. It may be injected in **exactly three places**, each for a stated reason: (1) SwiftUI previews, which have no app session; (2) snapshot fixtures that render slots without ads; (3) DEBUG test hooks that bypass monetization by design, today the three near-win covers (`SudokuNearWinCoverView`, `SudokuNearWinModalCoverView`, `MinesweeperNearWinCoverView`), which sit outside `makeGameApp`'s injection. **Any other use of `.disabled` is a CR reject.** The `\.bannerSession` environment default stays **`nil`**, so a missing injection reaches the DEBUG `onMissingSession` assertion.
- **`BannerSlotView` is a pure renderer.** Its whole body is `if session.isVisible, !isSuppressed { banner(status: session.status(for: id)).padding(h).padding(v) }`. It shows the ad through `session.bannerView(for: id)`, and no view holds a provider.
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
1. **`BannerSessionModel.load(id)`:** `catch is CancellationError { return }`, with no write to `slots`. Loads are cancelled only by `unregister(id)` or `hideAll()`. A handle that arrives after its load was cancelled (the SDK callback committed before `onCancel`) is disposed, not stored. The generic `catch` after it is unreachable by type and exists only because `ReadinessLatch.wait()` has untyped `throws`.
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
  - Only the three allow-listed uses inject `BannerSessionModel.disabled`: previews, snapshot fixtures, and the DEBUG near-win covers.

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
  4. Dispose the handle if the load was cancelled or the slot unregistered; run `hideAll()` on `.suppressed`, which collapses **every** slot, not just this one; otherwise store `slots[id]`.
- **Unreachable by ordering, not by type (one rule):**
  - `NoopAdProvider.refreshBanner()` throwing `AdProviderError.unsupported`.
  - A failing `BannerViewProviding` cast in `bannerView(for:)`.
  - Both need a load on a suppressed provider, and start step 2 plus the repoll suppression check keep a suppressed provider out of `load`.
- **Primer vs. load timing:**
  - `maybePresentOnAdContext` requests the sheet and returns (ATTPrimerCoordinator.swift:58-67), so loads start while the sheet is up and the first ad may be non-personalised until ATT is answered.
  - This matches today's `resolveGateAndLoad`.
  - C-33 still holds: `readyTask` requests the primer before it opens `sessionReady`, and every load waits on `sessionReady`.
- **What repoll adds beyond the latch** (`sceneDidBecomeActive()`):
  1. Join `start()`.
  2. Re-resolve the gate. Closed runs `hideAll()` without touching the provider. Open while `shouldShow != true` sets `shouldShow = true` (Gap 1).
  3. The suppression check, then `beginReadinessOnce()`, then `ensureLoads` for slots with no live handle, **retrying every `.failed` slot**. A loaded handle is not reloaded.

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
- **Dismiss (ruling a):** `dismiss()` stays **record-then-hide**. It records today's dismissal on `AdGate`, then `hideAll()` hides every slot and disposes every handle.
  - Reason: a banner that is hidden but whose dismissal never persisted is the worse failure. It would come back on the next launch or foreground as if the user never dismissed it.
  - The cost is that the collapse waits on the gate's store save.
- **Purchase:** `markPurchased` calls `bannerSession.refreshGate()`. It hides only if the re-resolved gate is closed, and leaves an open gate's banners untouched, so restore-with-nothing and failed purchases change nothing.

## Spec resolutions (Phase 2b and 2b.1)
These are decisions the brief left open. **Pinned** means a named mutation of the resolution turns a committed test red.
1. **The repoll path runs the suppression check too.** Otherwise a gate that was closed at cold launch and opens on a repoll would make a macOS Noop session call `awaitReady()` and show the primer. **Pinned:** `suppressedProviderFoundOnRepoll`.
2. **`refreshGate()` hides only when the re-resolved gate is closed.** **Pinned:** `purchaseHidesWithoutLoading` (closed) and `refreshGateWithOpenGateKeepsBanner` (open; red under an unconditional `hideAll()`).
3. **"Purchase hides without touching the provider" means no load and no readiness wait.** `hideAll()` still disposes handles, by spec. **Pinned:** `purchaseHidesWithoutLoading`.
4. **`unregister` writes to `slots` only when the slot has an entry.** Every write to an `@Observable` property notifies observers. **Pinned:** C3 `cancelledWaitWritesNothing`.
5. **A handle returned after its load was cancelled is disposed, and a stale load's cleanup never clears a newer load's entry** (via the `LoadEntry` token). **Pinned:** `lateHandleAfterCancellationIsDisposed` and `staleLoadCleanupKeepsNewerLoad`.
6. **Ruling (c), trigger-aware retry.** A `.failed` slot reloads only on its own (re-)registration or on a repoll, so mounting one slot never re-requests another slot's failed banner. **Pinned:** `failedSlotRetriesOnlyOnItsOwnTrigger`.
7. **Not pinned (14b):** the `readyTask != nil` guard in `ensureLoads()`.
   - It is reachable. `runStart` publishes `shouldShow` before its suppression await, so a slot can register while `isVisible` is true and readiness has not begun.
   - What it prevents is only a load parked on `sessionReady`, which never reaches the provider. `loads` is private, so no caller can observe the difference.
   - Kept as belt-and-braces, with a comment saying so.

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

## #931 E2E
- **Banner case:** at launch the fake store throws and the slot is hidden. After Home → activate, the root `scenePhase` observer runs a repoll, the gate opens, and the Today slot (registered while hidden, proven by S1 P1b) shows.
  - The shared assertion finds the slot by its "Advertisement" label: `TodayTabHost`'s `game.today.root` identifier shadows `monetization.banner.slot`, already on base `7ca5d73d` (#1072).
  - It dismisses the ATT primer when present (B2′ ordering puts the primer after the repoll) without requiring it.
- **Cover env:** both apps open a daily board through `GameRoot`'s cover and count "Advertisement" slots: Today + 1 while the board plays, Today while it is paused (also the Pause row's E2E pin). Host-driven E2E does not run in CI (#1039).
- **N15:** the first `beginReadinessOnce()` presents the primer; a second cycle doesn't re-present it.
- **Near-win covers** (`-uitest-near-win`, `-uitest-near-win-modal`) inject `.disabled`; a missing injection there fires M1's assertion (seen as the 2c E2E crash before `SudokuNearWinModalCoverView` was covered).

## Deletions and batch items
- **Delete in `BannerSlotView`:** the `ZStack`, `.task`, three `.onChange`s, `scenePhase`, three `@State`s, the lifecycle methods, and five init parameters.
- **Delete elsewhere:**
  - `MonetizationBootSignal`, `GameDeps.bootSignal`, and `bootMonetization`'s `bootSignal` parameter along with both `markReady` calls. **Done in 2d.**
  - `TodayTabHost`'s monetization parameters and `todayTabHostFireOnAdContext`. **Done in 2c.**
  - The `adProvider/adGate/bootSignal` threading, verified at `a9a48e1a` with `rg -l 'bootSignal|MonetizationBootSignal|adProvider|adGate'` over the three packages' `Sources`: **25 production files**. **Done in 2c.**
    - **GameAppKit (4):** `GameConfig`, `MakeGameApp`, `MakeGameApp+Helpers`, `TodayTabHost`.
    - **MinesweeperAppComposition (8):** `Live`, `Live+TabRoots`, `LiveRouteFactory`, `LiveRouteFactory+DailyBoardOpen`, `LiveRouteFactory+Helpers`, `LiveRouteFactory+ReplayDailyBoard`, `MinesweeperAppComposition`, `Preview`.
    - **MinesweeperUI (5):** `MinesweeperBoardLoaderView`, `MinesweeperBoardView`, `MinesweeperDailyOpenGuardView`, `MinesweeperDailyReplayLoaderView`, `MinesweeperFreshBoardLoaderView`.
    - **SudokuAppComposition (5):** `Live`, `Live+TabRoots`, `LiveRouteFactory`, `SudokuAppComposition`, `Preview`.
    - **SudokuUI (3):** `BoardLoaderView`, `BoardView`, `BoardView+Layout`.
    - Count history, 20 → 23 → 25: rev 3.1 said 20, and the lead's recount said 23. The recount's 23 is this list without the two `Preview.swift` files (25 − 2 = 23); those also build `FakeAdProvider`/`AdGate` and pass them into the composition struct's init, so they change too, giving 25. How rev 3.1 reached 20 was not recorded, so the 20 → 23 gap is not itemized; this verified list is the source of truth.
  - `BannerSlotColdLaunchTests`. **Done in 2c.**
- **Deleted in the 2c commit (PM ruling), not 2d:** `scan/bannerslot_bootsignal` plus its `lint.yml` job, header index line and "seven job names". 2c removes the `bootSignal:` parameter the gate checks. Its guarantee is now carried by the readiness latch inside the carrier (`AdProvider`) and by M1's DEBUG `onMissingSession` assertion on a lost `\.bannerSession` injection.
- **Keep:** the in-view padding, `BannerSlotCollapsedHeightTests`, the CLAUDE.md commit, and the latch.
- **Retarget** to an injected session, with baselines byte-identical: TodayTabHostTests, BoardViewBannerTests (construction only), BannerSlotDarkBandRegressionTests, MinesweeperBoardSnapshotTests, and HubSettingsBannerTests.
- **Padding:** `BoardView+Layout.swift:51` and `MinesweeperBoardView.swift:534` move their external padding to `horizontalPadding:`.
- **Collapsed-height test:** the header names both `themedBanner`s, and the rows use the real per-layout configs.
- **Test support:** `FakeAdProvider.awaitReadyCallCount` and a `loadGate` on `FakeAdMobBridge`.

### Phase 2d — deletions and survivors

Deletions-only pass (#1076). No behavior change, no new seam.

**Deleted**
- `MonetizationBootSignal` (subject deleted): the whole file. Its job — gating
  the first ad request on boot completion — is now the provider's own
  `ReadinessLatch` inside `AdProvider.awaitReady()`, which `BannerSessionModel`
  already awaits. The signal was redundant since the session model landed.
- `GameDeps.bootSignal` (subject deleted): no reader once `bootMonetization`
  stopped taking a `bootSignal` parameter.
- `bootMonetization`'s `bootSignal` parameter and both `markReady()` calls
  (subject deleted): same reason: nothing awaits the signal any more.
- `AdGate.lastKnownShouldShowBanner` + its backing `Mutex` (subject deleted):
  a layout-reservation hint for the old per-screen `BannerSlotView` lifecycle.
  The session-scoped `BannerSessionModel` carries its own `shouldShow` state,
  so the hint has had no reader since 2c.
- `AdGateLayoutHintTests.swift` (subject deleted): tested only the removed
  hint.
- `GameDeps.adProvider` / `GameDeps.adGate` (subject deleted): the only
  readers were `SudokuAppComposition` / `MinesweeperAppComposition`'s stored
  `adProvider` / `adGate` fields, which are also deleted below (test-only
  readers, no production reader). `makeGameAppCore` never read these off
  `GameDeps` — it holds its own local `adProvider` / `adGate` (see survivors).
- `SudokuAppComposition.adProvider` / `.adGate` and
  `MinesweeperAppComposition.adProvider` / `.adGate` (subject deleted): the
  only readers were `CompositionTests` / `MinesweeperAppCompositionTests`.
  Removed the stored properties, init params, `Live.swift` fills, and
  `Preview.swift` args (and the now-unused local `FakeAdProvider()` in each
  `Preview.swift`).
- `CompositionTests.liveCompositionExposesMonetizationDeps` (subject deleted
  for the dropped lines): dropped the `adProvider` type assertion and the
  `_ = composition.adGate` smoke; the test stays for its `iapClient` assertion.
- `CompositionTests.previewCompositionUsesFakes` /
  `.testsCompositionUsesFakes` (subject deleted for the dropped line): dropped
  the `adProvider` assertion line each; the rest of each test is unchanged.
- `MinesweeperAppCompositionTests.liveFactoryConstructs` /
  `.previewFactoryConstructs` (subject deleted for the dropped lines): dropped
  `_ = bag.adProvider` / `_ = bag.adGate`; the other field smokes stay.
- `MinesweeperAppCompositionTests.liveAdProviderIsLiveOnIOSNoopOnMac` (subject
  deleted): asserted `bag.adProvider`'s concrete type, which no longer exists
  on the bag.

**Coverage gap — closed by 2d.1 (PM ruling):** deleting
`liveAdProviderIsLiveOnIOSNoopOnMac` removed the only test of
`makeGameAppCore`'s Live/Noop `AdProvider` platform selection
(`MakeGameApp.swift:142-160`, the `#if os(iOS)` branch inside
`resolveAdProvider`). That branch is a closure inside `makeGameAppCore`, and
no unit test can reach it without refactoring production code. 2d.1 pins it
at compile time in the carrier instead: `LiveAdMobAdProvider.init(bannerAdUnitID:)`
is now wrapped in `#if canImport(GoogleMobileAds)`, the same guard
`LiveAdMobBridge` uses. On macOS the SDK is absent, so the public init does
not exist. A flipped branch that constructs the live provider on macOS fails
the macOS build. `internal init(bridge:)` stays unguarded, so the macOS-host
provider tests with fake bridges still run.

**Survivors (must stay, with production reader)**

| Symbol | Production reader |
|---|---|
| `ReadinessLatch` | `Packages/AppMonetizationKit/Sources/MonetizationUI/BannerSessionModel.swift:71` (`sessionReady`); `Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobAdProvider.swift:30` (`readiness`) |
| `AdProvider.awaitReady()` | `Packages/AppMonetizationKit/Sources/MonetizationUI/BannerSessionModel.swift:203` (`try await provider.awaitReady()`) |
| `BannerSessionModel` | `Packages/GameAppKit/Sources/GameAppKit/GameRoot.swift:62,94,104,121,125,195` (stored, injected via `\.bannerSession`, driven on scenePhase + start) |
| `makeBannerSession(...)` | `Packages/GameAppKit/Sources/GameAppKit/MakeGameApp.swift:173` |
| M1 `onMissingSession` | `Packages/AppMonetizationKit/Sources/MonetizationUI/BannerSlotRegistration.swift:34` (definition), `:63` (invoked when a slot renders with no injected session) |
| `makeGameAppCore`'s local `adProvider` | `Packages/GameAppKit/Sources/GameAppKit/MakeGameApp.swift:142` (declared), read at `:173` (`makeBannerSession`) and `:375` (`bootMonetization`) |
| `makeGameAppCore`'s local `adGate` | `Packages/GameAppKit/Sources/GameAppKit/MakeGameApp.swift:123` (declared), read at `:173` (`makeBannerSession`) and `:178` (`MonetizationStateController`) |

`GameDeps.adProvider` / `GameDeps.adGate` are gone because `makeGameAppCore`
never read them off the `GameDeps` bag it builds — it closes over its own
local `adProvider` / `adGate` directly — and the only other readers
(`SudokuAppComposition` / `MinesweeperAppComposition`'s stored fields) are
deleted in this same phase.

### Phase 2e — #1084 dismiss placement

AdMob policy forbids app content over or immediately adjacent to the
creative; a manual tap sweep hit the ad on 2 of 9 taps against the ✕
overlaid at the creative's top-trailing corner. `BannerSlotView.banner(...)`
now pins the creative to its native 320×50 size, leading-aligned in the
slot band, and moves the ✕ into the gutter past the creative's trailing
edge (`.overlay(alignment: .trailing)` + an `.alignmentGuide(.trailing)`
that reads the ✕'s leading edge instead of its own trailing edge), at a
44×44pt hit target. Pinned by `BannerSlotDismissPlacementTests`, which reads
the creative/✕/slot-band frames via a test-only `BannerSlotGeometryKey`
anchor-preference triple and asserts no overlap at 402pt, 393pt, and 375pt
host widths.

**Glyph contrast (uiux-bugfix-plan P1-6, #1084):** an after-crop review found
the ✕ nearly invisible on a warm paper background at 12pt with
`Color.secondary.opacity(0.7)`. The glyph is now 16pt inside the same
44×44pt target, and every `dismissTint` — the default and the four host
call sites (`BoardView+Layout`, `MinesweeperBoardView`, `TodayTabHost`,
`LiveRouteFactory`) — drops the `.opacity(0.7)`, keeping the underlying
color token. A second PM pass on a new crop found `theme.accent.muted` still
read as a ghost on the paper ground even at 16pt and full opacity, so the
three themed hosts (`BoardView+Layout`, `MinesweeperBoardView`,
`TodayTabHost`) now pass `theme.text.secondary` instead — the same token
those calls already use for `captionColor`, not a new color.
`LiveRouteFactory` (the un-themed Settings route banner) already passed
`Color.secondary` and is unchanged.

**PM ruling — narrow-width padding, final (#1084):** the ruled constraint is
"the ✕ stays fully on-screen", **not** "the ✕ stays inside the visible slot
band" — an important correction from an earlier draft of this rule. On a
host too narrow to fit `needed = creativeWidth + dismissTargetSize = 364` at
the full nominal padding on ONE side, the padding shrinks symmetrically
instead of letting the ✕ run off-screen: `padding = nominalPadding` while
`width ≥ needed + nominalPadding` (380pt at the shipped constants), else
`max(0, (width − needed) / 2)`. This is a ONE-SIDED comfort check
(`needed + nominalPadding`), not the two-sided `needed + 2×nominalPadding`
an earlier draft used — the two-sided version gave 393pt (the most common
iPhone width) a 14.5pt padding while 402pt kept 16pt, a visible, unjustified
inconsistency between the two most common widths once someone noticed it.
Implemented as a custom `Layout` (`BannerSlotBandLayout`), not
`onGeometryChange` + `@State` — the PM's own call: the state-loop approach
draws one frame at the wrong padding before correcting.
- **402pt** (≥ 364 + 16 = 380): padding stays the full nominal 16pt,
  byte-identical to the pre-shrink geometry — creative 16…336, ✕ 336…380,
  slot band 16…386.
- **393pt** (also ≥ 380): SAME full 16pt padding as 402pt — creative 16…336,
  ✕ 336…380, slot band 16…377. The ✕ ends 3pt past the band's own trailing
  edge but 13pt inside the screen; that's fine under the on-screen (not
  in-band) constraint.
- **375pt** (< 380): `(375 − 364) / 2 = 5.5`, so the padding shrinks to
  5.5pt on each side — creative 5.5…325.5, ✕ 325.5…369.5, slot band
  5.5…369.5 — the ✕ stays fully on-screen with a 5.5pt margin instead of
  overflowing.

**PM ruling — zero gap between the creative and the ✕ (#1084):** "Zero gap
kept (creative.maxX == dismiss.minX): the policy concern is a control
overlapping or reading as part of the ad; the 44pt target starts at the ad
edge but the 16pt glyph is centred 14pt away from it, fully outside, on the
app's own ground. A gap would push 375pt hosts back below a 44pt target."

### Phase 2f — Settings view-model identity (#1078 final-head E2E)

The #1078 final-head E2E run turned Minesweeper N19
(`test_clearCacheCancelAndFailureToast_N19`) red at `d25702c0` while it stays
green on `origin/main` (base 3/3, head 0/4; idb tree dumps identical except the
`settings.storage.cacheReady` anchor never appears at head). Mechanism, the
#909 shape: both apps' `.settings` `navigationDestination` builders mint
`SettingsViewModel(...)` inline, SwiftUI re-invokes that builder on any
ancestor re-render, and `SettingsView` held the model as a plain `@Bindable`
property, so a re-render replaced the instance whose one-shot
`.task { bootstrap() }` had already set `isCacheStateReady`; `.task` does not
re-fire for the same identity. This PR adds the ancestor re-render:
`GameRoot` now reads `@Environment(\.scenePhase)` for the banner repoll, so
the launch-time `inactive → active` change re-renders it right after Settings
mounts. Sudoku N19 was already red on base for the same class (#1088).

Fix: `SettingsView` owns the model as `@State` (`_viewModel =
State(initialValue:)`), shared by both apps from one place. Correct because
everything the builders capture is a composition-time `let` (Sudoku:
`generatorVersionLabel`, `appVersion`, `persistence`, `errorReporter`,
`toastController`; Minesweeper: `appVersion`, `persistence`, `errorReporter`,
`toastController`), so the first instance is complete. Pinned by
`SettingsViewModelIdentityTests` (GameAppKit): an ancestor that mints model
"A" on its first body evaluation and "B" on every later one, re-rendered
through an `@Observable` tick in a headless `NSHostingView`; the host's pixels
must not change (the Version row still reads "A"), and a "B"-first host must
render differently so the compare cannot pass vacuously. Mutation (plain
property restored) → red on the identity row. E2E: Minesweeper N19 2/2 with
the fix.

### Phase 2g — whole-PR CR closures (#1078)

Three findings from the PM's whole-PR code review at `a5ebe93f`, closed in one
commit:

- **MAJOR-1 — `HubSettingsBannerTests` deleted.** Since 2c the slot holds no
  provider, so all seven tests built a `FakeAdProvider` wired to nothing and
  asserted `refreshCallCount == 0`, which holds for any production code. The
  behaviour they named is pinned elsewhere: the gate decision by the `AdGate`
  suites; "gate allows → the slot is live" by
  `BoardViewBannerTests.running_andGateAllows_bannerMountIsActive` and
  `runningBoard_rendersLoadedBanner`; "gate denies / Remove Ads purchased →
  the slot collapses" by
  `BoardViewBannerTests.running_butGateDenies_bannerSlotCollapsesToEmpty` and
  `BannerEntitlementWiringTests` (purchase / restore / updates collapse the
  slot); "a load that finds the gate closed collapses every slot" by
  `BannerSessionModelFollowUpTests`. The SudokuKit "hubs" batch filter drops
  the name (62 tests / 9 suites).
- **MINOR-1 — suppression before publish.** `runStart()` published
  `shouldShow = open` and only then awaited `providerCanServe`; on a macOS
  cold launch with an open gate that painted one 50pt spinner band before the
  `NoopAdProvider` suppression collapsed it. Now the suppression is resolved
  first (the hide-generation capture stays before the first await;
  `sceneDidBecomeActive` already had this order). Pinned by
  `BannerSessionModelSuppressionOrderTests`: an actor provider holds its
  `bannerStatus` read on a latch and the test samples `isVisible` while
  `runStart()` is suspended in it — `[false, false]` with 2g; the mutation
  (old order restored) samples `[true, false]`, the frame in question.
- **MINOR-2 — no fixed sleeps in the negative primer rows.**
  `TodayTabHostTests.firstAdContextNeverPresentsWhenDetermined` and
  `declinedPrimerIsNotReoffered` hold readiness on the fake's `markReady()`
  seam and wait for a positive signal that the readiness path ran (a
  registered slot's `refreshBanner()` call, which only happens after ready →
  ad context → `sessionReady`; for the repoll, the retry of a slot whose loads
  are scripted to fail) before asserting the primer did not present.

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
| **M1, composition write — E2E-only:** `makeGameApp`'s `.environment(\.bannerSession, bannerSession)` on the `GameRoot` value. No unit pin is reachable: `makeGameAppCore` is `private` (`MakeGameApp.swift:81`) and constructs Live types (`LivePersistence`, `LiveAdMobAdProvider`) that an unentitled SwiftPM runner cannot build — the same limit recorded at `MemoizedTabRootsTests.swift:9`. Outside E2E the loud signal is M1's DEBUG `onMissingSession` assertion, which crashes any simulator or device DEBUG run on the first banner mount (device evidence E1 exercises that path). Dropping the write crashes every E2E launch the same way (Today's slot mounts under `GameRoot`). Host-driven E2E does not run in CI (#1039) | Mutation: drop the write |
| **B2:** open gate, readiness held, repoll. After 500ms there are 0 refreshes and no primer, then both happen | Mutation: bypass `sessionReady` |
| **B2′:** events arrive as `["ready","primer","adLoadStarted"]` with ready delayed 500ms | Mutation: primer before `awaitReady`. The base also encodes the wrong order at BannerSlotColdLaunchTests.swift:166 |
| **Gap 2:** two leases with interleaved loads get two distinct handles; unregistering A disposes only hA | Mutation: read the shared `bannerStatus` |
| **Gap 1:** dismissed today; clock +1 day; a repoll makes the slot visible and loaded | Mutation: drop repoll step 2 |
| **Pause:** pause then resume keeps the same lease (same `BannerSlotID`) and makes no second refresh call | Mutation: the host removes the slot while paused (v2.3.5 `if !isPaused`) |
| **Pause, host wiring (2c.1):** the real `BoardView` and `MinesweeperBoardView`, rendered over a started session with a loaded slot whose provider serves a height probe: banner height > 0 running, 0 paused, and 0 terminal on Minesweeper | Mutations: Sudoku host `isSuppressed: false`; Minesweeper host `isSuppressed: false`; Minesweeper drops `isTerminal` |
| **Start / repoll window (2c.1):** a `refreshGate()` hide landing while `runStart` or `sceneDidBecomeActive` is suspended on its gate read stays hidden with no refresh; reopening the gate and repolling then shows the banner and loads it exactly once | Mutations: drop `runStart`'s generation checks; drop `sceneDidBecomeActive`'s; a sticky bail flag; skip `beginReadinessOnce()` in the repoll |
| **Entitlement UI order (2c.1):** with the entitlement hook held, the purchase, restore and updates-listener paths already show their message and toast (and `.idle`) | Mutation: await the hook inside `markPurchased()` again |
| **Seed:** after `start()` resolves true, a newly mounted slot's first body renders the 50pt branch | Mutation: seed read from `slots` |
| **refreshGate, open gate:** a loaded slot survives `refreshGate()`; nothing is disposed | Mutation: unconditional `hideAll()` |
| **Late handle:** a load held past its cancellation (`dismiss()`) returns a handle; it is disposed | Mutation: delete the post-cancellation dispose |
| **Stale cleanup:** load 1 cancelled, then load 2 for the same slot; load 1's cleanup keeps load 2's entry (no third load) | Mutation: unconditional `loads[id] = nil` in the defer |
| **Suppressed load result:** a load that finds the gate closed collapses every slot and disposes the other slot's handle | Mutation: write `.suppressed` for that slot only |
| **`bannerView(for:)`:** non-nil for a loaded slot with a `BannerViewProviding` host; nil with no handle, no host, or a suppressed provider | Mutation: always return nil |
| **Retry trigger (ruling c):** A `.failed`; B registers, A is not retried; a repoll retries A; re-registering a failed C retries it | Mutation: retry every `.failed` slot on any trigger |
| **Cover env, E2E-only by design:** with the gate open, open a daily board through `GameRoot`'s cover and count "Advertisement" slots: Today + 1 while it plays, Today while paused (Today's subtree stays in the accessibility tree under a `.fullScreen` cover, and its slot identifier is shadowed, #1072). It can't be a SwiftPM test: no connected `UIWindowScene`. Host-driven E2E does not run in CI (#1039) | Mutation: drop both the `\.theme`-level injection and the cover re-injection |
| **Cold launch:** fresh gate, no view mounted; `start()` makes `store.loadCallCount > 0` | Replaces BannerSlotColdLaunchTests test 1 |
| **#931 banner repoll + N15 (XCUITest)** | Regression; unchanged |
