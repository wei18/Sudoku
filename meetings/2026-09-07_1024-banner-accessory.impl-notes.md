# impl-notes — #1024 banner → tabViewBottomAccessory (session/brisk-stork-isio)

Running log during implementation. Post-hoc meeting log is separate.

## PM Task A — sentinel-accessory render test (2026-09-08, post-merge follow-up)

`Packages/GameShellKit/Tests/GameShellUITests/RootShellViewBottomAccessoryRenderTests.swift`
(new, `#if os(iOS)`). Renders the real `RootShellView` with a sentinel
`bottomAccessory` in a `UIHostingController`/`UIWindow`, proving OUR wiring
(not just the #1029 API spike) actually threads content through
`.tabViewBottomAccessory`.

Dead end tried first, documented in the file: accessibility-identifier
lookup. `.accessibilityIdentifier(_:)` on plain `Text` does not surface via
`UIAccessibilityIdentification` or the `UIAccessibilityContainer` count/index
methods when walked in-process in a headless XCTest host — confirmed via
`-recursiveDescription`, which showed the identifier-less content view
(`SwiftUI.CGDrawingView`) sitting directly inside a real, populated
`SwiftUI.UIKitTabBarBottomAccessory` container.

Final proof strategy: find the container by class name (contains
"BottomAccessory") and assert it has real content — contrasted against an
`EmptyView` accessory (separate test) to rule out "the container always has
stray children" as a false-positive explanation. Both tests pass on iOS
Simulator; `@MainActor` added to the polling helpers after a Main Thread
Checker warning surfaced on the first pass (`.subviews` off-main after
`Task.sleep`).

## PM Task B — `-uitest-open-ad-gate` launch arg (2026-09-08, post-merge follow-up)

New DEBUG-only `UITestLaunchArg.openAdGate` ("-uitest-open-ad-gate") +
`UITestAlwaysOpenAdGateStateStore` (UITestFakeSeams.swift) + a new branch in
`resolveAdGateStore` (MakeGameApp+UITestOverrides.swift), inserted BEFORE the
existing `-uitest-fake-ad-gate-repoll` guard so that guard's own lines stay
byte-identical (verified via `git diff` scoped to the function — zero changes
to the repoll branch's text). `resolveAdProvider` is not touched at all —
confirmed both by the diff (function doesn't appear in it) and by a runtime
test (`resolveAdProviderStillReturnsMakeLiveResult`) proving it still returns
whatever `makeLive()` produces.

Release-unreachability proof: `swift build -c release` succeeds (a leaked
reference to a DEBUG-only symbol from outside `#if DEBUG` would fail to
compile), AND `strings` over every compiled `.o` in the Release
`GameAppKit.build` directory returns ZERO hits for `uitest-` (not just this
one arg — the whole family), confirming stripped, not just visually
`#if DEBUG`-fenced.

New tests: `UITestAlwaysOpenAdGateStateStoreTests.swift` (3 tests) — the fake
run through a REAL `AdGate` actually opens `shouldShowBanner` (not just
"looks open on paper"), plus the `resolveAdProvider`-untouched proof above.
All pass on macOS `swift test` (85/85 full GameAppKit suite, up from 82).

## Decisions locked by dispatch / gates (not re-litigated)

- **Accessory path ships** — B-6 gate (#1029) PASSED (comment: real BannerView in accessory,
  {360,48} non-zero, survives .expanded→.inline, impression fires every launch). Fallback
  (tab-content-bottom, today's TodayTabHost slot) stays reachable + documented, not shipped.
  **Update (#1080, 2026-09-15):** removed. Once #1079 confirmed the accessory path stable,
  the PM ruled the unused fallback (`themedBanner()`/`bannerSlot()` + the `banner:` params
  on `PracticeHubView`/`SettingsView`) obsolete — deleted, not kept reachable.
- **macOS: NO banner at all** (§2.4.1 option A, FINAL). Structural exclusion
  (`#if os(macOS)` / platform-conditional composition), never runtime check.
  Acceptance: zero `tabViewBottomAccessory` hits in macOS path.
- §2.4.1 options B (detail footer) / C (sidebar) forbidden, even as dead code.
- Mirror principle: one shared parameterized implementation; verify BOTH apps.
- Test AdMob IDs only in code/tests/diff; prod via secrets/.env + xcconfig `$()`.
- #1022 rebuilds board bottom controls concurrently — avoid board files; rebase on main pre-PR.

## Corrections applied

- 2026-09-07: issue #1024 body had 5× "V-3 (#1028)" where the B-6 gate is V-4 (#1029);
  verified #1028 = B-5 a11y matrix, fixed body + audit comment. (Dispatch-authorized.)

## Scope adjudications (2026-09-08, Leader; PM informed)

- **Board banners untouched** (BoardView / MinesweeperBoardView): board is `fullScreenCover`
  OUTSIDE the TabView (GameRoot.swift:149-176) so the accessory categorically cannot host it;
  also #1022 owns board bottom chrome. Out of #1024 scope.
- **In-shell inline banners retire**: Today (TodayTabHost slot), Practice + Settings
  (`banner:` closures) stop being passed — the accessory covers the whole tab shell.
  The shells' generic `banner:` parameters STAY (documented §2.4 fallback mechanism).
- **ATT primer anchor (C-33)** moves with the banner: `onAdContext` fires from the
  accessory's slot, not TodayTabHost.
- **GameShellKit stays zero-dep**: RootShellView gains a generic bottom-accessory
  ViewBuilder param; monetization types never enter GameShellKit. Modifier application
  wrapped `#if os(iOS)`; accessory content constructed only in GameAppKit `#if os(iOS)`.
- **Static-modifier rule honored** (RootShellView.swift:29-59): the accessory closure must
  not read state that changes while a board is pushed.

## In-flight decisions

- (2026-09-07) Explorer mapping banner wiring; implementation dispatched to sonnet developer
  after map returns. Subagent write probe: PASS.
- B-6 bonus finding: 320×50 creative leaves black side slivers in the .expanded capsule.
  DECIDED + implemented: `LiveAdMobBridge.loadBanner()` sets the native `BannerView
  .backgroundColor = .clear` so `BannerAccessoryView`'s themed SwiftUI background
  letterboxes the gap instead of the SDK's own opaque fill. One-line, low-risk; full visual
  confirmation is the Leader's idb screenshot pass (sim access is PM's per the ruling below).

## Final status (2026-09-08) — all phases complete, pushed

- Phase 1 (b527c3d9): RootShellView generic `bottomAccessory` param, `#if os(iOS)` attach.
- Phase 2 (637b18eb): `BannerAccessoryView` + composition wiring, `TodayTabHost` simplified.
- Phase 3 (debad990 + 6dfaed11): both apps' Practice/Settings inline `banner:` closures
  retired; orphaned `adProvider`/`adGate` params cleaned from both `makeTabRoot`s; every
  broken test call site (TodayTabHost's simplified init, `makeTabRoot` signature) fixed;
  retired banner-visible snapshot fixtures deleted (surface moved to BannerAccessoryViewTests).
- Order-pinning test (c7028953): `BannerAccessoryViewTests.primerFiresBeforeAnyAdLoad` —
  real render + shared event log, proves primer-before-load empirically on iOS Simulator
  (confirmed the macOS headless `.task`-actor-hop limitation does NOT apply there).
- Docs (fb102021): design.md §2.4/§2.4.1 AS-BUILT notes + §3.6.1 re-anchor note;
  screen-contracts.md HOME-note + ATT-PRIMER section re-anchored with an explicit
  before/after reachability table.
- B-6 cosmetic fix: `LiveAdMobBridge` banner background made `.clear` (pending commit).

## Leader verification round (2026-09-08 PM)

- CR dual-model: haiku APPROVE; sonnet APPROVE-WITH-NITS. 2 stale comments fixed
  inline (4fe8be2c). MEDIUM gap (no accessory-through-shell render test) escalated
  to PM (in-PR sentinel test vs fast-follow).
- Sim evidence (iPhone 17 Pro, iOS 26.5, both apps): **empty accessory renders a
  visible blank capsule** above the tab bar (su-01/su-02/ms-02 screenshots) — the
  Remove-Ads-purchaser steady state. Escalated to PM with options (zero-height
  experiment / `isEnabled:` needs iOS 26.1 > our 26.0 floor / accept).
- **Loaded-banner evidence structurally blocked on sims**: AdGate fail-closed on
  store error + CloudKit-Private live store + no iCloud on sims → gate never opens
  in-app (pre-existing environmental, not a #1024 regression). #931 seam swaps
  provider to Noop so it can't produce a real ad. Escalated with recommendation:
  DEBUG-only `-uitest-open-ad-gate` (store-only fake, live provider).

## PM rulings (2026-09-08, sly-bunting — binding)

- Done-when checklist received (6 items: PR merged by PM w/ closes #1024 · T6 ACCEPT ·
  issue closed · claim posted ✅ · docs in-PR (design.md §2.4/§2.4.1 as-built +
  screen-contracts C-33/banner re-anchor) · branch/worktree cleanup post-merge).
- Adjudications 1–3 APPROVED (board untouched / ATT anchor moves w/ conditions /
  no banner over sheets — all to be stated in PR body).
- ATT conditions: order-pinning test (primer BEFORE any ad-context/ad-load); document
  before/after trigger set; escalate if primer timing couples to accessory mount.
- Open question A DECIDED: `.tabViewBottomAccessory` applied STATICALLY, suppression
  inside content (gate denies → empty/zero-height). Conditional modifier forbidden
  (#1020 unmount scar class). Empty-capsule-chrome question answered by sim evidence,
  escalated to PM if visible — that trade is PM's.
- Commit+PUSH every phase boundary; sim access serialized to Leader.

## Open questions for PM/user

- PM done-when checklist requested (check-in sent 2026-09-07); proceeding with local impl,
  PR opens after PM ack + rebase.

## #1080 follow-through (2026-09-15, plucky-wren)

- **Merge resolution summary (#1080, rebasing #1024 onto the #1062 session
  model)**: `BannerAccessoryView` was rewritten onto `\.bannerSession` — a
  plain `BannerSlotView(isSuppressed: false, …)` like every other slot, no
  `provider` / `gate` / `primer` parameters flowing through it any more; the
  ATT anchor (C-33) lives on the session's `onAdContext` hook, wired in
  `makeBannerSession`. `BannerAccessoryViewTests` was deleted rather than
  ported: it called an init that no longer exists, and the ATT-primer
  coverage it existed for is already pinned by `makeBannerSession`'s own
  tests plus `TodayTabHostTests` (restored from main, unchanged). `#1024`'s
  removal of the inline Today/Practice/Settings banner slots won every
  conflicting hunk; no board file was touched.
- **Pin test restored (#1080, PM requirement — an E2E-only pin does not
  count)**: `GameAppKitTests/BannerAccessoryPinTests.swift` replaces the
  deleted `BannerAccessoryViewTests` as the accessory's own render-level pin.
  Round 2 (review gap): the (a)/(b) tests host the REAL `GameRoot`, not a
  bare `RootShellView` with `isVisible` frozen at construction — a bare host
  never re-reads anything, so a regression hard-coding
  `bottomAccessoryIsEnabled` to either constant passed every round-1 test.
  Hosting `GameRoot` with an UN-started `BannerSessionModel` (its own
  `.onAppear` calls `start()`, exactly like `MakeGameApp.swift`) closes that
  gap. Six mutations, each named where it bites; all but (a2) executed red
  and reverted: (a1) `BannerAccessoryView.body` → `EmptyView()` — (a) red
  (no registration, no `.loaded`); (a2) drop the `\.bannerSession`
  injection from the test's own hosting helper — named-only, since it
  mutates the test file, not production; (b) `RootShellView`'s
  `.tabViewBottomAccessory(isEnabled:)` hard-coded `true` — (b) red and the
  dismiss half of (a) red; (c) macOS — `makeBottomAccessory()` returns
  `EmptyView` structurally, `BannerAccessoryView` doesn't compile into the
  macOS binary; (d1) `GameRoot.shellContent`'s `bottomAccessoryIsEnabled:`
  hard-coded `true` — (b) red and the dismiss half of (a) red; (d2) same
  site hard-coded `false` — (a) red (capsule never appears).
- **`isEnabled` design (#1079, this session)**: `RootShellView` gained a
  plain `Bool` parameter, `bottomAccessoryIsEnabled`, feeding
  `tabViewBottomAccessory(isEnabled:content:)`. GameShellKit still has no
  idea what the Bool means — GameAppKit's `GameRoot` is the one that reads
  `bannerSession.isVisible` and passes it through, keeping GameShellKit
  zero-dependency. The modifier itself stays attached unconditionally, every
  render, inside `#if os(iOS)` — `isEnabled` is an SDK display switch, not a
  conditional attach, so the #1020 unmount-hazard rule this file's design.md
  section already documents still holds.
- **Floor**: iOS deployment target raised 26.0 → 26.1 across `Project.swift`'s
  four app targets and every `Packages/*/Package.swift` (macOS unchanged at
  26.0) — `tabViewBottomAccessory(isEnabled:content:)` requires iOS 26.1.
  Neither app has shipped, so no existing user is affected by the raise.
- **Open question**: when `isEnabled` flips (banner session's `isVisible`
  changes), `GameRoot.body` re-evaluates. Whether a pushed Settings stack or a
  presented board `fullScreenCover` survives that re-evaluation the way #1020
  requires (rule 2 in `RootShellView`'s file header) has not been verified on
  a simulator — the automated tests here only prove the render-level wiring
  (capsule appears/disappears with `isEnabled`), not this interaction with an
  in-flight navigation state. Needs sim verification before treating this as
  fully closed.

## #1080 fix: host-owned accessory lease (2026-09-15, plucky-wren round 3)

- **Probe summary**: a DEBUG `os_log`-instrumented prototype (`remount-probe`,
  not shipped — every `PROBE1080`/`identityLog`/`ProbeEC` line was stripped
  before this change) found `tabViewBottomAccessory` re-hosts its content
  natively — a new hosting view, `GameRoot.body` never re-runs — on push,
  pop, sheet dismissal, and cold-launch transitions. A `BannerSlotView`'s
  `@StateObject` lease inside that content was re-created 8 times across one
  launch-to-idle script (2 on `main`'s never-re-hosted inline slots), each
  re-creation disposing the loaded ad handle and sending a fresh request. The
  host-owned-lease prototype cut that to 1 request per launch on both
  devices. Full measurement recorded in
  `meetings/2026-09-11_1058-slot-model-design.md` §"Externally owned lease
  (#1080)".
- **E-a trigger mechanism**: `BannerAccessoryPinTests`'s T2
  (`accessorySurvivesPushPopReHost`) reproduces the re-host inside the same
  bare-`UIWindow`/`UIHostingController` harness (a) and (b) already use — no
  real app scene needed — by pushing then popping a route on the Today tab's
  own `NavigationStack` (`viewModel.pathBinding(for: .today)`). Confirmed
  empirically: under the pre-fix mutation (accessory reverted to a
  self-owned lease) the test goes red (refresh count 1→2, slot id changes);
  with the fix it stays green. This closes the PM condition that a hosted-
  window harness must be proven to actually re-host before it can serve as
  the pin, rather than assumed.
- **E-c numbers (ad-request count, same scripted push/pop/sheet script, both
  devices)**: accessory before the fix sent 8 ad requests per device; `main`
  sent 2; the host-owned-lease fix sent 1 on both iPhone and iPad.
- **PM ruling on the residual repaint gap**: after each re-host the
  reparented banner's creative stays visually unpainted for 0.6–1.9s past the
  transition animation — video-measured empty-creative durations: iPad ATT
  1926ms (single recording — an earlier 1855ms figure for the same video was
  a superseded ad-hoc estimate, not a second sample), push 1580ms, reminder
  decline 644ms, pop 1428ms; iPhone ATT 1236ms, push 934ms, reminder decline
  824ms, pop 1341ms. Control (C1): the
  main branch's never-re-hosted inline slot stayed painted in 144/144 frames,
  ruling out a recording artifact. A `setNeedsLayout`/`layoutIfNeeded` nudge
  in `updateUIView` was tried and dropped — its trigger (a window-change
  observation) never fired, since no window change is visible at that call
  site. PM accepted this gap as out of #1080's scope; it is NOT fixed by this
  change. Follow-up: #1094.
- **New pins and mutations (this round)**:
  - T1 (`AppMonetizationKit/Tests/MonetizationUITests/BannerSlotExternalLeaseTests.swift`,
    macOS): the same external lease survives its view being re-hosted under
    a new SwiftUI identity — one registration, one refresh, same slot id and
    loaded handle. Mutation (`BannerSlotRegistration.update()` attaches
    `ownLease` instead of `effective`) executed red, reverted green.
  - T2 (`GameAppKitTests/BannerAccessoryReHostTests.swift`, iOS Simulator, a
    sibling suite rather than folded into the round-2 file — that pushed it
    to 438 lines, over the `file_length` ceiling; duplicates its own stubs
    per the codebase's established file-private-copy convention): see E-a
    above. Mutation (`BannerAccessoryView` reverted to the self-owned-lease
    init) executed red on-device, reverted green.
  - T4 (`GameAppKitTests/BannerAccessoryMissingLeaseTests.swift`, iOS
    Simulator): a missing `\.bannerAccessoryLease` injection calls
    `BannerAccessoryView.onMissingAccessoryLease()` — mirrors
    `BannerSessionModel.onMissingSession` (#1058 M1), no silent fallback.
    Mutation (drop the call from the `nil` branch) executed red, reverted
    green. The API contract's "renders nothing" half is documented, not
    independently asserted — `UIHostingController.sizeThatFits(in:)`
    reported a nonzero height for this exact tree even with `EmptyView()` as
    the only content on an unwindowed, unparented hosting controller, the
    same false-negative class this file's own (a)/(b) header already flags
    for accessibility-identifier lookup in a headless host.
  - Round-2 vs T2 dedupe (PM condition 3): round-2's (a)/(b)/(c)/(d1)/(d2)
    pin `isEnabled`/visibility wiring (does the capsule show/hide with the
    gate); T2 pins lease-identity stability across a native re-host (does
    registration churn). Disjoint behaviors — both kept, nothing redundant.
  - Teardown (T3): no pin added this round (PM ruling: hygiene, not a gate)
    — a separate bounded diagnostic covers it, not investigated further
    here. The app is single-scene (no `UIApplicationSceneManifest`), so
    `GameRoot` and its accessory lease live for the process lifetime. In a
    hosted-window diagnostic
    (`build/evidence-1080/remount-probe/test-ec-teardown-v2.log`), releasing
    the hosting controller leaves the `GameRoot`-owned lease alive:
    `session.slots` still holds that same lease id after 5s and nothing is
    disposed. The retain path is not identified. An earlier v1 run that
    reported the lease deallocated was invalid (its capture hook never
    fired). Per-re-host accumulation checked from the E-c logs
    (`ec-head-{iphone,ipad}.log`): self-owned never-attached leases
    inits/deinits = iPhone 23/22, iPad 16/15. The one alive on each device is
    the live host's own lease, so old hosted content is released on every
    re-host. The harness-teardown retention does not accumulate in normal
    use. Board/Practice/Settings slots keep self-owned leases and deinit
    normally.
