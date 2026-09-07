# impl-notes — #1024 banner → tabViewBottomAccessory (session/brisk-stork-isio)

Running log during implementation. Post-hoc meeting log is separate.

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
- B-6 bonus finding to handle in feature: 320×50 creative leaves black side slivers in the
  .expanded capsule → letterbox/background-fill or adaptive banner sizing. Decision TBD
  after reading LiveAdMobBridge's current sizing.

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
