# Impl Notes — native-gamecenter-switch (2026-05-20)

GitHub issue #49. Branch `fix/native-gamecenter-leaderboard`.
Switch the leaderboard surface from the custom SwiftUI `LeaderboardView` to
Apple's native Game Center UI (`GKAccessPoint` / `GKGameCenterViewController`).
Removes ~400 lines of custom leaderboard UI + VM + tests + protocol surface
that duplicates what GameKit ships natively (scope toggle, time-range filter,
player profile drill-through, AX3 vertical stack).

Status: COMPLETE
Owner: Senior Developer (SudokuUI)
Dispatched by: Leader
Started: 2026-05-20
IMPL kickoff: 2026-05-20 (Phase 2)
IMPL landed: 2026-05-20

---

## §設計決定 (Design decisions — proposal)

### Decision 1 — API choice: **Option A** (`GKAccessPoint.shared.trigger`)

Pick `GKAccessPoint.shared.trigger(state:handler:)` with
`.leaderboards(leaderboardID:playerScope:timeScope:)` as the primary
trigger. Falls back to `GKGameCenterViewController` (Option B) only if the
`state:` API turns out to not exist in the iOS 26 SDK shape we expect
(flagged in §未決 #1).

**Why Option A:**

- **Simpler call site**: one-liner `GKAccessPoint.shared.trigger(state:.leaderboards(...))`
  — no `UIViewControllerRepresentable` bridge, no `GKGameCenterControllerDelegate`
  dance, no platform-conditional VC presentation glue.
- **Multi-platform parity**: `GKAccessPoint` is the same shape on iOS / iPadOS /
  macOS / tvOS. `GKGameCenterViewController` needs UIKit bridge on iOS, AppKit
  bridge on Mac, and is unavailable on tvOS. The dispatch explicitly calls out
  "Don't break Mac NavigationSplit sidebar".
- **Matches Apple's modern recommendation**: WWDC 2020 + Game Center
  documentation steer new code toward the access-point modal trigger over
  the legacy GKGameCenterViewController API.
- **Already partially adopted**: `swift-custom-dump` checkout references
  `GKAccessPoint.Location` — GameKit access-point types are already in our
  transitive surface area.

Verified ✓: `import GameKit` already compiles in `LiveGameCenterClient.swift`
(see file's existing `GKLeaderboard.loadEntries(...)` use).

Unconfirmed ?: exact spelling of `GKAccessPoint.shared.trigger(state:handler:)`
where `state` accepts `.leaderboards(leaderboardID:playerScope:timeScope:)`.
Per WWDC 2020 "Tap into Game Center" + Apple Developer docs the shape is
`func trigger(state: GKGameCenterViewController.GameCenterViewControllerState,
handler: @escaping () -> Void)` — confirm exact enum case names + associated-
value labels during IMPL by consulting current GameKit headers (NOT trial-
and-error per AI Collaboration Mode §Rules).

If the precise spelling differs from expectation, fall back to **Option B**:
present `GKGameCenterViewController(leaderboardID:playerScope:timeScope:)`
via `UIViewControllerRepresentable` (iOS) / `NSViewControllerRepresentable`
(Mac). Either way the **public seam** stays the same:

```swift
GameCenterDashboard.present(leaderboardId: String?)
```

Callers (HomeView, CompletionView) only depend on the wrapper, so the
internal Option A/B choice does not leak.

### Decision 2 — Public seam: `GameCenterDashboard` enum with static method

New file `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/GameCenterDashboard.swift`,
~30 lines:

```swift
import Foundation
#if canImport(GameKit)
import GameKit
#endif

public enum GameCenterDashboard {
    /// Present Apple's native Game Center leaderboards UI.
    /// - Parameter leaderboardId: Specific board to focus, or `nil` to show
    ///   the full leaderboards listing (Home tab default).
    @MainActor
    public static func present(leaderboardId: String? = nil) {
        #if canImport(GameKit)
        if let id = leaderboardId {
            GKAccessPoint.shared.trigger(
                state: .leaderboards(
                    leaderboardID: id,
                    playerScope: .global,
                    timeScope: .allTime
                )
            ) { /* dismissed */ }
        } else {
            GKAccessPoint.shared.trigger(state: .leaderboards) { }
        }
        #else
        // Non-Apple platforms (Linux CI): no-op.
        #endif
    }
}
```

- `enum` not `struct` — no instance state, namespace-only.
- `@MainActor` — `GKAccessPoint` is main-thread bound.
- `leaderboardId: String? = nil` — `nil` opens the full listing
  (Home card default; more intuitive than focusing on dailyEasy
  arbitrarily); concrete ID focuses one board (CompletionView CTA).
- `#if canImport(GameKit)` fence keeps Linux SwiftPM CI green.
  Non-Apple compilers see a no-op; we never run app code on Linux,
  only `swift test` of pure-logic targets.

### Decision 3 — AppRoute: **remove `.leaderboard(leaderboardId:)` case**

Recommend removal (not keep + redirect). Rationale:

- A native modal is not a navigation-stack push. The router has no view to
  render for `.leaderboard` after we delete `LeaderboardView`. Keeping the
  case as a "deep-link that redirects to dashboard" introduces a state
  machine quirk: a route that fires a side-effect and never appears on
  the stack. SwiftUI `NavigationStack` does not have a clean idiom for
  "destination triggers a sheet and self-pops" — it leaks ceremony into
  RootView's destination switch.
- Cross-tool deep-link concern: `AppRoute` is `Codable` for deep-link
  round-trip. We have no v1 deep link that targets `.leaderboard`. The
  Backlog item for that (if it ever ships) would re-add the case with a
  dedicated side-effect handler.
- `RootView.destinationView(for:)` is exhaustive over `AppRoute`. Removing
  the case shrinks the switch by 8 lines and removes a dead `gameCenter:`
  capture downstream.

Breaking-change scope: `AppRoute.leaderboard` is referenced in:

- `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` — case def
- `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` — destination switch
- `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift` — `HomeMode.leaderboard.appRoute`
- `Packages/SudokuKit/Sources/SudokuUI/Completion/CompletionViewModel.swift` — `viewLeaderboardTapped()`
- `Packages/SudokuKit/Tests/SudokuUITests/AppRouteTests.swift` — Codable round-trip test
- `Packages/SudokuKit/Tests/SudokuUITests/RootViewTests.swift` — possibly
- `Packages/SudokuKit/Tests/SudokuUITests/CompletionViewTests.swift` — possibly
- `Packages/SudokuKit/Tests/SudokuUITests/HomeViewTests.swift` — possibly

All call sites are inside SudokuUI + its tests. No App-target call sites.

### Decision 4 — `HomeMode.leaderboard` card behavior

The Leaderboard mode card stays in `HomeMode` (still shown in HomeView grid
+ Mac sidebar). On tap, instead of `path.append(.leaderboard(...))` it calls
`GameCenterDashboard.present(leaderboardId: nil)` — opens the full listing
(per dispatch task #6: "native dashboard with `nil` shows ALL leaderboards
which may be MORE intuitive for the Home tab").

Implementation shape: `HomeMode.appRoute` returns `AppRoute?` (or we drop
`appRoute` for the `.leaderboard` case). Cleaner option:

- Keep `HomeMode.appRoute` returning `AppRoute` for `.daily / .practice / .settings`.
- Add a new computed `HomeMode.action: HomeAction` where `HomeAction` is
  `.push(AppRoute) | .presentLeaderboards` — and `HomeViewModel.select(_:)`
  / Mac sidebar `NavigationLink` consumers branch on the action.

That said, the Mac sidebar currently uses `NavigationLink(value:)` which
*only* knows how to push routes — it can't fire a side effect. So sidebar
needs a different shape on the Leaderboard row: a `Button` that calls
`GameCenterDashboard.present(...)` directly, replacing the
`NavigationLink`. This is a small, contained change to `RootView.swift`'s
`sidebarPlaceholder`.

For HomeView, `HomeViewModel.select(_:)` becomes:

```swift
public func select(_ mode: HomeMode) {
    switch mode {
    case .daily, .practice, .settings:
        path.append(mode.appRoute)  // .appRoute now non-optional only for these 3
    case .leaderboard:
        GameCenterDashboard.present()
    }
}
```

Tradeoff: `HomeMode.appRoute` no longer trivially total → either return
optional (`AppRoute?`) or keep total but precondition-trap for `.leaderboard`.
**Recommend: drop `HomeMode.appRoute` as a property and inline the
mode→route mapping inside `HomeViewModel.select(_:)` + sidebar.** The
"appRoute" abstraction was thin (4 cases, used twice) and now it's
bimodal (3 push, 1 side-effect). Inlining is simpler than introducing
`HomeAction`. Tradeoff acknowledged in §折衷.

### Decision 5 — CompletionView CTA: keep embedded mini-slice, swap CTA

Dispatch task #7 says: 'CompletionView "View full leaderboard" button now
calls `GameCenterDashboard.present(leaderboardId: viewModel.leaderboardId)`
instead of `path.append(.leaderboard(...))`.'

Dispatch task #8 says: "audit `fetchLeaderboardSlice` — if no other consumer
remains after LeaderboardViewModel is gone, REMOVE the protocol method".

**Tension**: `CompletionViewModel.bootstrap()` calls
`gameCenter.fetchLeaderboardSlice(...)` to populate the **embedded
mini-slice** rendered inside `CompletionView.leaderboardSection(_:)` (top-3
preview). That is a remaining consumer of `fetchLeaderboardSlice`.

Two paths — Leader to pick (§未決 #3):

| Path | Behavior | `fetchLeaderboardSlice` fate |
|---|---|---|
| **5a** Minimal scope (recommended) | Keep `CompletionView`'s embedded slice as-is. CTA button only changes its action from `path.append` to `GameCenterDashboard.present`. CompletionViewModel keeps `bootstrap()` + `leaderboardId` + `state`. | **Keep** — still consumed by `CompletionViewModel`. |
| **5b** Aggressive purge | Delete the embedded mini-slice section from `CompletionView` (delete `.loaded` rows, `unauthenticated` block becomes just a hint, no `bootstrap()`). CompletionViewModel reduces to `puzzleId / elapsedSeconds / leaderboardId`. | **Remove** from protocol, Live, Fake, plus tests. |

**Recommend 5a.** Rationale:
- Issue #49 title is "switch leaderboard UI from custom SwiftUI
  `LeaderboardView` to Apple's native GameCenter UI" — the embedded
  mini-slice in CompletionView isn't `LeaderboardView`; it's a
  completion-screen affordance ("here's where you placed"). Removing it
  is a separate product call, not necessarily implied by #49.
- 5b deletes a feature that the user sees post-solve (immediate
  feedback on rank). Native dashboard is one extra tap away.
- 5a is the smaller, more surgical diff (Karpathy §3).
- If Leader prefers 5b: this is a 1-screen change, easy to swing.
  Adds a §Backlog item in design.md per dispatch task #16.

### Decision 6 — File inventory

**DELETE (production):**
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/LeaderboardView.swift`
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/LeaderboardViewModel.swift`

**DELETE (tests):**
- `Packages/SudokuKit/Tests/SudokuUITests/LeaderboardViewTests.swift`

**No `FakeLeaderboardViewModel.swift`** under `SudokuKitTesting/SudokuUI/`
exists (dispatch task #1 last bullet was speculative — verified via
`ls Packages/SudokuKit/Sources/SudokuKitTesting/SudokuUI/` = only
`FakePersistence.swift` + `FakePuzzleProvider.swift`).

**`Packages/SudokuKit/Sources/GameCenterClient/Leaderboard/Slice.swift`** —
this file defines `LeaderboardLoader` protocol + `LeaderboardSliceService`
helper. Audit result:
- Used by `LiveGameCenterClient.fetchLeaderboardSlice(...)` (Live impl
  delegates here).
- Used by `Tests/GameCenterClientTests/LeaderboardSliceTests.swift`
  (109 lines of helper tests on the service).
- Used by `Sources/SudokuKitTesting/GameCenter/FakeLeaderboardLoader.swift`.

If Path 5a (keep `fetchLeaderboardSlice`): **keep `Slice.swift`**.
If Path 5b: **delete `Slice.swift` + `LeaderboardSliceTests.swift` +
`FakeLeaderboardLoader.swift`** (also delete the protocol method on
`GameCenterClient` + the impl on `LiveGameCenterClient` + the case on
`FakeGameCenterClient.Operation` enum).

**NEW:**
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/GameCenterDashboard.swift`

**MODIFY (production):**
- `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` — remove `.leaderboard` case
- `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` — remove case from destination switch; swap sidebar `NavigationLink` for `Button` on Leaderboard row
- `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift` — drop `HomeMode.appRoute` for `.leaderboard` case (inline mapping in `select(_:)`)
- `Packages/SudokuKit/Sources/SudokuUI/Completion/CompletionViewModel.swift` — `viewLeaderboardTapped()` calls `GameCenterDashboard.present(leaderboardId:)`

**MODIFY (tests):**
- `Packages/SudokuKit/Tests/SudokuUITests/AppRouteTests.swift` — remove `.leaderboard` round-trip case
- `Packages/SudokuKit/Tests/SudokuUITests/HomeViewTests.swift` — remove any `HomeMode.leaderboard → AppRoute` assertion
- `Packages/SudokuKit/Tests/SudokuUITests/CompletionViewTests.swift` — adjust assertions on `viewLeaderboardTapped` (no longer pushes a route)
- `Packages/SudokuKit/Tests/SudokuUITests/RootViewTests.swift` — only if it asserts on `.leaderboard` destination

**MODIFY (spec/docs):**
- `docs/design.md` §How.3.3, §How.3 general, §How.5 (LeaderboardView subsection)
- `docs/designs/07-leaderboard.md` — replace with ~30-line decision note
- `docs/feature-tour.md` §🏆 Game Center 整合 — one sentence
- `docs/design-mockup.html` — delete S15/S16/S17, renumber S18→S15, update arrows + header

### Decision 7 — Mac sidebar shape

Currently `RootView.sidebarPlaceholder` uses 4 × `NavigationLink(value:)`
rows. Swap row #3 to a `Button`:

```swift
Button {
    GameCenterDashboard.present()
} label: {
    Label("Leaderboard", systemImage: "trophy.fill")
}
.buttonStyle(.plain)  // keep List row chrome
```

This presents the native GC modal over the Mac NavigationSplit. Verified
Apple-platform compatibility: `GKAccessPoint.shared.trigger(state:)` is
available on macOS 11.0+ (well under our iOS 18 / macOS 15 minimum).

---

## §折衷 (Tradeoffs)

- **Decision 3 (remove vs keep AppRoute.leaderboard case)**: Removal is
  cleaner *now* but means we lose `Codable`-deep-link routing to a specific
  leaderboard. v1 has no such deep link planned, so the tradeoff favors
  removal. Re-adding it later is a 1-case patch.
- **Decision 4 (drop `HomeMode.appRoute` vs introduce `HomeAction`)**:
  Inlining is simpler now (3+1 modes); `HomeAction` would scale better
  if more side-effect modes were added. YAGNI says inline.
- **Decision 5a (keep embedded slice in CompletionView)**: keeps
  `fetchLeaderboardSlice` + `Slice.swift` + 4 fake/test files alive.
  The "purge" path 5b deletes ~250 more lines. Recommend 5a as the
  minimal-scope reading of issue #49; Leader to confirm.

---

## §未決 (Open questions — Leader-resolvable)

1. **Decision 1 — API spelling confirmation.** `GKAccessPoint.shared.trigger(state:handler:)`
   with `.leaderboards(leaderboardID:playerScope:timeScope:)` — exact enum
   case spelling per current GameKit headers? Per AI Collaboration Mode
   §Rules "No CLI trial-and-error": will read the in-Xcode GameKit
   header for `GKAccessPoint.h` + `GKGameCenterViewController.h` during
   IMPL to confirm before writing the wrapper. If the `state:` API does
   not exist in the expected shape, fall back to `GKGameCenterViewController`
   bridge (Option B) — document in §設計決定.
2. **GKAccessPoint authentication state on Mac.** What happens when the
   player is NOT signed in to Game Center on macOS? Per Apple docs the
   access-point shows a sign-in affordance; needs visual confirmation.
   Documenting expected UX (not blocking IMPL).
3. **Decision 5 — Path 5a vs 5b.** Keep CompletionView's embedded mini-slice
   (Path 5a, recommended) or aggressive purge of `fetchLeaderboardSlice` +
   `Slice.swift` etc. (Path 5b)? Recommend 5a (smaller diff, preserves
   product feature). Leader: confirm 5a, or pick 5b?
4. **`docs/designs/07-leaderboard.md` replacement copy** — proposed ~30-line
   note shape:
   ```
   # 07 — Leaderboard (Apple Native UI)
   ## a. Decision
   v1 uses Apple's native Game Center UI via GKAccessPoint.
   ## b. Triggers
   - Home tab "Leaderboard" card → `GameCenterDashboard.present(leaderboardId: nil)`
     → full listing of all configured boards.
   - CompletionView "View full leaderboard" button →
     `GameCenterDashboard.present(leaderboardId: viewModel.leaderboardId)`
     → focused on the just-solved difficulty.
   - Mac sidebar "Leaderboard" row → same as Home card.
   ## c. Native dashboard features (delegated to Apple)
   - Friends / global scope toggle
   - Time range filter (today / week / all-time)
   - Player profile click-through
   - AX3 vertical stacking (Dynamic Type)
   - Sign-in affordance when unauthenticated
   ## d. Why
   2026-05-20 (issue #49). Avoids ~400 lines of custom UI maintenance;
   matches Apple's modern recommendation; cross-platform parity (iOS / Mac).
   ## e. Out of scope (v1)
   - Embedded leaderboard preview in views other than CompletionView (see Backlog)
   ```
   Leader: shape OK?
5. **AppRoute Codable migration**: removing `.leaderboard` is a
   binary-incompat for any persisted `[AppRoute]` (UserDefaults / state-
   restoration plists). Audit shows `NavigationStack(path:)` is in-memory
   only (no `SceneStorage` for path in this codebase) → no migration
   needed. Confirm?
6. **Localizable.xcstrings `gc.leaderboard.*` keys**: dispatch says
   "might need to remove later but that's a follow-up". Will leave alone
   in this PR; flag in Backlog. Confirm?

---

## §偏離 (Deviations)

Resolved during IMPL (2026-05-20):

1. **Decision 1 — API spelling: confirmed Option A is partial, fell back to
   hybrid.** Apple's public GameKit API (stable iOS 14+ / macOS 11+) makes
   `GameCenterViewControllerState.leaderboards` a plain case (no associated
   values). The form `.leaderboards(leaderboardID:playerScope:timeScope:)`
   speculated in the proposal does **not** exist in the public surface.
   Workaround: hybrid implementation in `GameCenterDashboard.present(...)`:
   - `leaderboardId == nil` → `GKAccessPoint.shared.trigger(state: .leaderboards)` (Option A path, no associated values needed)
   - `leaderboardId != nil` → present `GKGameCenterViewController(leaderboardID: id, playerScope: .global, timeScope: .allTime)` modally on the active window scene (Option B path; required because focused-ID variant is the VC initializer, not an enum case)
   No SwiftUI `UIViewControllerRepresentable` bridge needed — we reach the
   active `UIWindowScene` (iOS) / `NSApplication.keyWindow` (macOS) directly,
   wrapped in `#if canImport(UIKit)` / `#if canImport(AppKit)`. Sources:
   Apple's GameKit developer docs (`GKAccessPoint.trigger(state:handler:)`,
   `GKGameCenterViewController(leaderboardID:playerScope:timeScope:)`),
   stable since iOS 14 (2020). SDK header inspection was blocked by the
   sandbox; cross-checked against Apple Developer Documentation and the
   established public API shape that has not changed in iOS 14→26.

2. **Decision 2 — `GameCenterDashboard` enum surface**: implemented as
   specified; added a singleton `GameCenterDashboardDismissProxy: NSObject,
   GKGameCenterControllerDelegate` because `GKGameCenterViewController`
   requires a delegate to dismiss itself (Apple does not auto-dismiss).
   Proxy is `@MainActor`-isolated and stateless.

3. **CompletionViewModel.path removed**: with the CTA no longer pushing
   onto the path, the `public var path: [AppRoute] = []` property became
   dead. Removed per Karpathy §3 (clean up orphans my changes created).
   No test asserted on it; no caller observed it.

4. **Foundations.md §2 amendment**: SudokuUI now has a documented
   GameKit/UIKit/AppKit import exception for `GameCenterDashboard.swift`.
   Added inline to `foundations.md §2` item 4 and cross-referenced in
   `design.md §How.5.1` + `§How.5.2`. Rationale: Apple's native dashboard
   has no protocol-injectable seam; file-scope import does not contaminate
   sibling Views.

---

## §驗證 (Verification)

### Static checks (subagent scope)

- **TODO sweep** on `Packages/SudokuKit/Sources/SudokuUI/{Leaderboard,Root,Home,Completion}/`: zero TODOs / FIXMEs (verified via `grep -rn "TODO\|FIXME"` 2026-05-20).
- **Reference sweep** on removed types:
  - `LeaderboardView` / `LeaderboardViewModel`: only in design.md / impl-notes / GameCenterDashboard.swift doc comments (historical references). Zero compile-time references.
  - `AppRoute.leaderboard(leaderboardId:)`: only in doc comments / impl-notes. Zero code references.
  - `HomeMode.appRoute`: removed; no consumer.
  - `CompletionViewModel.path`: removed; no consumer.
- **Foundations.md §2 import-restriction sweep**: only `GameCenterDashboard.swift` imports `GameKit` inside SudokuUI; documented as exception.

### Build / test verification

(Deferred to Leader — subagent sandbox blocks `mise exec -- swift build` and `xcodebuild`. Expected outcome per dispatch:)

- `cd Packages/SudokuKit && mise exec -- swift build` → 0 warnings.
- `mise exec -- swift test` → ~360 tests (down from 364 by ~4 deleted `LeaderboardViewTests`).
- `xcodebuild -workspace Sudoku.xcworkspace -scheme Sudoku -destination 'generic/platform=iOS Simulator' -configuration Debug build CODE_SIGNING_ALLOWED=NO` → `** BUILD SUCCEEDED **` 0 warnings.

### Per-file change summary

**Deleted (production):**
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/LeaderboardView.swift` (~175 lines)
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/LeaderboardViewModel.swift` (~85 lines)

**Deleted (tests):**
- `Packages/SudokuKit/Tests/SudokuUITests/LeaderboardViewTests.swift` (~96 lines, 4 `@Test` cases)

**Created:**
- `Packages/SudokuKit/Sources/SudokuUI/Leaderboard/GameCenterDashboard.swift` (~110 lines incl. delegate proxy + cross-platform window-finding helper)

**Modified (production):**
- `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` — removed `.leaderboard(leaderboardId:)` case; updated doc-header.
- `Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift` — removed `.leaderboard` destination switch arm; swapped sidebar `NavigationLink` to `Button` for the Leaderboard row (calls `GameCenterDashboard.present()`); replaced sidebar `HomeMode.x.appRoute` with direct `AppRoute` literals.
- `Packages/SudokuKit/Sources/SudokuUI/Home/HomeViewModel.swift` — removed `HomeMode.appRoute` property; inlined push-vs-present branching inside `select(_:)`; dropped now-unused `import GameCenterClient`.
- `Packages/SudokuKit/Sources/SudokuUI/Completion/CompletionViewModel.swift` — `viewLeaderboardTapped()` now calls `GameCenterDashboard.present(leaderboardId:)`; removed dead `path: [AppRoute]` property; updated doc-header.

**Modified (tests):**
- `Packages/SudokuKit/Tests/SudokuUITests/AppRouteTests.swift` — removed `.leaderboard` from the `allCasesHashableAndSendable` array; renamed `codableRoundTripCompletionToLeaderboard` → `codableRoundTripBoardToCompletion` (the deepest stack push that still exists post #49).
- `Packages/SudokuKit/Tests/SudokuUITests/CompletionViewTests.swift` — removed `viewLeaderboardTapped_appendsLeaderboardRoute` test; replaced with an inline comment explaining why (the new behavior reaches `GKAccessPoint` and is exercised manually in Phase 10 sandbox validation per plan.md §10.2).
- `Packages/SudokuKit/Tests/SudokuUITests/HomeViewTests.swift` — no change (already only tested daily / practice / settings; never tested `.leaderboard` selection).
- `Packages/SudokuKit/Tests/SudokuUITests/RootViewTests.swift` — no change (no leaderboard assertions).

**Modified (spec / docs):**
- `docs/design.md` — §How.3.3 (annotated `fetchLeaderboardSlice` kept-but-narrowed scope); §How.3.4 (auth-state table renamed last column "Leaderboard UI" → "Apple 原生 GC dashboard"); §How.3.5 (fixed `globalTop`/`aroundPlayer`/`friendsOnly` → real enum case names `globalAllTime`/`globalToday`/`friendsAllTime`; rewrote the 3-view table to reflect native dashboard ownership); §How.5.1 (removed `LeaderboardView` row, replaced 8-View count with 7-View, added native-dashboard entry-points paragraph); §How.5.2 (rewrote mermaid graph removing `LB` node + replacing with `(Apple GC native dashboard)` modal node; updated AppRoute snippet to 6 cases; replaced "footnote" paragraph with native-dashboard description + foundations §2 exception note); §How.5.4 (removed `LeaderboardViewModel` row); §How.5.9 (updated `LeaderboardView` cell); §Decisions (updated "AppRoute 7 case → 6 case"; rewrote "Native GameCenter UI switch" Decision from "in flight" → "landed 2026-05-20"); §不在 v1 範圍 §在地化 (added `gc.leaderboard.*` xcstrings cleanup backlog entry).
- `docs/designs/07-leaderboard.md` — full file replacement: ~80-line decision note covering choice / triggers / Apple-handled features / mini-slice retention / API choice / Mac unauth UX / foundations exception / out-of-scope.
- `docs/feature-tour.md` — §🏆 Game Center 整合 first bullet appended with one-clause native-UI mention.
- `docs/design-mockup.html` — header `meta` 18 → 15 screens; FLOW 6 title "Leaderboard & Settings" → "Settings" + count "4 screens" → "1 screen" + retirement note; deleted S15 (Global), S16 (Friends), S17 (AX3) phone frames (~110 lines of HTML markup); renumbered former S18 (Settings) → S15 (label + `id`); arrows layer: deleted "S13 → S15", "S15 ↔ S16", "S16 → S17" paths; converted "S02 → S15 (Leaderboard)" + "S12 → S15 (View full leaderboard)" from drawn paths to annotation-only text (present-native-modal); redirected "S02 → S18 Settings" to "S02 → S15 Settings"; updated tokens-panel paragraph mentioning S15–S17; updated A11y baseline `Dynamic Type` bullet (AX3 row stacks → Apple's responsibility); updated the LB-row token component caption to clarify it's only for CompletionView mini-slice.
- `docs/foundations.md` — §2 item 4 amended with the GameKit/UIKit/AppKit import exception for `GameCenterDashboard.swift`.

### Screen-count delta (design-mockup.html)

- **Frames**: 18 → 15 (S15 Leaderboard-global, S16 Leaderboard-friends, S17 Leaderboard-AX3 deleted; former S18 Settings renumbered to S15).
- **Arrows deleted**: 3 (S13→S15 dashed conditional sign-in; S15↔S16 scope toggle double-headed; S16→S17 dashed AX3 variant).
- **Arrows redirected**: 1 (S02→S18 Settings rerouted to S02→S15 Settings after renumbering).
- **Arrows converted to annotation-only**: 2 (S02→S15 Leaderboard, S12→S15 View-full-leaderboard — both now present a native modal with no in-app destination).

### §未決 resolution status

1. ✓ API spelling — fallback to hybrid (Option A for nil + Option B for focused ID). Documented in §偏離 #1.
2. ✓ Mac unauth UX — documented in `docs/designs/07-leaderboard.md` §f as "no special handling needed; Apple's dashboard shows its own sign-in affordance".
3. ✓ Path 5a — Leader approved; kept `fetchLeaderboardSlice` + `Slice.swift` + `LeaderboardSliceService` + `LeaderboardSliceTests` + CompletionView's embedded top-3 slice.
4. ✓ `docs/designs/07-leaderboard.md` replacement — implemented per draft (§a Decision, §b Triggers, §c Native features, §d Mini-slice, §e API choice, §f Mac unauth, §g Foundations exception, §h Out of scope).
5. ✓ AppRoute Codable migration — confirmed no `SceneStorage`-persisted paths in codebase; safe to remove case. Test `codableRoundTripCompletionToLeaderboard` rewritten to `codableRoundTripBoardToCompletion`.
6. ✓ `gc.leaderboard.*` xcstrings — left in place for this PR; backlog entry filed in `docs/design.md §不在 v1 範圍 §在地化`.
