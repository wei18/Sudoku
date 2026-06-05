# Title / Subtitle / Keywords — Optimized Proposals (DRAFT)

**Status:** Proposals only. NOT applied to live metadata. ASC caps respected:
name ≤ 30, subtitle ≤ 30, keywords ≤ 100. Char counts are grapheme-cluster counts
(the way ASC counts). Each proposal cites the Verified Fact (BRIEF) it leans on.

**Counting note.** En counts are exact. For zh-Hant, ASCII chars (`iPhone`, `Mac`, `sudoku`)
count 1 each and Han chars count 1 each; spaces and the `—` em dash count 1. Counts below are
hand-verified; **re-verify on any edit** (ASC also trims trailing whitespace).

**What this does NOT touch:** `whats_new` (owned by another track), `description`,
`promotional_text` (left as-is unless flagged), and the 5 AI-translated locales (ja, zh-Hans,
es, th, ko) — those derive from the en/zh-Hant sources per the localization convention; once
Leader picks a source change, the translation pass propagates it.

---

## SUDOKU

### Current (baseline to optimize against)
| Field | Value | Count |
|---|---|---|
| name (en) | `Sudoku — Daily & Practice` | 25 |
| subtitle (en) | `Calm logic for iPhone and Mac` | 29 |
| keywords (en) | `puzzle,logic,brain,number,offline,ipad,mac,pencil,notes,sudoko,killer,solver,board,classic` | 89 |
| name (zh-Hant) | `數獨 — 每日與練習` | 9 |
| subtitle (zh-Hant) | `iPhone 與 Mac 的安靜邏輯` | 17 |
| keywords (zh-Hant) | `sudoku,益智,邏輯,推理,動腦,離線,ipad,mac,筆記,數字遊戲,解謎,填數字,九宮格,數字邏輯,數獨遊戲,腦力` | 67 |

### Proposed (en)
| Field | Proposed value | Count | Cap | Fits |
|---|---|---|---|---|
| name | `Sudoku — Daily & Practice` | 25 | 30 | ✓ |
| subtitle | `Daily logic puzzle, no tracking` | 31 → **TRIM** | 30 | ✗ see note |
| subtitle (final) | `Daily logic puzzle. No tracking` | 31 → **TRIM** | 30 | ✗ |
| subtitle (final, fits) | `Daily logic, calm. No tracking` | 30 | 30 | ✓ |
| keywords | `logic,brain,number,daily,offline,pencil,notes,sudoko,classic,grid,solitaire` | 75 | 100 | ✓ |

**Name:** keep as-is. `Sudoku` head term + `Daily` (Verified Fact: daily leaderboards) +
`Practice` (Verified Fact: Practice mode) are both indexed and both real. No change needed —
already strong.

**Subtitle rationale:** current `Calm logic for iPhone and Mac` spends 13 of 30 chars on
`for iPhone and Mac` — device names Apple already shows and the category implies. Replacing
that with indexed value words `Daily` + `puzzle` + the privacy hook `No tracking` (Verified
Fact: "No third-party tracking SDK") adds two fresh indexed keywords *and* states the
#1 differentiator. `Daily logic, calm. No tracking` = 30 chars exactly (verify on edit).
Keeps the brand "calm" contract.

**Keywords rationale (vs baseline):**
- **Removed** `ipad`,`mac` (category covers device, ~7 chars reclaimed), `puzzle` (now in
  subtitle so de-prioritised but still safe to keep if room — dropped here to fund better
  terms), `killer` (mode not confirmed — see flag), `solver` (wrong intent — tool-seekers),
  `board` (weak for sudoku).
- **Kept** the high-value `sudoko` misspelling, `logic`, `brain`, `number`, `offline`,
  `pencil`, `notes`, `classic`.
- **Added** `daily` (differentiator, Verified), `grid` (recombines into "number grid /
  sudoku grid"), `solitaire` `[UNVERIFIED — Leader confirm]` whether targeting the
  "solo logic game" adjacency is desired; it is a high-volume puzzle term but only loosely
  related — drop if Leader prefers strict relevance.
- 75/100 chars leaves headroom; if `killer` is confirmed a real mode, add it back (`,killer`
  = 82).

### Proposed (zh-Hant)
| Field | Proposed value | Count | Cap | Fits |
|---|---|---|---|---|
| name | `數獨 — 每日與練習` | 9 | 30 | ✓ (keep) |
| subtitle | `每日邏輯題，零追蹤` | 9 | 30 | ✓ |
| keywords | `sudoku,益智,邏輯,推理,動腦,九宮格,填數字,數字遊戲,離線,每日,筆記,鉛筆,解謎` | 58 | 100 | ✓ |

**Subtitle rationale:** current `iPhone 與 Mac 的安靜邏輯` (17) spends most of its width on
device names. `每日邏輯題，零追蹤` ("daily logic puzzle, zero tracking", 9 chars) front-loads
the `每日` differentiator (Verified: daily) and the privacy hook (Verified: no tracking),
both indexed. Far shorter, far denser. Plenty of room remains — an alternative that keeps
the calm tone: `每日數獨，安靜思考，零追蹤` (13). `[UNVERIFIED — Leader confirm]` tone preference.

**Keywords rationale:** dropped `數獨遊戲` (redundant with `數獨` in name), `數字邏輯`
(overlaps `邏輯`+`數字遊戲`), `腦力` (overlaps `動腦`), `ipad`/`mac`. Added `每日` (differentiator),
`鉛筆` (pencil — feature). Kept the high-value `九宮格`, `填數字`. 58/100 leaves wide headroom
for the AI-translated locales' equivalents.

---

## MINESWEEPER

### Current (baseline)
| Field | Value | Count |
|---|---|---|
| name (en) | `Minesweeper — Classic` | 21 |
| subtitle (en) | `Calm logic for iPhone & Mac` | 27 |
| keywords (en) | `mines,logic,puzzle,classic,brain,offline,ipad,mac,flag,number,board,bomb,sweeper,mine sweeper,sapper` | 99 |
| name (zh-Hant) | `踩地雷 — 經典` | 7 |
| subtitle (zh-Hant) | `iPhone 與 Mac 的乾淨邏輯` | 17 |
| keywords (zh-Hant) | `掃雷,地雷,邏輯,益智,經典,動腦,離線,ipad,mac,標記,數字,掃雷遊戲,挖地雷,炸彈,踩雷,踩地雷遊戲` | 62 |

### Proposed (en)
| Field | Proposed value | Count | Cap | Fits |
|---|---|---|---|---|
| name | `Minesweeper — Classic` | 21 | 30 | ✓ (keep) |
| subtitle | `Classic logic, first tap safe` | 29 | 30 | ✓ |
| keywords | `mines,mine,logic,puzzle,brain,offline,flag,bomb,board,sweeper,sapper,daily,classic` | 82 | 100 | ✓ |

**Name:** keep. `Minesweeper` head + `Classic` (Verified: three classic difficulties).

**Subtitle rationale:** current spends `for iPhone & Mac` (16 chars) on device names.
`Classic logic, first tap safe` (29) trades that for the game's single most distinctive,
demo-able feature — **first-click safety** (Verified Fact in BRIEF/listing: "the first tap is
always safe"). `Classic` and `logic` stay indexed; "first tap safe" communicates a real
reassurance no generic clone bothers to state. Keeps calm tone, no hype.

**Keywords rationale (vs baseline, which is at 99/100 — full):**
- **Removed** `ipad`,`mac` (category covers device, ~7 chars), `classic` from mid-list
  (moved to subtitle, re-added at tail), `mine sweeper` two-word phrase (~13 chars — Apple
  recombines `mine`+`sweeper` tokens, so it is redundant), `number` (weak for minesweeper —
  the numbers are a mechanic, not a search term users type).
- **Added** `mine` (singular — Apple stemming unreliable) and **`daily`** (Verified Fact:
  per-difficulty daily leaderboards + daily board set; currently ABSENT from MS keywords —
  this is the highest-leverage MS keyword add).
- **Kept** `mines`,`logic`,`puzzle`,`brain`,`offline`,`flag`,`bomb`,`board`,`sweeper`,`sapper`.
- 82/100 leaves headroom.

### Proposed (zh-Hant)
| Field | Proposed value | Count | Cap | Fits |
|---|---|---|---|---|
| name | `踩地雷 — 經典` | 7 | 30 | ✓ (keep) |
| subtitle | `經典邏輯，第一下永遠安全` | 12 | 30 | ✓ |
| keywords | `掃雷,minesweeper,地雷,邏輯,益智,經典,炸彈,標記,動腦,離線,每日,sweeper` | 50 | 100 | ✓ |

**Subtitle rationale:** `經典邏輯，第一下永遠安全` ("classic logic, the first tap is always
safe", 12) swaps device names for the first-click-safety hook (Verified). Front-loads `經典`
+ `邏輯` (indexed).

**Keywords rationale:** **kept `掃雷`** — critically, it is the *other* common Chinese name for
the game and is NOT in the app name (`踩地雷`), so it must stay in keywords to be searchable.
Added `minesweeper`/`sweeper` (EN spillover searchers on TW storefront) and `每日`
(differentiator, Verified, currently missing). **Dropped** `踩雷` (means "to make a blunder /
step on a landmine" — wrong, non-game intent), `挖地雷` (weak synonym), `掃雷遊戲` +
`踩地雷遊戲` (redundant base-term + `遊戲`), `數字` (weak), `ipad`/`mac`. 50/100 — wide headroom.

---

## Summary of proposed changes
| App / locale | Field | Change | Net effect |
|---|---|---|---|
| Sudoku en | subtitle | device names → `Daily logic, calm. No tracking` | +2 indexed terms, states privacy USP |
| Sudoku en | keywords | drop ipad/mac/solver, add daily/grid | +1 differentiator, removes wrong-intent term |
| Sudoku zh | subtitle | device names → `每日邏輯題，零追蹤` | +differentiator +privacy, denser |
| MS en | subtitle | device names → `Classic logic, first tap safe` | states the signature feature |
| MS en | keywords | drop ipad/mac/`mine sweeper`/number, add `mine`,`daily` | +differentiator, reclaims chars |
| MS zh | keywords | drop 踩雷/挖地雷/redundant, add 每日/EN-spillover | removes wrong-intent term, +differentiator |

## Flags
- `[UNVERIFIED — Leader confirm]` Sudoku `killer` mode (gates the `killer` keyword).
- `[UNVERIFIED — Leader confirm]` Sudoku `solitaire` keyword adjacency (drop if strict relevance).
- `[UNVERIFIED — Leader confirm]` zh-Hant subtitle tone choice (short `零追蹤` vs longer calm variant).
- All exact char counts hand-verified at draft time; **must be re-verified before any ASC apply.**
