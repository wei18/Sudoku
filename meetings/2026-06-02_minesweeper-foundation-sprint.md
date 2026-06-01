# 2026-06-02 Minesweeper Foundation Sprint — Session Log

Single session capturing the Minesweeper foundation work + Sudoku icon cleanup + shell extraction Phase X1-X4.

## Scope

User goal: "新增 Minesweeper App, 其他 (shell / settings / monetization / persistence) 全部跟 Sudoku 共用"; plus side-quests on AppIcon catalog + workflow polish.

## Merged PRs (16 total this session)

### Minesweeper foundation (4-PR arc + skeleton)
- **#219** `refactor(persistence)` — `PrivateCKConfig` per-app injection (zone / subscription); `.sudoku` constant; record-type names stay shared
- **#220** `refactor(monetization)` — `LiveAdMobBridge(bannerAdUnitID:)` + `LiveStoreKit2IAPClient(knownProductIds:)`; v2.5.3 fatalError safety relocated to `AppComposition.Live`
- **#222** `refactor(tuist)` — `App/` → `Sudoku/`; `Project(name: "Sudoku")` → `"Game"`; admin-bypass merge because XCC pointed at old workspace name
- **#223** `feat(minesweeper)` — app target skeleton + `MinesweeperCoreKit` (`MinesweeperEngine` placeholder) + `MinesweeperKit` (`MinesweeperUI` + `MinesweeperAppComposition` placeholders); separate `iCloud.com.wei18.minesweeper` container

### Bug fixes (4)
- **#218** `fix(ads)` — UMP consent form load on `@MainActor` (was crashing iOS at launch)
- **#229** `fix(board)` — `GameViewModel.startOrResume()` after `BoardLoaderView.load()` + 1Hz `.task` ticker for `refreshElapsed()`; closes #227 (Mac board timer stuck + digit pad dead)
- **#230** `feat(daily)` — `SavedGameStore.latestInProgress()` filters stale daily saves; `GameViewModel.isLateCompletion` + BoardView header marker; closes #228 E+B

### Shell extraction (Phase X, X1-X4)
- **#224 X1** — `NavigationStackHost<Route: Hashable, ...>` extracted into new `GameShellKit/Sources/GameShellUI/`
- **#226 X2** — `RouteFactory<Route>` protocol (primary associated type) extracted; `LiveRouteFactory` stays in SudokuKit
- **#232 X3** — `RootShellView<Route, RootContent>` + `SidebarItem<Route>` value type; Sudoku's `RootView` shrinks to wrapper
- **#239 X4** — `SettingsShellView<Sections: View>` extracted (Form chrome only; rows/sections stay Sudoku-specific per "no premature abstraction")

### App icon polish (5)
- **#225** single 1024 universal AppIcon (initial direction — later partially reversed)
- **#231** Minesweeper v1 ship art + `app-icon-rasterize` skill + meeting design spec
- **#233** strip baked rounded corners from Sudoku finalists; drop unused `AccentColor.colorset`
- **#234** add Tinted variant (Xcode 26 Inspector only offers "None" or "Any+Dark+Tinted"; can't have Any+Dark only)
- **#238** **restore** macOS AppIcon ladder (Xcode 26 still requires 16/32/128/256/512 × 1x/2x for macOS; Single Size is iOS-only)

### Other
- **#235** `chore(workflows)` — `.claude/workflows/*.js` `/Users/zw/...` → relative `.`
- **#237** `feat(minesweeper)` — pure-Swift **engine MVP**, 51 tests / 9 suites; deferred mine placement + first-click safety + flood-fill + win/lose
- Direct push to main: docs(skill) macOS ladder `sips` recipe in `app-icon-rasterize`

## Key technical decisions

1. **Shared packages get app-specific Config via init injection** — not enum statics. Pattern: `PrivateCKConfig.sudoku`, `LiveStoreKit2IAPClient(knownProductIds: ...)`, `LiveAdMobBridge(bannerAdUnitID: ...)`. Required (no default) so Minesweeper can't accidentally inherit Sudoku's IDs.
2. **Phase X extraction order**: protocol → state-free shell → state-touching shell → ViewModels (X5+) → composition. Each PR keeps Sudoku byte-identical.
3. **App icon strategy** (post-thrash):
   - iOS: 1024 universal in `AppIcon.appiconset` with Light/Dark/Tinted appearance entries
   - macOS: full 10-PNG ladder in `AppIcon-macOS.appiconset` (Sequoia AppKit still requires it)
   - SVG sources MUST be full-bleed (no `rx/ry`); Apple's compositor applies the squircle mask
   - Rasterize: `qlmanage -t -s 1024` for the 1024 master; `sips -Z <N>` for macOS ladder downscale
4. **Sub-agent edits often sandbox-blocked** — fallback: subagent delivers verbatim diff, Leader applies. Used this pattern 6+ times this session (#229, #230, #232, #233, #237, #239 all had Sr Dev → Leader apply chains).

## Process feedback captured to memory

- `feedback-auto-act-on-green-prs.md` — "check" means check AND merge/act
- `feedback-project-scope-auto-execute.md` — anything under `~/GitHub/Wei18/` + already-installed binary = no prompt; git worktree paths auto-trusted; file create/edit included; scratch dir `~/GitHub/Wei18/tmp/`, NOT `/tmp/`
- `feedback-opportunistic-test-sweep.md` — while XCC disabled, run `swift test` on main during idle gaps

## XCC status

User hit Xcode Cloud usage limit mid-session and disabled it (2026-06-01). PRs after that point relied only on GitHub Actions (PR title + markdown + SwiftLint) for CI. Some PRs admin-bypass merged. **No new XCC runs until user re-enables** (probably next billing cycle).

## Open backlog snapshot

### Release blockers (Sudoku v2.5)
- #212 AdGate `gracePeriodDays` 0 → 7 revert
- #217 CloudKit Production schema deploy
- v2.5.3 paired flip: AdMob production app + banner unit IDs

### User-owned ops (Apple ecosystem)
- Xcode Cloud reconfig for `Game.xcworkspace` (was `Sudoku.xcworkspace`) — pending quota restore
- Provision `iCloud.com.wei18.minesweeper` CKContainer (before any Minesweeper CK code)
- ASC register `com.wei18.minesweeper.iap.remove_ads` + Minesweeper AdMob credentials
- #156 GitHub App bot identity
- #157 branch protection on main
- #132 TestFlight + ASC submission tracking
- #236 App Store review notes for Sudoku v2.5 + Minesweeper v1 (NEW this session)

### Tech debt
- #214 GameViewModel.swift > 400 lines (swiftlint disabled)
- #221 AdMob `dispose(handle:)` accessor
- #209 NSWindow-based snapshot harness
- #150 GameCenter leaderboard centring on non-local player
- SettingsIAPRowTests 2 snapshot drift (local-only, no issue filed)

### Next-up code work
- **MinesweeperCoreKit/GameState** actor wrapper (undo/redo, timer, actor isolation; mirrors SudokuCoreKit's two-module split)
- **X5** Daily / Practice hubs extraction
- **X6** AppComposition base extraction
- Minesweeper UI: BoardView + GameViewModel + persistence wire + monetization wire
- Minesweeper icon: replace placeholder copy of Sudoku assets with proper Minesweeper art (Designer spec already in `meetings/2026-06-01_minesweeper-icon-design.md`)

### Other
- #166 Android module portability (long-term)
- #167 XcodeSelectiveTesting evaluation
- #169 XCC PR-CI as required check
- #170 GitHub Action review agents
- #178 swift-issue-reporting evaluation
- #195 Permission request UX
- #200 ASC API tooling for IAP submission

## Worktree state at session close

Only `Sudoku-spec` (main, `3572a15`). All sibling worktrees cleaned up post-merge.
