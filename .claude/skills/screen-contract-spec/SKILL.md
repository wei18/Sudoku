---
name: screen-contract-spec
description: Spec-first methodology for planning an app's navigation as SCREEN CONTRACTS — per-screen element inventory + per-interaction outcome (destination + presentation semantics + back/close landing) + covering/z-order behavior + loading/empty/failed/degraded state variants + forward AND negative flow chains, each row anchored to code. Use when planning a new app/feature's screens, auditing an existing app's navigation for traps/drift, deriving E2E test cases from flows, or turning a screen contract into a SwiftUI navigation skeleton. NOT a visual mockup tool (that is `apple-dev-skills:ios-design-mockup`).
---

# Screen Contract Spec

Navigation is the skeleton of a product. Most "how do I go back / does this
cover that / why am I stranded here" bugs are decided the moment you pick a
**presentation semantic** — and specs that draw bare `A → B` arrows never force
that choice. This skill makes you commit to it, per screen, per interaction,
with a code anchor, so the spec is an as-built contract instead of a wish.

Worked example in this repo: `docs/screen-contracts.md` (21 contracts) +
`docs/navigation-flows.md` (flow chains + 18-row negative-flow table). Read
those first — they are the reference shape.

## When to invoke

- Planning a **new app or feature's** screens before writing view code.
- **Auditing** an existing app's navigation for traps, dead ends, and doc↔code
  drift (this skill's checklist IS the audit checklist).
- Deriving an **E2E test-case catalog** from flows (each negative edge = one case).
- Turning a contract into a **SwiftUI navigation skeleton** (route enum + router).
- Reviewing a PR that changes navigation, presentation, or a completion/back flow.

## The core discipline: pick the presentation semantic

Every transition MUST carry one tag. The tag decides back/dismiss behavior,
state teardown, and covering — get it wrong and the return logic distorts (see
the repo's own 2B bug: a macOS completion pushed instead of overlaid, so Close
popped one route and stranded the player on the solved board).

| Tag | SwiftUI | Back/close behavior | Covers | Key constraint |
|---|---|---|---|---|
| **push** | `NavigationStack(path:)` + `navigationDestination` | back-swipe pops (ON by default) | full | `NavigationPath` is OPAQUE — can't introspect; router must shadow with its own `[Route]` if it needs "is X pushed?" |
| **sheet-detent** | `.sheet` + `.presentationDetents` | swipe-to-dismiss ON by default; `interactiveDismissDisabled(true)` to force | partial (detent); presenter can stay live via `presentationBackgroundInteraction(.upThrough:)` | >1 detent auto-shows grabber; detents IGNORED on macOS |
| **fullscreen-modal** | `.fullScreenCover` | swipe-dismiss **OFF** (hand-roll `DragGesture`); exit via `dismiss()` | full, opaque | **NO macOS API** — must fall back to push (see repo's `GameBoardRedirect` two-context contract) |
| **popover** | `.popover` | tap-outside dismisses | anchored bubble | **collapses to a sheet on compact width** unless `.presentationCompactAdaptation(.popover)` inside the content |
| **alert** | `.alert` | button tap ONLY (no scrim-tap, no swipe) | center float | data-drive with `presenting:` off an optional, not stacked `Bool`s; alert+sheet on same view can misfire (move to different hierarchy nodes) |
| **dialog** | `.confirmationDialog` | Cancel **or tap-outside** dismisses | bottom sheet of buttons | **contract says "dismiss on scrim tap" ⇒ this, NOT alert**, regardless of visual intent |
| **overlay** | `.overlay` / `ZStack` | none of its own (host controls) | z-stacked layer | pure layout; no interactive-dismiss/detent machinery — the match for "just visual stacking" |
| **inspector** | `.inspector` | resizable column / swipe | trailing column | **collapses to a sheet on compact width** (like popover) |
| **tab-switch** | `TabView` | selection change | sibling swap | not a stack push — no back |
| **root-swap** | conditional root content on an `@Observable` state | **no back concept** — replaces | full | destroys the outgoing tree (nav stack + presented sheets torn down); logout/login lives here |
| **external** | `openURL` / `GameCenterDashboard.present()` | system-owned | system UI | deep-link cold-start via `onOpenURL`; NO built-in mid-stack restoration |
| **side-effect** | (no navigation) | n/a | n/a | e.g. leaderboard card when signed-out → shows an alert, doesn't navigate |

### root-swap vs modal-present (the login trap)

Login → success is **root-swap, NOT modal-present**. Put an `@Observable`
auth-state at the root and conditionally render `LoginView` vs `AppView`.
Success flips the flag → root rebuilds `AppView`, LoginView is **destroyed**.
Logout flips it back → clean teardown of the whole app nav stack. If you instead
present the app modally over login, logout means "dismiss a modal" — an
anti-pattern that keeps login alive underneath and couples app lifetime to a
presentation. "How do I go back" is always answered by "what presented it";
pick the wrong semantic and the return path is forced to be a hack.

Login → error is a separate choice the contract must force: **toast** (transient,
non-blocking, orthogonal region, login stays put, auto-dismiss) vs **alert**
(blocking, must tap OK, dismiss → same LoginScreen with password cleared). "A
toast with a confirm button" is a contradiction — that's an alert.

## The Screen Contract template

One per screen/surface. Keep it terse — tables, not prose.

```
## <SCREEN-ID>   e.g. SUD-BOARD, MS-DAILY-HUB, HOME, PAUSE, COMPLETION-OVERLAY
Entry points: <which flows land here>
Element inventory:
  | element | copy / LocalizedStringKey | a11y id |
Interactions:
  | element | action | destination | presentation | back/close lands on | state preserved/refreshed |
Covering: <what this covers / is covered by; is the layer below still interactive?>
State variants: loading | empty | failed | degraded(CK signed-out/offline) — what each renders
Anchors: <file:line or symbol per row>
```

Notation conventions (define your own light set; there is no ISO standard):
- Model overlays/toasts/banners as **parallel (orthogonal) regions**, not
  separate flow nodes — that is how you express "X covers Y" and z-order.
- Model a **negative transition as an explicit labeled edge** (event fires but
  should NOT transition, or routes to an error state) — each one becomes a test.
- Tag every screen + transition with a stable **ID** (`SCR-03`, `NAV-07`); require
  the view/test code to reference the ID in a comment or test name → grep-able
  bidirectional traceability. Orphan ID = drift; code with no ID = undocumented.
- Update with **dated ADR-style deltas**, never silent rewrites of frozen content
  (see how `docs/designs/*` carry `AS-BUILT NOTE (date)` banners).

## Flow chains + negative flows

- **Forward chains** reference screen IDs: `HOME → DAILY → BOARD(modal) →
  COMPLETION(overlay) → close → DAILY`. Keep readable; detail lives in contracts.
- **Negative-flow table** — one row per exit/cancel/error/degraded path:
  board-load failure → Retry-in-place; hub `.empty` → alert; hub `.failed` →
  failure block; CK signed-out → resume pill absent + completion overlays skipped
  + GC surfaces degrade; pause mask-tap = resume; Close in EACH presentation
  context (modal `dismiss()` vs push pop vs `removeAll()`); deep-link cold-start;
  UMP/ATT interruptions. Every negative row is a candidate E2E case.

## SwiftUI skeleton recipe (contract → runnable nav)

No public generator exists; the community-convergent shape (SUICoordinator /
FlowStacks as study templates) is mechanically emittable from a contract:

1. One `enum Route: Hashable` per module (associated values = payload).
2. One `@Observable` router: `path: [Route]` (prefer over raw `NavigationPath`
   for introspection) + one optional per modal kind (sheet/cover/alert) + `navigate`/`present`/`dismiss`.
3. Root: `NavigationStack(path:$router.path){ Root().navigationDestination(for: Route.self){ router.view(for:$0) } }` — the `view(for:)` switch is the only enum→View map.

Skeleton footguns (bake into any generated code):
- `@Environment(\.dismiss)` only works read INSIDE the presented content — no-op in the presenter.
- UIKit "present while presenting" crashes — chain the next present in the prior dismiss's completion.
- Dismiss-cascade is unreliable (still open on iOS 26) — model explicit `.dismiss` vs `.dismissAll`.
- Child-router `onComplete` closures leak — mark `weak`/`unowned`.

## Repo battle-scars (first-party constraints, not in any web source)

These are why the constraint table earns its place — each is a shipped bug:
- **#2B / #669** macOS has no `fullScreenCover` → board pushes instead of covers →
  Close must pop-to-hub not pop-one (`GameBoardRedirect` two-context `boardDestination`).
- **#197** `NavigationSplitView` cross-pane value-link fires inconsistently → sidebar `onTap` uses direct `path.append`.
- **#523** `item:` vs `isPresented:` present race → blank cover; use `item:`.
- **#611** double-present when both an overlay predicate and a push fired → gate on ONE.
- **#518** chrome row bled over the completion overlay → hide chrome at terminal.
- **#674** a control gated on `.playing` disappears in `.ready`/idle → can strand
  the user (MS board pre-first-tap trap, #681). Always give `.ready`/idle an exit.

## Using this skill as an AUDIT

Contract-drive the audit: for each shipped screen, fill the contract from CODE,
then check each row against the running app (sim). Mismatches are findings:
- element present in code but not reachable (dead affordance) / vice versa;
- a transition whose real presentation ≠ the tag (push where a modal was intended);
- a back/close that lands somewhere other than the contract says (2B class);
- a state variant with no rendering (loading/empty/failed/degraded gap);
- a `.ready`/terminal state with no exit (trap class);
- an overlay that doesn't hide the layer below from the a11y tree (VoiceOver leak —
  screenshot-clean but `describe-all` shows interleaved stale elements).
Cross-check both apps (mirror principle): a contract row that differs between
Sudoku and Minesweeper without a documented reason is drift.

## See also

- `docs/navigation-flows.md` + `docs/screen-contracts.md` — the worked example.
- `interactive-sim-ux-audit` — how to drive the sim to verify contract rows.
- `apple-dev-skills:ios-design-mockup` — the VISUAL-mockup skill (this one is the
  behavioral contract; they compose: contract → mockup → implementation → E2E).
- `apple-dev-skills:swiftui-interaction-footguns` · `apple-dev-skills:ios-accessibility-engineering`.
- Memory: `reference/screen-contract-spec-research.md` (full research provenance).
