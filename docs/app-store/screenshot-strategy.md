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

Audited, kept as-is (no honest fuller candidate exists):
- **Both apps, iPad, Daily Hub**: only one baseline exists per app (no
  streak/all-done iPad variant recorded).
- **Sudoku Board**: `inProgress` (half-filled grid + one red error cell) is
  the *message-correct* choice, not the emptiest — the Direction-B callout
  chip is anchored to that red error cell to sell "catches mistakes
  instantly" (#979). A fuller-looking `almostComplete` sibling exists but has
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
verify the previous round, #979) found MS iPad Board's chip overlapping the
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
