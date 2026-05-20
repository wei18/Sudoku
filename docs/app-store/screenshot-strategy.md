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
