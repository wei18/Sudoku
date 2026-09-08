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
