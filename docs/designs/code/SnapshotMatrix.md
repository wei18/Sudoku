# Snapshot Matrix — v1 UI baseline

Tracks every PNG snapshot the snapshot-test target must produce. Aligns with `docs/v1/design.md §How.5.8` (21-view baseline) **plus** component-level snapshots so the user can visually grok every atomic UI piece.

Conventions:

- **Source file**: under `docs/designs/code/Components/` or `docs/designs/code/Views/`.
- **Variant params**: locale / colorScheme / dynamicTypeSize / sizeClass. Omitted columns inherit `en / light / .large / .compact`.
- **Mac variants**: Developer chooses the precise device trait (e.g. `.fixed(width: 900, height: 700)`) — see `// TODO: Developer chooses precise device size` below the table.
- **Total target**: ≈ 50 snapshots (21 view + 16 component-base + 13 component-variant).

---

## §1 View snapshots — §How.5.8 baseline (21)

### BoardView (12)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 1 | `boardView_iphone_light_en_empty` | `Views/BoardView_Designs.swift` | iPhone / light / en — `board: .demoEmpty` | empty grid |
| 2 | `boardView_iphone_light_en_inProgressErrors` | `Views/BoardView_Designs.swift` | iPhone / light / en — `board: .demoInProgressWithErrors` | mid-game with error cell |
| 3 | `boardView_iphone_light_en_aboutToComplete` | `Views/BoardView_Designs.swift` | iPhone / light / en — `board: .demoAboutToComplete` | last empty cell |
| 4 | `boardView_iphone_dark_ja_empty` | `Views/BoardView_Designs.swift` | iPhone / dark / ja — empty | ja for wide-glyph coverage |
| 5 | `boardView_iphone_dark_ja_inProgressErrors` | `Views/BoardView_Designs.swift` | iPhone / dark / ja — in-progress | ja |
| 6 | `boardView_iphone_dark_ja_aboutToComplete` | `Views/BoardView_Designs.swift` | iPhone / dark / ja — about-to-complete | ja |
| 7 | `boardView_iphone_light_ko_empty` | `Views/BoardView_Designs.swift` | iPhone / light / ko — empty | ko for ligature coverage |
| 8 | `boardView_iphone_light_en_paused` | `Views/BoardView_Designs.swift` | iPhone / light / en — `isPaused: true` | pause overlay |
| 9 | `boardView_mac_light_en_empty` | `Views/BoardView_Designs.swift` | Mac / light / en — empty | // TODO: Developer chooses precise device size |
| 10 | `boardView_mac_light_en_inProgressErrors` | `Views/BoardView_Designs.swift` | Mac / light / en — in-progress | TODO Mac device |
| 11 | `boardView_mac_dark_en_aboutToComplete` | `Views/BoardView_Designs.swift` | Mac / dark / en — about-to-complete | TODO Mac device |
| 12 | `boardView_mac_dark_ja_inProgressErrors` | `Views/BoardView_Designs.swift` | Mac / dark / ja — in-progress | TODO Mac device |

### DailyHubView (3)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 13 | `dailyHub_iphone_light_en_nonePlayed` | `Views/DailyHubView_Designs.swift` | iPhone / light / en — `state: .loaded(.demoNoneDone)` | |
| 14 | `dailyHub_iphone_light_en_easyDone` | `Views/DailyHubView_Designs.swift` | iPhone / light / en — `.demoEasyDone` | |
| 15 | `dailyHub_iphone_light_en_allDone` | `Views/DailyHubView_Designs.swift` | iPhone / light / en — `.demoAllDone` | |

### PracticeHubView (3)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 16 | `practiceHub_iphone_light_en_idle` | `Views/PracticeHubView_Designs.swift` | iPhone / light / en — `state: .idle` | |
| 17 | `practiceHub_iphone_light_en_drawingShimmer` | `Views/PracticeHubView_Designs.swift` | iPhone / light / en — `state: .drawing` | shimmer redacted card |
| 18 | `practiceHub_iphone_light_en_drawn` | `Views/PracticeHubView_Designs.swift` | iPhone / light / en — `state: .drawn(puzzleId: "24c8")` | |

### CompletionView (3)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 19 | `completion_iphone_light_zhTW_authenticated` | `Views/CompletionView_Designs.swift` | iPhone / light / zh-Hant — `state: .authenticated(...)` | zh-TW for hero long copy |
| 20 | `completion_iphone_light_en_unauthenticated` | `Views/CompletionView_Designs.swift` | iPhone / light / en — `.unauthenticated` | |
| 21 | `completion_iphone_light_en_fetchFailed` | `Views/CompletionView_Designs.swift` | iPhone / light / en — `.fetchFailed` | |

---

## §2 Non-baseline view snapshots (covers Views that 21-set doesn't include)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 22 | `root_iphone_light_en_withResume` | `Views/RootView_Designs.swift` | iPhone / light / en — `resume: .some` | |
| 23 | `root_iphone_light_en_noResume` | `Views/RootView_Designs.swift` | iPhone / light / en — `resume: nil` | |
| 24 | `root_mac_dark_ja_withResume` | `Views/RootView_Designs.swift` | Mac / dark / ja — `resume: .some` | TODO Mac device |
| 25 | `home_iphone_light_en` | `Views/HomeView_Designs.swift` | iPhone / light / en | |
| 26 | `home_mac_dark_ja` | `Views/HomeView_Designs.swift` | Mac / dark / ja | TODO Mac device |
| 27 | `leaderboard_iphone_light_en_loaded` | `Views/LeaderboardView_Designs.swift` | iPhone / light / en — `.loaded` | |
| 28 | `leaderboard_iphone_light_ja_unauthenticated` | `Views/LeaderboardView_Designs.swift` | iPhone / light / ja — `.unauthenticated` | |
| 29 | `leaderboard_iphone_light_en_error` | `Views/LeaderboardView_Designs.swift` | iPhone / light / en — `.error` | |
| 30 | `leaderboard_iphone_light_en_AX3_loaded` | `Views/LeaderboardView_Designs.swift` | iPhone / light / en / `dynamicTypeSize: .accessibility3` — `.loaded` | **AX3 vertical-stack row layout** (design-system §Dynamic Type item 5) |
| 31 | `settings_iphone_light_en` | `Views/SettingsView_Designs.swift` | iPhone / light / en | |
| 32 | `settings_mac_dark_ja` | `Views/SettingsView_Designs.swift` | Mac / dark / ja | TODO Mac device |
| 33 | `completion_mac_dark_ja_fetchFailed` | `Views/CompletionView_Designs.swift` | Mac / dark / ja — `.fetchFailed` | TODO Mac device |
| 34 | `completion_iphone_light_en_practiceMode` | `Views/CompletionView_Designs.swift` | iPhone / light / en — `.practiceMode` | Practice: no GC UI |

---

## §3 Component snapshots — atomic UI pieces (light + dark per component)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 35 | `modeCard_light_en` | `Components/ModeCard.swift` | light / en | |
| 36 | `modeCard_dark_en` | `Components/ModeCard.swift` | dark / en | |
| 37 | `puzzleCard_light_en_done` | `Components/PuzzleCard.swift` | light / en — `completedTime: "4:11"` | |
| 38 | `puzzleCard_light_en_pending` | `Components/PuzzleCard.swift` | light / en — `completedTime: nil` | |
| 39 | `puzzleCard_dark_en_done` | `Components/PuzzleCard.swift` | dark / en — `completedTime: "4:11"` | |
| 40 | `digitPad_light_en` | `Components/DigitPad.swift` | light / en | |
| 41 | `digitPad_dark_en` | `Components/DigitPad.swift` | dark / en | |
| 42 | `shimmerCard_light_en` | `Components/ShimmerCard.swift` | light / en | |
| 43 | `shimmerCard_dark_en` | `Components/ShimmerCard.swift` | dark / en | |
| 44 | `leaderboardRow_light_en_default` | `Components/LeaderboardRow.swift` | light / en — `isMe: false` | |
| 45 | `leaderboardRow_light_en_me` | `Components/LeaderboardRow.swift` | light / en — `isMe: true` | accent-tinted highlight |
| 46 | `leaderboardRow_dark_en_me` | `Components/LeaderboardRow.swift` | dark / en — `isMe: true` | |
| 47 | `leaderboardRow_light_en_AX3` | `Components/LeaderboardRow.swift` | light / en / `dynamicTypeSize: .accessibility3` | vertical-stack |
| 48 | `resumePill_light_en` | `Components/ResumePill.swift` | light / en | |
| 49 | `resumePill_dark_ja` | `Components/ResumePill.swift` | dark / ja | |
| 50 | `generatorExhaustedAlert_daily_light_en` | `Components/GeneratorExhaustedAlert.swift` | light / en — `surface: .daily` | |
| 51 | `generatorExhaustedAlert_practice_dark_en` | `Components/GeneratorExhaustedAlert.swift` | dark / en — `surface: .practice` | secondary "Switch difficulty" button |

---

## §4 CellView state variants (6 — drives the BoardView visual primitive)

| # | Test name | Source file | Variant params | Notes |
|---|---|---|---|---|
| 52 | `cellView_light_empty` | `Components/CellView.swift` | light — `.empty` | |
| 53 | `cellView_light_given` | `Components/CellView.swift` | light — `.given(5)` | bold + cell.prefilled bg |
| 54 | `cellView_light_user` | `Components/CellView.swift` | light — `.user(7)` | regular + text.user tint |
| 55 | `cellView_light_error` | `Components/CellView.swift` | light — `.error(7)` | bg + corner triangle + red digit |
| 56 | `cellView_light_selected` | `Components/CellView.swift` | light — `.selected(6)` | |
| 57 | `cellView_light_highlighted` | `Components/CellView.swift` | light — `.highlighted(nil)` | |
| 58 | `cellView_dark_error` | `Components/CellView.swift` | dark — `.error(7)` | dark-mode error palette |

---

## Coverage summary

| Group | Count |
|---|---|
| §1 — §How.5.8 baseline views | 21 |
| §2 — additional view variants | 13 |
| §3 — component base (light/dark per component) | 17 |
| §4 — CellView state grid | 7 |
| **Total** | **58** |

Meets the "40–50 snapshot" target with ~+8 buffer (room to trim if CI time becomes an issue — recommended trim order: drop §2 row 24/26/32/33 Mac duplicates first, then §3 dark-only duplicates).

---

## Notes for Developer

1. **Mac device traits**: `swift-snapshot-testing` doesn't ship a `.macBookPro13` trait. Recommended approach: use `.fixed(width: 900, height: 700)` (iPhone Mac mode) or a custom `ViewImageConfig(size: CGSize(width: 900, height: 700), traits: UITraitCollection(horizontalSizeClass: .regular))` factory. Search the markdown for `TODO: Developer chooses precise device size`.
2. **AX3 variant** (snapshot #30, #47): set `.environment(\.dynamicTypeSize, .accessibility3)` on the snapshot host — the components already branch on this value.
3. **Glass effect snapshot stability**: `.glassEffect()` rasterizes against whatever's behind it. Place every preview on a `DesignTokens.surfaceBackground` host before snapshotting; otherwise the glass material composites against a transparent test background and the diff fluctuates per Xcode build.
4. **Locale registration**: `LocalizedStringKey`s in this preview code resolve from the **default English bundle** unless the snapshot host imports a `Localizable.xcstrings`. For ja / ko / zh-Hant variants Developer should temporarily inject the localized strings (or accept English fallback for snapshot baseline if catalog is not yet committed).
5. **`.glassEffect` API**: requires iOS 26 / macOS 26 toolchain. Snapshot test target must inherit the package's `.platforms` list.
