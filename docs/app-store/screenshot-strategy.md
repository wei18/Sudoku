# App Store screenshot strategy

Capture plan for Sudoku v1 App Store storefront. This file specifies **what to shoot, in what order, at what dimensions, with what overlay text** for every supported device class and locale. Actual PNG capture is Phase 10 A5 (Xcode Simulator + Liquid Glass enabled).

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
| 2 | Daily Hub (3 difficulties) | The daily ritual hook. One difficulty shown as already completed today to imply progress, not pressure. | Three difficulty rows, one with `✓ 04:32` style timestamp |
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

### Shot 1 — Home / Entry point

| Locale | Headline | Subhead |
|---|---|---|
| en | Calm logic, every day. | Two modes, one focused place to think. |
| zh-Hant | 每天，一場安靜的推理。 | 兩種模式，一個專注思考的地方。 |
| ja | 毎日、静かな論理を。 | ふたつのモード、ひとつの集中する場所。 |
| zh-Hans | 每天，一场安静的推理。 | 两种模式，一个专注思考的地方。 |
| es | Lógica tranquila, cada día. | Dos modos, un solo lugar para pensar. |
| th | ตรรกะเงียบๆ ทุกวัน | สองโหมด หนึ่งพื้นที่สำหรับคิด |
| ko | 매일, 조용한 논리. | 두 가지 모드, 집중할 수 있는 한 곳. |

### Shot 2 — Daily Hub

| Locale | Headline | Subhead |
|---|---|---|
| en | Three puzzles. Every day. | Easy, medium, hard — the same world over. |
| zh-Hant | 每天三題。世界同題。 | 簡單、中等、困難，看你比別人快多少。 |
| ja | 毎日3問。世界中で同じ問題。 | 簡単・中級・上級、タイムで世界と並ぶ。 |
| zh-Hans | 每天三题。世界同题。 | 简单、中等、困难，看你比别人快多少。 |
| es | Tres puzles. Cada día. | Fácil, medio, difícil — los mismos para todos. |
| th | สามปริศนา ทุกวัน | ง่าย กลาง ยาก ชุดเดียวกันทั่วโลก |
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

### Localized UI — per-locale baselines, and a known limitation

Every slot × device now sources a **per-locale baseline** (`en` uses the
original unparameterized snapshot; the other 6 locales come from new
`*Localized` parameterized `@Test(arguments:)` snapshot tests added to
`SudokuUITests` / `MinesweeperUITests`, reusing the existing
`hostingView(locale:)` injection that 3 pre-existing regression baselines
already used — no new capture mechanism). Cost: 108 new baseline PNGs (60
Sudoku + 48 MS, self-recording via the suites' existing `.missing` record
mode) across 9 test files + 2 `SnapshotConfig.swift` additions.

**Known limitation (pre-existing, not introduced by this change — but bigger
than it first looks):** `hostingView(locale:)` only sets
`.environment(\.locale, ...)` on the rendered subtree. SwiftUI's
`Text(LocalizedStringKey)` resolves its string table against `Bundle.main`
(the actual OS/device language), not the `\.locale` environment value — so
inside a headless `swift test` host, whose `Bundle.main` is the xctest
runner (no compiled `.lproj` resources at all), **no in-screen string
localizes, full stop.** This isn't limited to difficulty labels or weekday
letters: byte-for-byte comparison of the 108 new baselines confirms every
locale's raw snapshot (`en`, `zh-Hant`, `zh-Hans`, `ja`, `ko`, `es`, `th`)
is **pixel-identical** to the `en` baseline for every slot in both apps —
Home, Board, Completion, Settings, Daily all included. This was already
true of the 3 pre-existing `*_ja`/`*_ko`/`*_zhTW` regression baselines in
`BoardViewTests` before this PR (verified: `Board-iPhone-dark-empty-ja.png`
also shows "Easy" in English), so it's not a regression — but the 108 new
baselines don't capture any new *content*, only new *file names* for the
compositor to hang a locale-correct caption on. The MARKETING OVERLAY
(headline/subhead/callout chips, composited by
`build-ascspec-screenshots.py` from its own translation tables, independent
of SwiftUI's Text resolution) is genuinely localized per the tables above —
that's real. The underlying app screenshot is not, for any string,
anywhere. Fixing this for real needs the app's `Text` call sites to accept
an explicitly-injected per-locale `Bundle` (loading each `.lproj` as its own
`Bundle` and threading it through `.environment(\.locale)` alongside an
explicit `bundle:` argument, or an equivalent DI seam) — out of scope here,
flagged for a follow-up issue rather than silently accepted or downplayed.
