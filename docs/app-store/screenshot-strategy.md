# App Store screenshot strategy

Capture plan for Sudoku v1 App Store storefront. This file specifies **what to shoot, in what order, at what dimensions, with what overlay text** for every supported device class and locale. Actual PNG capture is Phase 10 A5 (Xcode Simulator + Liquid Glass enabled).

> **Superseded by the pipeline below.** The "5-shot storyline" / "Shot 5 platform
> variant" sections immediately below are the original v1 capture plan and no
> longer match what `scripts/build-ascspec-screenshots.py` actually generates
> — see "Store-screenshot redesign — Direction C + B" further down for the
> real, current pipeline. Two concrete contradictions worth calling out
> (#984 caption-accuracy sweep): there is **no dedicated Leaderboard-screen
> slot** anywhere in the generator (`SLOTS`) — Shot 5 is Settings only, and
> **Sudoku-only** (Minesweeper has never had a Shot 5 / Settings slot on any
> device, including the new macOS arm's "06-stats", which is a different slot).

## Device classes (4) and required dimensions

| Class | Apple required dim (px) | Notes |
|---|---|---|
| iPhone 6.7" / 6.9" | 1290 × 2796 (preferred) or 1320 × 2868 | Hero — most discovery happens here |
| iPhone 6.5" | 1284 × 2778 or 1242 × 2688 | Legacy phones still in use |
| iPad Pro 12.9" (6th gen) | 2048 × 2732 | Landscape and portrait both acceptable; we use portrait |
| Mac | 1280 × 800 min, **2880 × 1800 preferred** | Window frame visible; Liquid Glass sidebar must render |

Screenshot count: **5 shots × 4 device classes × 7 locales = 140 PNG total**.

## The 5-shot storyline

| # | Screen | Why this shot | Hero element |
|---|---|---|---|
| 1 | Home (4 mode cards, Liquid Glass) | Entry point. Establishes brand: warm paper background, sage accents, Liquid Glass chrome. | Two large cards (Daily, Practice), translucent over warm paper |
| 2 | Daily Hub (3 difficulties) | The daily ritual hook. All three difficulties shown completed with a 7+ day streak to sell the habit payoff, not the empty-state grind. | Three difficulty rows, all badged done, streak strip up top |
| 3 | Board mid-game (active grid + sage selected cell) | Core gameplay experience. Shows pencil notes in at least one cell and an active row/col highlight. | 9×9 grid, one selected cell, soft sage highlight band |
| 4 | Completion (Solved + leaderboard slice) | The payoff moment. Calm "Solved" treatment (no confetti), with a 3-row leaderboard slice underneath showing world ranking. | "Solved" headline, time, top-3 leaderboard rows |
| 5 | Settings or Leaderboard depth | Differentiator proof — 7 locale picker visible **and** Game Center integration row. iPad/Mac variant emphasizes keyboard hint. | Locale list (7 rows), Game Center status row |

### Shot 3 visual rule
On the Mac and iPad classes, show the keyboard hint chip near the bottom: `←→↑↓ · 1–9 · ⌫ · ⌘Z`. iPhone classes hide this chip (no physical keyboard).

### Shot 5 platform variant
- iPhone 6.7" and 6.5": **Settings** screen (locale list + GC row)
- iPad Pro 12.9": **Leaderboard** screen (broader real-estate makes leaderboard the better hero; settings looks too sparse on iPad)
- Mac: **Leaderboard** screen, with sidebar showing all top-level navigation (Home / Daily / Practice / Settings)

## Overlay copy per locale

Each shot has a 2-line overlay: a **headline** (≤ 5 words) and a **subhead** (≤ 12 words). Overlay is placed in the top-third on iPhone and the top quarter on iPad / Mac. Background: warm-paper `#FAF8F3` at 92% opacity with sage `#5C7A4F` headline color.

### Shot 1 — Progress tab (Stats)

Repointed from the original "Home / Entry point" shot by #1040: the HOME
route was retired in #1038 (3-tab shell), which left the old baseline
(Today-tab empty state) identical in content to Shot 2's all-completed
DailyHub screenshot, and its copy described a Home mode-card layout that no
longer exists. Now shoots the Progress tab's Stats screen — a 2×3 grid of
per-difficulty Daily/Practice tiles (Completed / Best / Average), fully
populated via a dedicated store-only fixture so no tile shows the app's own
"—" empty-state placeholder. Copy below is Sudoku's; Minesweeper's own
`01-home` copy lives only in `scripts/build-ascspec-screenshots.py` (COPY →
`"minesweeper"` → `"01-home"`), matching the same accuracy constraint (no
ranking / Game Center / streak claim — only what the grid visibly shows).

| Locale | Headline | Subhead |
|---|---|---|
| en | Every solve, on the record. | Best and average times per difficulty, synced through iCloud. |
| zh-Hant | 每次解題，都被記錄。 | 各難度的最佳與平均時間，透過 iCloud 同步。 |
| zh-Hans | 每次解题，都被记录。 | 各难度的最佳与平均时间，通过 iCloud 同步。 |
| ja | 解いた記録が残る。 | 難易度ごとのベストと平均タイムをiCloudと同期。 |
| ko | 푼 기록이, 모두 남습니다. | 난이도별 최고 및 평균 시간을 iCloud와 동기화합니다. |
| es | Cada partida resuelta, registrada. | Mejores tiempos y promedios por dificultad, sincronizados con iCloud. |
| th | ทุกครั้งที่ไข ถูกบันทึกไว้ | เวลาที่ดีที่สุดและเฉลี่ยตามระดับ ซิงค์ผ่าน iCloud |

### Shot 2 — Daily Hub

| Locale | Headline | Subhead |
|---|---|---|
| en | Three puzzles. Every day. | Easy, medium, hard — the same world over. |
| zh-Hant | 每天三題。世界同題。 | 簡單、中等、困難，看你比別人快多少。 |
| ja | 毎日3問。世界中で同じ問題。 | やさしい・ふつう・むずかしい、タイムで世界と並ぶ。 |
| zh-Hans | 每天三题。世界同题。 | 简单、中等、困难，看你比别人快多少。 |
| es | Tres puzles. Cada día. | Fácil, medio, difícil — los mismos para todos. |
| th | สามปริศนา ทุกวัน | ง่าย ปานกลาง ยาก ชุดเดียวกันทั่วโลก |
| ko | 매일 세 문제. 전 세계 동일. | 쉬움, 보통, 어려움 — 시간이 곧 순위. |

### Shot 3 — Board mid-game

| Locale | Headline | Subhead |
|---|---|---|
| en | Notes the way you write them. | Live error highlighting. Twenty steps of undo. |
| zh-Hant | 筆記，跟你紙上寫法一樣。 | 即時錯誤提示，20 步 undo。 |
| ja | メモは紙のときと同じ作法で。 | 誤入力はその場で表示、20手まで戻せる。 |
| zh-Hans | 笔记，跟你纸上写法一样。 | 实时错误提示，20 步 undo。 |
| es | Notas como en el papel. | Detección de errores al instante. Veinte pasos de deshacer. |
| th | โน้ตเหมือนเขียนบนกระดาษ | เห็นผิดทันที ย้อนได้ยี่สิบขั้น |
| ko | 종이에 적던 그대로 메모. | 실시간 오류 표시, 스무 단계 되돌리기. |

### Shot 4 — Completion

| Locale | Headline | Subhead |
|---|---|---|
| en | Solved. | One scoring attempt per puzzle. Your time, ranked. |
| zh-Hant | 完成。 | 同題一次計分機會。你的時間，全球排名。 |
| ja | 解けた。 | 1問1スコア。あなたのタイムが世界に並ぶ。 |
| zh-Hans | 完成。 | 同题一次计分机会。你的时间，全球排名。 |
| es | Resuelto. | Una puntuación por puzle. Tu tiempo, en el ranking. |
| th | สำเร็จ | คิดคะแนนครั้งเดียวต่อปริศนา เวลาคุณบนกระดานอันดับ |
| ko | 완료. | 한 퍼즐당 한 번의 기록. 당신의 시간, 세계 순위에. |

### Shot 5 — Settings / Leaderboard depth

| Locale | Headline | Subhead |
|---|---|---|
| en | Seven languages. Zero tracking. | Game Center built in. No third-party SDKs. |
| zh-Hant | 七種語言。零追蹤。 | 內建 Game Center。沒有第三方 SDK。 |
| ja | 7言語対応、追跡ゼロ。 | Game Center対応。サードパーティSDKなし。 |
| zh-Hans | 七种语言。零追踪。 | 内置 Game Center。没有第三方 SDK。 |
| es | Siete idiomas. Cero seguimiento. | Game Center integrado. Sin SDK de terceros. |
| th | เจ็ดภาษา ไม่มีการติดตาม | รองรับ Game Center ไม่มี SDK ของบุคคลที่สาม |
| ko | 일곱 가지 언어. 추적은 0. | Game Center 내장. 서드파티 SDK 없음. |

## Capture conventions (for Phase 10 A5)

1. **Locale**: launch the Simulator/App with the target locale set via scheme argument (`-AppleLanguages "(ja)"` etc.). Verify Game Center titles also localized.
2. **Light mode only for v1**. Dark mode screenshots reserved for v1.x.
3. **Status bar**: use `xcrun simctl status_bar` to pin 9:41 AM, 100% battery, full signal, full wifi, no carrier text on all iPhone shots. iPad inherits same. Mac: hide menubar clutter via Stage Manager / clean desktop.
4. **Window chrome on Mac**: keep traffic-light buttons visible; window title bar shows just "Sudoku".
5. **Liquid Glass**: must be visible on Home and on any modal hero (Shot 1, Shot 4 if completion is modal). Confirmed render on iOS 26 / macOS 26 only.
6. **Personally identifiable data**: scrub any visible Game Center alias to `Player One` / `あなた` / `ผู้เล่น 1` etc. before publishing. Same for iCloud account display name on Mac.
7. **File naming**: `screenshots/<device-class>/<locale>/<NN>-<screen>.png`, e.g. `screenshots/iphone-6.7/ja/02-daily-hub.png`.
8. **Compression**: PNG with optimized palette; under 8 MB per ASC's upload cap.

## Verification checklist before ASC upload

- [ ] All 140 files present in the file tree.
- [ ] Each PNG matches the exact pixel dimensions for its class.
- [ ] No live Game Center alias, no iCloud email, no real APN token visible.
- [ ] Overlay copy is for the file's own locale (one wrong locale on one file is the easiest mistake — quick eyeball spot-check before upload).
- [ ] Mac Shot 5 sidebar shows full nav, not collapsed.
- [ ] iPad Shot 3 includes keyboard hint chip.

## Snapshot-sourced pipeline (#311)

Instead of hand-capturing from the built app, the store storyline is wired
from the committed snapshot-test baselines as a **single source of truth**.

- Mechanism: `mise-tasks/store/screenshots` (task `store:screenshots`) —
  `sync` / `list` / `clean`. `sync` creates relative **symlinks** under
  `docs/app-store/screenshots/<app>/<device>/<locale>/NN-screen.png` pointing
  at `Packages/.../__Snapshots__/`. Re-recording snapshots auto-refreshes the
  previews; no PNG is duplicated.
- Wired today (light mode, `en`/default-locale slots that have a baseline):
  Sudoku iPhone Home/Daily/Board/Completion/Settings + Mac Home/Board/Settings;
  Minesweeper iPhone Home/Daily/Board/Completion + Mac Home/Daily. Run
  `mise run store:screenshots list` for the live mapping and any gaps.

### Why these are PREVIEW-ONLY, not submission-ready

The snapshot PNGs are raw `NSHostingView` renders at the snapshot layout sizes,
**with an alpha channel** — they do **not** satisfy ASC's screenshot spec:

| Source | Baseline pixels | ASC 2026 requirement | Verdict |
|---|---|---|---|
| iPhone snapshot (393×852 @2x) | 786 × 1704, RGBA | iPhone 6.9": 1290×2796 / 1320×2868 — **exact, zero tolerance**, no alpha | ✗ size + alpha |
| Mac snapshot (900×600 @2x) | 1800 × 1200, RGBA | Mac: ≥ 1280×800, larger OK, no alpha | ✗ alpha (dimensions pass) |
| iPad 13" (#506) | 2064 × 2752, RGBA | iPad 13": 2048×2732 / 2064×2752 | ✗ alpha only (size already ASC-exact) |

ASC rejects the upload at the dimension/alpha check **before** review, so the
symlinked tree is for eyeballing the storyline from one source — it is **not**
an upload path.

### Remaining work to reach submission-ready (separate issue, under #236)

A **marketing-frame / upscale pass** consumes these baselines and emits
ASC-exact RGB (no-alpha) PNGs at the required device dimensions, applying the
overlay copy tabled above and (optionally) a device frame — that pass (dropping
the alpha channel; iPad's baseline dimensions are already ASC-exact, iPhone and
Mac still need the upscale) is what closes the gap to a real ASC upload. #311
delivers the wiring + this honest gap doc only.

## Store-screenshot redesign — Direction C + B (feat/store-screenshots-cb)

Replaces the caption-panel-over-flat-tint + centered-bezel marketing frame
(`scripts/build-ascspec-screenshots.py`) with:

- **Direction C** (Home / Daily / Settings): full-bleed brand-gradient ground
  in the app's OWN theme accent (Sudoku sage, Minesweeper steel-blue), the
  headline/subhead set directly into the gradient (no caption card), the
  device screenshot bleeding off the canvas's bottom edge, and a small
  app-icon badge top-left. The headline/subhead copy tabled above is
  UNCHANGED — it already fit the ≤5-word / ≤12-word constraint directly in
  color.
- **Direction B** (Board / Completion, layered on C): one feature-callout
  chip + leader line per slot, anchored in normalized screen-fraction
  coordinates (authored once per app/slot/device, reused across every
  locale — never per-locale positions).

### Direction B callout copy (NEW — not part of the locked table above;
pending native-speaker review, same as any new marketing string)

| Slot | en | zh-Hant | zh-Hans | ja | ko | es | th |
|---|---|---|---|---|---|---|---|
| Sudoku Board | Catches mistakes instantly | 即時抓出錯誤 | 实时揪出错误 | ミスをその場で検出 | 실수를 즉시 잡아냄 | Detecta errores al instante | จับข้อผิดพลาดได้ทันที |
| Sudoku Completion | Every solve, timed & ranked | 每次完成，計時排名 | 每次完成，计时排名 | 解くたびにタイム計測＆ランキング | 풀 때마다 시간 측정 및 순위 | Cada partida, cronometrada y clasificada | ทุกครั้งที่ไข จับเวลาและจัดอันดับ |
| MS Board | Flag suspected mines | 標記可疑地雷 | 标记可疑地雷 | 疑わしいマスに旗を立てる | 의심되는 칸에 깃발 표시 | Marca las minas sospechosas | ปักธงจุดที่สงสัยว่ามีระเบิด |
| MS Completion | Every board, timed & ranked | 每一局，計時排名 | 每一局，计时排名 | 毎回タイム計測＆ランキング | 매 판마다 시간 측정 및 순위 | Cada tablero, cronometrado y clasificado | ทุกกระดาน จับเวลาและจัดอันดับ |

### Localized UI — tried, backed out, tracked as #977

A per-locale-baseline variant of this pipeline was attempted (108 new
`*Localized` snapshot-test baselines, one set per locale per slot) so the
underlying app screenshot — not just the composited caption — would show
real translated UI. It didn't work: SwiftUI's `Text(LocalizedStringKey)`
resolves against `Bundle.main`, not `hostingView(locale:)`'s
`.environment(\.locale, ...)`, and a headless `swift test` host's
`Bundle.main` has no compiled `.lproj` resources — so every one of the 108
new baselines came out **byte-for-byte identical** to `en`, for every slot,
in both apps (verified via MD5, not eyeballed). Not a new bug — the 3
pre-existing `BoardViewTests` locale baselines already had it — but scaling
it to 108 files for zero signal wasn't worth landing, so that work was
reverted.

**What's real:** the composited overlay (headline/subhead/Direction-B
callout chips, from `build-ascspec-screenshots.py`'s own translation
tables, independent of SwiftUI's `Text` resolution) IS genuinely localized
per the tables above — every slot's *caption* is correct in all 7 locales.
The screenshot underneath it is not, for any string, in any locale, and
stays on the single `en`-sourced baseline the pipeline used before this
redesign. Root cause, byte-identical evidence, and two real fix paths (with
recommendation) are in #977 — read that before attempting a per-locale
baseline again.

### #967 — ja/th Daily-Hub vocabulary drift (fixed)

The Shot 2 ja/th subhead had hand-written difficulty terms that didn't match
the app's own shipped strings. Verified against
`App/Sudoku/Resources/Localizable.xcstrings` (`Easy`/`Medium`/`Hard` keys) —
ja: やさしい／ふつう／むずかしい (was 簡単・中級・上級); th: ปานกลาง for
Medium specifically (was the shortened กลาง; ง่าย/ยาก for Easy/Hard were
already correct). Table above updated to match; MS's own
Beginner/Intermediate/Expert scale (a different, already-correct set of
strings) is untouched.

### Baseline-fixture fullness audit (feat/store-screenshots-cb)

Every slot's baseline choice was re-audited against every sibling fixture in
its snapshot suite directory, picking the fullest state that's still an
honest representation of the screen (not a fabricated state) — the
generator's dead-space crop (`detect_content_bottom()`) fixes layout
whitespace, but an *empty-content* baseline (all-✕ Daily Hub, blank-slate
Home) still reads as flat regardless of cropping.

Swapped:
- **Sudoku Daily Hub (iPhone)**: `unfinished` → `allDone` — 🔥 7+ day streak
  strip, all three difficulties badged done, vs. seven grey ✕ and three
  `Best —` rows. Same canvas size, same crop behavior.
- **Minesweeper Daily Hub (iPhone)**: `compact` → `streak2` — adds a 2-day
  streak strip above the same Beginner/Intermediate/Expert rows (the
  Intermediate-done/Expert-Failed badges were already present in `compact`;
  the swap only adds real positive content, introduces nothing new negative).
- **Minesweeper Daily Hub (iPad) — round-2 code-review finding, resolved.**
  The only baseline that existed, `Daily-iPad-light-regular`, has
  `weekStrip == .unknown` (skeleton dots, no streak) AND Expert badged
  Failed — once `detect_content_bottom()` correctly crops the panel to its
  real (tiny) content, that combination composited as the worst-emptiness
  frame in the whole 126-PNG set (~7% of canvas height of panel, ~75% flat
  gradient below), and a failure badge has no business in store copy
  regardless of emptiness. No honest fuller iPad baseline existed to swap
  to, so one was recorded:
  `MinesweeperDailyHubSnapshotTests.snapshotDaily_iPad_light_streak` — same
  2-day streak strip as the iPhone `streak2` swap above, all three
  difficulties completed (Beginner/Intermediate/Expert), zero `isFailed`.
  Wired into `SLOTS` in place of `Daily-iPad-light-regular`. No CALLOUTS
  entry exists for `("minesweeper", "02-daily")` on either device, so no
  chip-geometry re-verification was needed.

Audited, kept as-is (no honest fuller candidate exists):
- **Sudoku, iPad, Daily Hub**: only one baseline exists (`unfinished`, no
  streak/all-done iPad variant recorded) — unlike the Minesweeper iPad case
  above, its content isn't the worst-emptiness frame in the set, so it
  wasn't escalated; still an open gap if a fuller iPad fixture is ever
  wanted.
- **Sudoku Board**: `inProgress` (half-filled grid + one red error cell) is
  the *message-correct* choice, not the emptiest — the Direction-B callout
  chip is anchored to that red error cell to sell "catches mistakes
  instantly". A fuller-looking `almostComplete` sibling exists but has
  no error highlighted, which would silently break the callout's claim.
  Kept `inProgress`.
- **Sudoku Completion**: `loaded` vs. sibling `noLeaderboard` differ only in
  `Mistakes: 2` vs. `Mistakes: 0` — same amount of visible content either
  way, not a fullness gap.
- **Minesweeper Completion (iPad)**: only `win-loaded` exists (no
  `win-reminder` iPad variant recorded); iPhone did swap (below).
- **Both apps, Home (iPhone)**: the `...WithAvatar` sibling is
  byte-identical to the default baseline in this crop (verified via
  `ImageChops.difference` — empty diff bbox), so it adds nothing. The
  `ResumeCandidate` sibling adds a "Resume Easy 3:21" pill but doesn't fix a
  dead-space defect (the default already fills 5 full menu rows) and risks
  muddying the "start your daily puzzles" headline with an abandoned-game
  signal — kept the default.
- **Both apps, iPad, Home / Board**: single baseline per slot, no sibling to
  compare.

Swapped separately (Minesweeper Completion, iPhone): `win-loaded` →
`win-reminder` — adds the real "Remind me when tomorrow's boards are ready"
notification-opt-in row below the Close button, filling space that was
previously blank canvas. The Close-button position is pixel-identical
between the two baselines, but the panel's own content-bottom is NOT (the
Direction-B callout's iPhone anchor targeted the Close button's bottom edge
at fraction 0.637 — with `win-reminder`'s added row, that fraction now
lands mid-text on "Remind me…" instead of past all content). Re-measured
via `detect_content_bottom()` against the new baseline (0.702) and updated
the anchor; see the CALLOUTS comment at `("minesweeper", "04-completion")`
in the script.

### Chip-width overflow — found by re-verifying every locale, not just `en`

Auditing every callout chip across all 7 locales (not just the `en` used to
verify the previous round) found MS iPad Board's chip overlapping the
grid's rightmost cells for ja/es/th — those translated labels (790–868px)
are wider than the ~772px of actual blank column space next to the grid,
which `en`'s shorter label (662px) happened to fit inside without ever
exercising the problem. `draw_callout_chip()` gained an optional
`max_width` that wraps an overflowing label onto a second line (word-split
for Latin/Hangul, falling back to a character split for CJK/Thai, which
carry no spaces at all — a space-only splitter left those scripts
completely unwrapped, since `str.split()` never breaks them). Wired via a
new `chip_max_w` key in the `CALLOUTS` dict, currently only on
`("minesweeper", "03-board")`'s `ipad-13` entry — the one placement proven
to need it; the other three callout slots' available space was re-verified
per-locale and left alone.

### Fullness audit, round 2 — widened to every suite directory, not just the slot's own

Round 1 only compared each baseline against siblings in its OWN
`__Snapshots__/<Suite>/` folder. Widening the search to every suite
directory in each package turned up better candidates that round 1's
narrower method structurally could not see.

Swapped:
- **Minesweeper Board (iPhone)**: `beginner-covered`
  (`MinesweeperBoardSnapshotTests` — every tile covered, status "Ready",
  timer 0:00) → `beginner-flagged` (`MinesweeperBoardRevealedSnapshotTests`
  — same suite that also holds `midReveal`). `flagged` is `midReveal`'s
  revealed number cells (colour-coded 1–8, status "Playing", timer 0:42)
  PLUS three flags placed on covered cells — a strict superset, and it
  depicts both verbs the headline promises ("Flag, reveal, solve.") in one
  frame, not just one. No iPad variant exists in that suite, so iPad keeps
  `beginner-covered` (documented gap, not silently left stale). iPhone's
  callout uses the default below-anchor drop (no `chip_at`, no grid to
  overlap) anchored to the flag-count header, which is identical UI chrome
  regardless of board content — re-verified at full res post-swap, still
  clear.

Reviewed and rejected (evaluated, not just skipped):
- **Minesweeper**, `MinesweeperBoardRevealedSnapshotTests/mineHit` and
  `MinesweeperBoardTerminalOverlaySnapshotTests/terminalOverlay`: both are
  loss states ("Boom", red mine glyph) — losing is not what we're selling.
- **Sudoku**, `BoardViewDigitFirstTests/armedDigit`: a number-pad selection
  highlight, no pencil notes, no error cell — no more relevant to Board's
  headline than the current `inProgress`.
- **Sudoku**, `BoardViewBannerTests`: ad-banner-reservation states, not a
  fuller version of anything in the current 5-shot storyline.
- Suites with no state relevant to any of the 5 slots (Sudoku:
  `PracticeHubViewTests`, `StatsViewTests`, `ToastTests`,
  `AudioSettingsSectionTests`, `ReminderSettingsSectionTests`,
  `SettingsIAPRowTests`, `BannerSlotDarkBandRegressionTests`,
  `BoardLoaderViewFailedExitTests`; Minesweeper: `MinesweeperStatsTests`,
  `MinesweeperBoardLoaderViewFailedExitTests`) — different screens
  entirely, or failure/edge states, not alternate happy-states of a slot
  already in use.

Escalated, then ruled on:

- **Sudoku Board — resolved, new baseline recorded.** `BoardViewPencilNotesTests/pencilNotes`
  shows REAL pencil/candidate notes rendered inside grid cells — the literal thing the headline
  "Notes the way you write them." promises, which the previous `inProgress` fixture did NOT
  actually show (its grid had zero pencil marks; what read as "notes-ish" there was only the
  number-pad's per-digit remaining-count subscript, not an in-grid note). But `pencilNotes` had
  no red error cell (confirmed: zero red pixels, scanned) for the subhead's "Live error
  highlighting" and the Direction-B chip "Catches mistakes instantly" to anchor to — swapping
  to it would have moved the unproven-claim problem, not fixed it (headline proven, subhead no
  longer proven). The ruling: neither existing fixture — record one that's both. Checked every
  `BoardView*` suite (`BoardViewBannerTests`, `BoardViewDigitFirstTests`,
  `BoardViewPencilNotesTests`, `BoardViewTests`) on both device classes for a fixture that
  already combined pencil notes with a red error cell first (scanned every PNG for red pixels;
  only the `InProgress` family has one, and none of those have notes) — none existed, so
  `BoardViewPencilNotesTests.snapshotPencilNotesWithError_iPhone_light` /
  `..._iPad_light` were recorded: `BoardViewTests.inProgressClues` reused byte-for-byte with the
  SAME userCells/errorCells/selection/elapsedSeconds as `snapshotInProgress_iPhone_light` /
  `..._iPad_light` (so the existing, already-reviewed Direction-B anchor coordinates for
  `("sudoku", "03-board")` keep working without recalculation — verified post-swap, they did),
  plus pencil notes added into three cells confirmed empty against the clue string and
  userCells. Wired into `SLOTS` in place of `BoardViewTests/inProgress`.
- **Sudoku Settings — rejected.** `SettingsViewAppStoreRowsTests` shows three more real rows
  than the current `purchased` fixture ("Invite Friends", "Share App", "Write a Review"), but
  its only recorded variant shows "Remove Ads **$2.99**" — the price changed to $0.99, so this
  isn't a marketing-tone judgment call, it's a wrong-price defect no amount of extra content
  buys off. Kept `purchased`. Filed #981 for the stale $2.99 baseline (and grepped every other
  `2.99` fixture in the repo for the same staleness — 5 total committed snapshots affected,
  Minesweeper unaffected); not fixed in this PR, out of scope.
- **Sudoku Completion — left as-is.** `CompletionOverlayScaffoldTests/playAgain` has a grey (not
  white) card, no `Mistakes:` row, and a "Play Again" button the current `CompletionViewTests`
  fixtures never show. Couldn't tell a real production surface our chosen fixture just doesn't
  exercise from an earlier/simpler test double for the shared overlay scaffold apart — not
  enough evidence to call it, and the downside of guessing wrong (shipping a test-double
  surface) outweighs the upside, so no further digging.

## macOS APP_DESKTOP arm + caption-accuracy sweep (#984)

Adds a THIRD device family, `mac` (2880×1800, APP_DESKTOP 16:10) — a
different layout from the iPhone/iPad frames above, not a scaled variant:
copy on the left, the app window (given Mac chrome — rounded corners +
traffic-light dots, since the baselines carry none of their own) vertically
centered on the right with the FULL window always visible (never bled off
the canvas — on a landscape Mac window that reads as a cropping mistake,
unlike the deliberate portrait bleed on iPhone/iPad). Slots: Sudoku
Board/Home/Settings, Minesweeper Board/Home/Stats (Stats has no iOS
counterpart — new copy, `("minesweeper", "06-stats")`). Details, exact
geometry, and per-locale verification live in the PR description, not
duplicated here.

A sweep triggered by that work (checking every slot's caption against what
its frame actually shows) found three defects, all fixed in the same pass:

- **`04-completion`, both apps, iPhone+iPad.** The subhead/callout claimed
  "ranked" / "ranked globally" — the completion popup's leaderboard-slice
  presenter was deleted in #698 (state has been `.hidden` since v2.6), so no
  frame has shown any ranking UI since then. The Shot 4 table above ("a
  3-row leaderboard slice underneath showing world ranking") is now also
  stale for the same reason — that leaderboard slice does not exist in the
  current app. Copy rewritten to name only what the card visibly shows
  (time, mistake count for Sudoku). Same fixture ALSO had real dead space
  ABOVE the card (a bottom-anchored card on a tall baseline canvas —
  `detect_content_bottom()` only ever trimmed the bottom); fixed by cropping
  the baseline on all 4 sides (`detect_content_bbox()`, a horizontal-axis
  extension of the same "any non-bg pixel" test) and never upscaling past
  1:1 — the card renders at its own native size, centered in the remaining
  space, when that's smaller than the slot.
- **Sudoku `05-settings`, iPhone+iPad+mac.** "Zero tracking." / "No
  third-party SDKs." directly contradicted `PrivacyInfo.xcprivacy`
  (`NSPrivacyTracking = true`, 8 declared AdMob tracking domains) and the
  linked GoogleMobileAds dependency — a false privacy claim live in App
  Store metadata. Rewritten to sell only what's true and visible in the
  frame: seven fully-localized languages, the ads-removal purchase, Game
  Center. No privacy/tracking claim at all now, by design — see the `en`
  string's own comment in `build-ascspec-screenshots.py` for the full
  reasoning.
- **Sudoku Settings fixture — stale version.** The rendered "Version" row
  showed "1.0.0" (the shipping app is 2.6.0) because
  `SettingsViewTests.makeSettingsHost()` never passed `appVersion` to
  `SettingsViewModel`, falling back to its placeholder default (the LIVE app
  is unaffected — `LiveRouteFactory` reads `CFBundleShortVersionString` from
  `Bundle.main` at runtime; only this synthetic test host had no bundle to
  read). Fixed by passing the shipping version explicitly, mirroring
  `App/Sudoku/Info.plist`. This will drift again at the next version bump —
  nothing currently keeps it in sync automatically; see the comment at that
  call site.

All new/rewritten strings from this sweep — COPY headlines/subheads AND the
CALLOUTS chip labels — carry the accuracy-fixed wording in all 7 locales
(approved `en` → `ai-translated-localization` pass, chip vocabulary anchored
to the same slot's COPY subhead). `PENDING_TRANSLATION_SLOTS` in
`build-ascspec-screenshots.py` is the hold-back gate for any future rewrite;
it is empty when, and only when, every table is fully translated.

## Portrait panel-fill + gap-consistency pass (#985, picks up the #995 icon drift)

The ASO audit's biggest conversion-lever finding: every portrait frame read
as "a small card floating in a big empty colour field." Measured with a
row-scan requiring a full-width run of panel-colour pixels across the
centre 60% of each row (immune to the corner app-icon badge and to white
headline text sitting in that same band — a naive row-brightness metric
gets fooled by both). `build_asc_image()` (portrait iPhone/iPad only;
`build_mac_asc_image()` untouched) changed on two axes:

- **`SCREEN_MARGIN` 0.045→0.030 of `asc_w`.** Frees ~3-4% more canvas
  width for the device screenshot at the SAME width-fill scale formula
  every slot already used — a legitimate "thinner decorative gutter, more
  real panel" gain, not a new kind of upscale.
- **crop_all_sides slots (`04-completion`, `02b-rank`) top-anchored
  instead of centered.** (`02b-rank` has since been removed with the
  native-Game-Center revert; `crop_all_sides` is now `{"04-completion"}`.
  The measurements below are the record of this pass as it ran.) The #984 completion-card crop already capped its
  own scale at `min(1.0, screen_w / content_w)` (never upscale past
  1:1) — correct and untouched. The bug was *positioning*: it centered the
  resulting small card in the leftover canvas below the copy block
  (`available_h = asc_h - SCREEN_TOP - CHIP_RESERVE`), which pushed a
  native-resolution card deep into the frame and measured as a 40-50%
  gap-above-panel — the single worst offender in the pre-#985 set (`04-completion`
  measured 50.0% gap / 15.2% panel on Sudoku iPhone). Anchoring at the
  same `SCREEN_TOP` every other slot already uses brought both slots'
  gap down to the same 20-30% band as everything else, with the leftover
  gradient landing below the card (where the callout chip already
  anchors off the card's own bottom edge) instead of above it.

**What did NOT change:** the width-fill scale for the non-crop_all_sides
slots (`01-home`/`02-daily`/`03-board`/`05-settings`) — that formula
predates this pass and already exceeds 1:1 on iPhone (baseline snapshots
are captured at a smaller point size than the 1290×2796 ASC canvas); this
pass did not push it further. Consequently `01-home`/`02-daily` stay
under the 60% aim on **iPad** specifically — measured directly
(`detect_content_bbox`, re-measured 2026-08 against the current baselines
after #1040 repointed `01-home` from the retired Today-tab Home to the
Progress-tab Stats screen): the iPad `02-daily` baseline's real content
spans ~96.9% of the baseline's own width at native resolution, and the new
iPad `01-home` (Stats) baseline spans ~90.0% (both apps render the same
grid layout here, so the number is identical for Sudoku and Minesweeper) —
so there is no unused width to zoom into without upscaling past 1:1. Per
this task's own constraint ("never upscale baseline art past 1:1 — shrink
and report the number, don't blow it up"), those two iPad slots are
reported short of 60% rather than forced. Re-extending the crop past
`detect_content_bottom()`'s content-bearing region (to synthetically pad
panel height with the app's own blank chrome) was considered and
rejected — that's the exact "large flat cream area inside the panel"
defect the original #984 pass already fixed once; doing it again would
have gamed the row-scan metric without fixing the underlying perception.

Before/after panel-fill (`en`, full table across every portrait slot/
device/app in the PR body) — the crop_all_sides gap fix alone dropped
`04-completion`/`02b-rank` (the latter since removed) gap-above from
40-53% to a consistent 20-30%
band matching every other slot; panel-fill on the width-fill slots moved
up 1-3 points from the margin trim (e.g. Sudoku iPhone `01-home`
47.1%→48.8%, `03-board` 76.6%→79.2%).
