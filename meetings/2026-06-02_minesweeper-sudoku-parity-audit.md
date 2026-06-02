# Minesweeper-Sudoku Parallel Structure Audit

**Date**: 2026-06-02
**Auditor**: Code Reviewer (parallel-audit dispatch)
**Rubric**: `feedback/minesweeper-mirrors-sudoku.md` — mirror everything except the gameplay screen.

## Summary

Minesweeper currently mirrors Sudoku in the *frame* (App entry, Tuist target, Package shape, entitlements, asset catalogs, xctestplan structure, GameShellUI-backed root and Settings shell) and in the **core gameplay engine** (`MinesweeperEngine` + `MinesweeperGameState` siblings to `SudokuEngine` + `GameState`). Every divergence beyond that is justified in code comments as "deferred", which is exactly the gap this audit must surface.

The frame is excellent — `MinesweeperApp.swift` reads as one expression `composition.rootView`, just like `SudokuApp`; `MinesweeperAppComposition` consciously copies Sudoku's `AppComposition` shape; `MinesweeperRoot` consciously copies `RootView`; entitlements / asset catalogs are byte-equivalent. The big gaps are below the frame: **no Persistence, no Telemetry, no GameCenter, no Monetization (AdGate/IAP/Banner), no Daily, no Practice, no Completion, no Leaderboard, no ToastController, no Theme**. Settings is a "Coming soon" placeholder. `AppRoute` only has `.board` + `.settings` (vs Sudoku's 6 cases).

Worst case to highlight: **PrivacyInfo.xcprivacy is copied verbatim from Sudoku**, declaring `NSPrivacyTracking=true` and the AdMob tracking-domain list **even though Minesweeper does not link AdMob and does not surface NSUserTrackingUsageDescription in Info.plist**. This is shipping a privacy manifest that overstates Minesweeper's data collection. Either the wire actually needs to land, or the manifest must be flipped to "no tracking" — current state misrepresents the binary.

## Audit matrix

| Area | Sudoku location | Minesweeper location | Status | Notes |
|---|---|---|---|---|
| App entry (`@main`) | `Sudoku/SudokuApp.swift` | `Minesweeper/MinesweeperApp.swift` | ✅ Mirrors | Both 13 lines, both read `composition.rootView`. Sudoku attaches `.task { bootMonetization }` inside `AppComposition.rootView`; Minesweeper has no equivalent (no monetization yet). |
| AppComposition shape | `Packages/SudokuKit/Sources/AppComposition/{AppComposition,Live,Preview}.swift` | `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/{MinesweeperAppComposition,LiveRouteFactory}.swift` | ⚠️ Diverged (scoped down) | Sudoku bag carries 12 deps (rootVM, routeFactory, puzzleProvider, persistence, gameCenter, telemetry, errorReporter, adProvider, iapClient, adGate, monetizationStateStore, monetizationController, toastController) + `bootMonetization()`. Minesweeper bag carries 1 (`routeFactory`). No `Preview.swift`, no `Tests` factory. By the mirror rubric this is the largest single divergence — but each missing dep traces to a real downstream missing subsystem below. |
| RootView / Sidebar | `Packages/SudokuKit/Sources/SudokuUI/Root/{RootView,RootViewModel}.swift` | `Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperRoot.swift` | 🟡 Partial | Both wrap `GameShellUI.RootShellView`. Sudoku sidebar = [Daily, Practice, Leaderboard, Settings]; Minesweeper sidebar = [New Game, Settings]. Sudoku has a `RootViewModel` with `bootstrap()` + `resumeCandidate`; Minesweeper holds local `@State path` with no VM. Mirror principle: a `MinesweeperRootViewModel` should exist even if `resumeCandidate` is stubbed `nil` until persistence lands. |
| Navigation: AppRoute | `Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift` (6 cases) | `Packages/MinesweeperKit/Sources/MinesweeperUI/AppRoute.swift` (2 cases) | 🟡 Partial | Sudoku: `home / daily / practice / board(puzzleId) / completion(...) / settings`, `Codable`. Minesweeper: `board(difficulty, seed) / settings`, *not* `Codable`. Once Daily/Practice/Completion land they belong here. `Codable` is the deep-link round-trip property — defer is fine, but tag the divergence. |
| Navigation: RouteFactory | `Packages/SudokuKit/Sources/SudokuUI/Navigation/RouteFactory.swift` + `Packages/SudokuKit/Sources/AppComposition/` (LiveRouteFactory in package) | `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/LiveRouteFactory.swift` | ✅ Mirrors (shape) | Both conform to `GameShellUI.RouteFactory<AppRoute>`. Shapes align — Minesweeper just covers fewer routes because fewer destinations exist. |
| Daily hub | `Packages/SudokuKit/Sources/SudokuUI/Daily/{DailyHubView,DailyHubViewModel}.swift` | — | 🔴 Missing | No Minesweeper equivalent. Per rubric, "Daily for Minesweeper" should exist (date-seeded board, completion checkmark). The `NewGameView` comment explicitly says "Daily-style date seeding is out of scope". |
| Practice hub | `Packages/SudokuKit/Sources/SudokuUI/Practice/{PracticeHubView,PracticeHubViewModel}.swift` | — | 🔴 Missing | No Minesweeper equivalent. `NewGameView` is doing double duty as "the picker", which is fine as a stand-in for Practice but should not block a real Practice hub. |
| Home hub | `Packages/SudokuKit/Sources/SudokuUI/Home/{HomeView,HomeViewModel}.swift` | — (root content is `NewGameView`) | 🔴 Missing | Sudoku's HomeView is the root content with mode cards + banner slot + Remove Ads card. Minesweeper's root content is the difficulty picker. By mirror rubric, root content should be a "hub" not a picker — the picker belongs inside Practice. |
| Completion view | `Packages/SudokuKit/Sources/SudokuUI/Completion/{CompletionView,CompletionViewModel}.swift` | — | 🔴 Missing | No win-screen surface on the Minesweeper side. Currently win/loss must be inside `MinesweeperBoardView`. Mirror rubric expects a dedicated route. |
| Settings page | `Packages/SudokuKit/Sources/SudokuUI/Settings/{SettingsView,SettingsViewModel}.swift` | `Packages/MinesweeperKit/Sources/MinesweeperUI/SettingsView.swift` | 🟡 Partial | Both wrap `SettingsShellView`. Sudoku has Purchases (Remove Ads + Restore), About (Version + Generator), Storage (Clear cache). Minesweeper has a single `Section { Text("Coming soon") }`. About / Version is trivially addable today (no subsystem deps); Purchases requires monetization wire; Storage requires persistence. |
| Persistence | `Packages/PersistenceKit/Sources/Persistence/` (CloudKit Private DB, SavedGameStore, MonetizationStateStore) | — | 🔴 Missing | iCloud container is provisioned in entitlements (`iCloud.com.wei18.minesweeper`) but no Persistence target exists for Minesweeper. SavedGame / resume / monetization-state-store are all unreachable. |
| Monetization: AdGate | `Packages/AppMonetizationKit/Sources/MonetizationCore/AdGate.swift` (consumed in Sudoku Live) | — | 🔴 Missing | Not wired into Minesweeper's composition. |
| Monetization: IAP | `IAPStoreKit2` + `iap.remove_ads` product (Sudoku) | — | 🔴 Missing | No StoreKit2 client, no `.storekit` config file, no product ID declared. |
| Monetization: Banner | `BannerSlotView` (SudokuUI/Components) + `LiveAdMobAdProvider` | — | 🔴 Missing | No banner mount. |
| Monetization: Boot order | `AppComposition.bootMonetization()` (UMP → ATT → AdMob) | — | 🔴 Missing | Minesweeper `App.body` has no `.task`. |
| Game Center | `Packages/GameCenterKit/Sources/GameCenterClient/` + Sudoku Leaderboard sidebar + `GameCenterDashboard.present()` | — | 🔴 Missing | Entitlement `com.apple.developer.game-center=true` is set, but no client wired, no leaderboard / achievement IDs registered, no sidebar entry. |
| Telemetry | `Packages/TelemetryKit/Sources/Telemetry/` (OSLogSink, NoOpTrackingSink, MetricKitSink) | — | 🔴 Missing | No Telemetry instance. No `OSLogSink(subsystem: "com.wei18.minesweeper")`. |
| ErrorReporter | `LiveErrorReporter` over Telemetry (M10 / issue #67) | — | 🔴 Missing | Tied to Telemetry above. |
| ToastController | `Packages/SudokuKit/Sources/SudokuUI/Components/ToastView.swift` + `.toastOverlay()` on RootView | — | 🔴 Missing | No transient bottom surface. |
| Theme | `Packages/SudokuKit/Sources/SudokuUI/Theme/{Theme,DefaultTheme}.swift` + `@Environment(\.theme)` | — | 🔴 Missing | No theme target, no `@Environment(\.theme)` reads anywhere in `MinesweeperUI`. Backgrounds, accent tints, status colors all rely on SwiftUI defaults. Note: `Theme` lives in `SudokuUI` today, not in `GameShellUI` — so genuine sharing requires either (a) extract Theme into GameShellUI, or (b) Minesweeper ships a parallel `MinesweeperTheme`. The mirror principle leans (a). |
| AppIcon catalog (iOS) | `Sudoku/Assets.xcassets/AppIcon.appiconset/` (Light/Dark/Tinted) | `Minesweeper/Assets.xcassets/AppIcon.appiconset/` | ✅ Mirrors | Identical 3-PNG single-1024 shape. PNG bytes differ (different art) — correct. |
| AppIcon catalog (macOS) | `Sudoku/Assets.xcassets/AppIcon-macOS.appiconset/` (16…512 ladder) | `Minesweeper/Assets.xcassets/AppIcon-macOS.appiconset/` | ✅ Mirrors | Identical 10-PNG ladder filenames. |
| Info.plist | `Sudoku/Info.plist` | `Minesweeper/Info.plist` | ⚠️ Diverged (intentionally) | Minesweeper is missing: `ITSAppUsesNonExemptEncryption`, `GADApplicationIdentifier`, `NSGameKitFriendListUsageDescription`, `NSUserTrackingUsageDescription`. ATT + GADApplicationIdentifier divergence is consistent with no-monetization-yet. `ITSAppUsesNonExemptEncryption=false` should mirror as a trivial fast-follow (export-compliance prompt on every TestFlight upload otherwise). |
| Entitlements | `Sudoku/Sudoku.entitlements` | `Minesweeper/Minesweeper.entitlements` | ✅ Mirrors | Same 4 keys; only container ID differs (correct). |
| PrivacyInfo.xcprivacy | `Sudoku/Resources/PrivacyInfo.xcprivacy` | `Minesweeper/Resources/PrivacyInfo.xcprivacy` | ⚠️ Diverged (wrong direction) | Minesweeper's manifest is a verbatim copy of Sudoku's including `NSPrivacyTracking=true` and the AdMob tracking-domain list — **but Minesweeper does not link AdMob, has no NSUserTrackingUsageDescription, and cannot present ATT**. The copy is anticipatory ("flip to `false` if Minesweeper's monetization plan diverges from Sudoku's"). Either land Minesweeper monetization now or flip the manifest to `false` + empty arrays. Current state is misrepresentation. |
| xctestplan | `Sudoku/Sudoku.xctestplan` (12 test targets) | `Minesweeper/Minesweeper.xctestplan` (3 test targets) | 🟡 Partial | Shapes align (containerPath form, single Configuration). Minesweeper has Engine + GameState + UI; missing tests trace to missing subsystems (no Telemetry/Persistence/MonetizationCore/AppCompositionTests). Tracks naturally. |
| Tuist target | `Project.swift` `sudokuTarget` (deps: SudokuUI, AppComposition, MonetizationCore, AdsAdMob, IAPStoreKit2; resources include `.storekit` + Settings.bundle) | `Project.swift` `minesweeperTarget` (deps: MinesweeperUI, MinesweeperAppComposition) | 🟡 Partial | Shape mirrors. Missing: monetization links (would be needed before AdMob slices embed correctly), `.storekit` config file (no IAP yet), Settings.bundle glob (no LicensePlist acknowledgements page). The `.storekit` and Settings.bundle are downstream of subsystem wiring, not standalone gaps. |
| Package.swift | `Packages/SudokuKit/Package.swift` (PuzzleStore, SudokuUI, SudokuKitTesting, AppComposition, ASCRegister) | `Packages/MinesweeperKit/Package.swift` (MinesweeperUI, MinesweeperAppComposition) | 🟡 Partial | Both Swift 6, both `iOS(.v26) / macOS(.v26)`, both strict concurrency. Missing: `MinesweeperKitTesting` target (no shared fakes), `MinesweeperAppCompositionTests` test target, snapshot-testing dep, ASCRegister-equivalent leaderboard/achievement bootstrap. |
| Core engine package | `Packages/SudokuCoreKit` (SudokuEngine + GameState) | `Packages/MinesweeperCoreKit` (MinesweeperEngine + MinesweeperGameState) | ✅ Mirrors | Both pure-Swift, two-target, zero framework imports. Module names disambiguated (`MinesweeperGameState` vs `GameState`) for Tuist co-residency. |
| Snapshot tests | `SudokuUITests` carves `__Snapshots__/` as resource; uses `pointfreeco/swift-snapshot-testing` | `MinesweeperUITests` — no snapshot tests | 🔴 Missing | No snapshot baselines, no `swift-snapshot-testing` dep. `swift-testing-baseline` skill calls these mandatory. |
| Localizable.xcstrings | `Sudoku/Resources/Localizable.xcstrings` | `Minesweeper/Resources/Localizable.xcstrings` | (out of scope per task) | Per task scope, defer audit. Presence confirmed. |
| StoreKit config | `Sudoku/Resources/Sudoku.storekit` | — | 🔴 Missing | No StoreKit config file. Sudoku scheme's runAction wires it via `storeKitConfigurationPath`. |
| LicensePlist Settings.bundle | `Sudoku/Resources/Settings.bundle/**` (gitignored, CI-generated) | — | 🔴 Missing | No equivalent in Minesweeper Tuist resources block. Needed for the App Store acknowledgements page once dependencies (esp. monetization SDKs) link. |

## Backlog — recommended issues to file

### 1. Privacy manifest misrepresents Minesweeper data collection
- **Gap**: `Minesweeper/Resources/PrivacyInfo.xcprivacy` is a verbatim copy of Sudoku's, claiming `NSPrivacyTracking=true` plus AdMob tracking domains, while the actual binary doesn't link AdMob, has no ATT key, and cannot collect that data.
- **Effort**: S — flip to `NSPrivacyTracking=false` + empty `NSPrivacyTrackingDomains` + empty `NSPrivacyCollectedDataTypes` array; keep the manifest in place. Or, conversely, do the full monetization wire and keep the existing content.
- **Blocked by**: nothing (Leader-doable). The decision is "ship clean manifest now, flip later when monetization actually lands" vs "wait for monetization".
- **Priority signal**: **High** — ASC will reject submissions whose runtime behavior contradicts the privacy manifest. Pre-v2.5 / pre-first-TestFlight blocker for Minesweeper.
- **Suggested issue title**: `fix(minesweeper): correct PrivacyInfo.xcprivacy to reflect no-tracking baseline`

### 2. Telemetry / OSLog wire — first observability spine
- **Gap**: No `Telemetry` instance, no `OSLogSink(subsystem: "com.wei18.minesweeper")`. All Minesweeper crashes / errors are invisible to MetricKit + OSLog.
- **Effort**: S — `MinesweeperAppComposition` adds a `telemetry: Telemetry` stored property, Live wires `OSLogSink + NoOpTrackingSink + MetricKitSink`. No protocol surface changes anywhere else; nothing currently emits events.
- **Blocked by**: none.
- **Priority signal**: **High** — observability gap before TestFlight; cheap to land.
- **Suggested issue title**: `feat(minesweeper): wire Telemetry facade + OSLog/MetricKit sinks`

### 3. ErrorReporter unified funnel
- **Gap**: No `LiveErrorReporter` in Minesweeper. Catch sites in `MinesweeperSession` / `MinesweeperEngine` have no place to route.
- **Effort**: S (depends on #2). Add `errorReporter: any ErrorReporter` to the bag, wire `LiveErrorReporter(telemetry:)`.
- **Blocked by**: Telemetry (#2).
- **Priority signal**: High alongside #2.

### 4. Persistence (CloudKit Private DB) for SavedGame + resume
- **Gap**: No Persistence target. iCloud container exists in entitlements but is unused. No `SavedGameStore`, no `MonetizationStateStore`, no resume pill possible.
- **Effort**: M — likely extract a `MinesweeperPersistence` target inside `PersistenceKit` (the CK record types diverge: Sudoku stores puzzleId, Minesweeper would store difficulty + seed + revealed-mask + flag-mask). Schema design is the bulk; plumbing mirrors Sudoku.
- **Blocked by**: user-owned CloudKit container schema deploy via CK Dashboard; `feedback/asc-ops-handoff` covers the handoff shape. RootViewModel `resumeCandidate` is gated on this.
- **Priority signal**: Medium — Sudoku's resume pill is a v2 feature; Minesweeper can ship without resume initially, but you've already provisioned the container.
- **Suggested issue title**: `feat(minesweeper): SavedGameStore over CloudKit Private DB + resume pill`

### 5. Game Center wire (leaderboards + achievements)
- **Gap**: Entitlement `com.apple.developer.game-center=true` is set but no `GameCenterClient` wired, no Leaderboard sidebar entry, no achievement IDs registered.
- **Effort**: M — wire `LiveGameCenterClient(authDriver: GKAuthDriver())` in `MinesweeperAppComposition.live()`; add sidebar item for `GameCenterDashboard.present()`. Achievement / leaderboard ID catalog + ASCRegister-equivalent bootstrap.
- **Blocked by**: user-owned ASC steps (register leaderboards/achievements via ASCRegister CLI flow per `asc-ops-handoff`). Code side is Leader-doable.
- **Priority signal**: Medium — competitive Minesweeper times are an obvious leaderboard. Pre-v1-release.
- **Suggested issue title**: `feat(minesweeper): Game Center client + Leaderboard sidebar + ASCRegister bootstrap`

### 6. Monetization wire (AdGate + IAP + Banner + Boot order)
- **Gap**: No `AdGate`, no `IAPStoreKit2` client, no `BannerSlotView`, no `bootMonetization()`. `MonetizationStateController` + `ToastController` also absent.
- **Effort**: L — mirrors Sudoku's `Live.swift` block (lines 60–150) plus `MonetizationBootCoordinator`. Per-app banner unit ID + Remove Ads product ID need ASC registration.
- **Blocked by**: user-owned AdMob console (new app + ad unit ID) and ASC IAP product registration; Info.plist needs `GADApplicationIdentifier` + `NSUserTrackingUsageDescription`. See `feedback/admob-production-ids`.
- **Priority signal**: Medium — Sudoku's monetization model is v2; if Minesweeper ships free with no ads as v1, defer is fine. **If deferring, fix #1 first so the privacy manifest doesn't pre-declare AdMob.**
- **Suggested issue title**: `feat(minesweeper): wire AdGate / IAP / banner / monetization boot order`

### 7. Theme extraction or parallel theme
- **Gap**: No `@Environment(\.theme)` reads in `MinesweeperUI`. SwiftUI defaults applied everywhere.
- **Effort**: M — recommended path: extract `Theme` protocol + `ThemeColor` into `GameShellUI` (game-agnostic), keep `DefaultSudokuTheme` and add `DefaultMinesweeperTheme` (different difficulty tints, accent palette).
- **Blocked by**: design decision (Leader + user). Could be done before #4/#5/#6.
- **Priority signal**: Medium — affects visual identity, but not functionality. Visual consistency win.
- **Suggested issue title**: `refactor(shell): extract Theme into GameShellUI; add MinesweeperTheme`

### 8. Daily hub for Minesweeper
- **Gap**: Sudoku has Daily (3 cards/day, completion checkmark, exhaustion alert). Minesweeper has none. `NewGameView` only generates random seeds per tap.
- **Effort**: M — copy `DailyHubView` + `DailyHubViewModel` shape, adapt for Minesweeper (difficulty triplet → seed-from-date).
- **Blocked by**: Persistence (#4) for completion checkmark; product decision on what "Daily Minesweeper" means.
- **Priority signal**: Medium — meaningful UX hook. Per mirror rubric, this is in scope.
- **Suggested issue title**: `feat(minesweeper): Daily hub mirroring Sudoku's date-seeded picker`

### 9. Practice hub for Minesweeper
- **Gap**: Sudoku has Practice as a distinct hub destination. Minesweeper conflates "Practice" into root content (`NewGameView`).
- **Effort**: M — move difficulty picker out of root content into a `PracticeHubView`, give Minesweeper a real `HomeView` for root content with mode cards (Daily / Practice / Leaderboard / Remove Ads). Aligns AppRoute case set with Sudoku.
- **Blocked by**: design decision on whether MS Home hub mirrors Sudoku Home's card grid.
- **Priority signal**: Medium — depends on #8 landing first.
- **Suggested issue title**: `feat(minesweeper): split NewGameView into HomeView + PracticeHub`

### 10. Completion view
- **Gap**: No `CompletionView` route. Win/loss handling currently lives inside the BoardView.
- **Effort**: S–M — stand up `CompletionView` + `CompletionViewModel`; `AppRoute.completion(seed, difficulty, elapsedSeconds, didWin)`.
- **Blocked by**: gameplay screen design decides what stats to show. Game-Center submission (best time) belongs here, so this couples with #5.
- **Priority signal**: Medium — needed before leaderboards have anywhere to submit from.
- **Suggested issue title**: `feat(minesweeper): CompletionView route + win/loss summary`

### 11. `MinesweeperAppComposition.preview()` factory
- **Gap**: Only `.live()` exists. `Preview.swift` (Sudoku) is missing.
- **Effort**: S — add when the bag has more than one dep so SwiftUI Previews can render destinations.
- **Blocked by**: bag growing (#2/#4/#5/#6).
- **Priority signal**: Low — quality-of-life for Previews.

### 12. `MinesweeperKitTesting` target
- **Gap**: Sudoku has shared fakes (`SudokuKitTesting`); Minesweeper has none. Each test file builds its own fakes inline.
- **Effort**: S — add the target once 2+ test targets share a fake. Currently both test targets are small enough not to demand this.
- **Blocked by**: nothing; speculative until duplication exists.
- **Priority signal**: Low.

### 13. Snapshot tests
- **Gap**: No `pointfreeco/swift-snapshot-testing` dep, no `__Snapshots__/` baselines for Minesweeper UI.
- **Effort**: M — add the dep, mirror `SudokuUITests` snapshot layout, baseline `NewGameView` / `SettingsView` / `MinesweeperBoardView`.
- **Blocked by**: nothing.
- **Priority signal**: Medium — `swift-testing-baseline` skill calls these mandatory.

### 14. StoreKit config + Settings.bundle (LicensePlist)
- **Gap**: No `Minesweeper.storekit` config file referenced from Tuist scheme runAction; no Settings.bundle glob in resources.
- **Effort**: S — adds with #6.
- **Blocked by**: #6.
- **Priority signal**: Low (couples with #6).

### 15. Info.plist parity — encryption export
- **Gap**: Missing `ITSAppUsesNonExemptEncryption=false`. Every TestFlight upload will prompt for export compliance.
- **Effort**: S — single key add.
- **Blocked by**: nothing.
- **Priority signal**: High — trivial fix, big nuisance saved.
- **Suggested issue title**: `chore(minesweeper): set ITSAppUsesNonExemptEncryption to skip TestFlight prompt`

### 16. RootViewModel for Minesweeper
- **Gap**: `MinesweeperRoot` holds `@State var path` directly; no VM. Sudoku has `RootViewModel` with `bootstrap()` + `resumeCandidate` + `resumeTapped()`.
- **Effort**: S — stand up `MinesweeperRootViewModel` even if `bootstrap()` is empty and `resumeCandidate == nil`. Future-proofs the Resume pill.
- **Blocked by**: nothing (skeleton); functional `resumeCandidate` needs #4.
- **Priority signal**: Medium.

## Risks

- **Risk 1 — "deferred" comments are accumulating without owning issues.** Every Minesweeper file says some variant of "X is deferred — see follow-up issues". If those issues are not in the GitHub tracker, the deferred work is invisible. This audit should produce the issue stubs.
- **Risk 2 — PrivacyInfo verbatim copy is a submission blocker.** ASC's privacy review correlates manifest claims against runtime behavior; declaring AdMob tracking with no AdMob SDK present is exactly the kind of mismatch ASC flags. This is the only "you can't ship like this" item in the audit.
- **Risk 3 — Theme drift will harden before extraction.** The longer `MinesweeperUI` ships without `@Environment(\.theme)` reads, the more visual call-sites use raw SwiftUI colors / `Color.primary`. Once a few screens land that way, extraction means rewriting every call-site. Cheap to land before BoardView grows.
- **Risk 4 — Practice/Daily skipped on the "X5 hubs extraction" rationale.** Track B note (observation 2117) recommends skipping the standalone phase that would have extracted Daily/Practice into GameShellUI. The mirror principle says the right move is **copy-paste-and-adapt** Sudoku's two hub files into MinesweeperUI, not extract. Confirm Leader still agrees with that direction after reading this audit — extraction is fine *later* if both hubs converge, but copy-paste now respects the rubric.
- **Risk 5 — `MinesweeperGameState` module name vs `GameState`.** Tuist co-residency forced disambiguation. If a third game ever lands, this naming choice (game-prefixed) should become the convention; this is a methodology observation worth a §Backlog entry in `docs/foundations.md`.

## Files audited

- `/Users/zw/GitHub/Wei18/Sudoku-spec/Project.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/SudokuApp.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Info.plist`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Sudoku.entitlements`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Sudoku.xctestplan`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Resources/PrivacyInfo.xcprivacy`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Assets.xcassets/AppIcon.appiconset/` (directory)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Sudoku/Assets.xcassets/AppIcon-macOS.appiconset/` (directory)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/MinesweeperApp.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Info.plist`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Minesweeper.entitlements`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Minesweeper.xctestplan`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Resources/PrivacyInfo.xcprivacy`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Assets.xcassets/AppIcon.appiconset/` (directory)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Minesweeper/Assets.xcassets/AppIcon-macOS.appiconset/` (directory)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Package.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/AppComposition/AppComposition.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/AppComposition/Live.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/Root/RootView.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/Navigation/AppRoute.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/Daily/DailyHubView.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/Settings/SettingsView.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/Theme/Theme.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/SudokuKit/Sources/SudokuUI/` (directory listing)
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Package.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperAppComposition/MinesweeperAppComposition.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperAppComposition/LiveRouteFactory.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperUI/MinesweeperRoot.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperUI/SettingsView.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperUI/NewGameView.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperKit/Sources/MinesweeperUI/AppRoute.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/MinesweeperCoreKit/Package.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/GameShellKit/Package.swift`
- `/Users/zw/GitHub/Wei18/Sudoku-spec/Packages/GameShellKit/Sources/GameShellUI/` (directory listing)
