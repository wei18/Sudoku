# App Store Copy Review — Sudoku & Minesweeper (#236)

> ASO + conversion + localization review of the live App Store Connect listing
> copy for both apps, across all 7 locales each. Copy is **already live** (pushed
> via ASC API). This report recommends changes for the Leader to apply + re-push;
> the `listing.yaml` files were **not** edited.
>
> Reviewer: App Store Optimizer · Date: 2026-06-04 · Scope: `name`, `subtitle`,
> `promotional_text`, `description` (above-the-fold), `keywords`.
>
> Char counts were measured programmatically against ASC caps (name 30, subtitle
> 30, keywords 100, promo 170, description 4000). A trailing block-scalar newline
> is not counted by ASC and was excluded.

---

## Executive summary

| App | Overall verdict | Headline issues |
|-----|-----------------|-----------------|
| **Sudoku** | **Strong (A−).** Voice is consistently calm and native across all 7 locales. Conversion copy hooks fast; privacy + cross-platform + no-ads framing all land above the fold. Main gaps are ASO keyword waste (self-duplication with the indexed `name`) and zero headroom on several subtitles/promos. | P2 keyword self-dupes (`daily`/`sudoku` etc. already in name); P2 unused keyword budget in CJK locales; P3 subtitle headroom. |
| **Minesweeper** | **Good but one compliance risk (B+).** Same calm voice, clean translations. **One P1: the `description` claims "Resume any time — saves are automatic," which the v1 review doc explicitly says to OMIT until the save-flow lands** — a factual-accuracy / App-Review risk across all 7 locales. Plus a cross-app es inconsistency from the recent hand-edit, and large unused keyword budget. | **P1 resume claim vs. review-doc gating**; P2 es `rastreo`/`seguimiento` cross-app inconsistency; P2 keyword budget; P3 `daily set of boards` borderline phrasing. |

**Translation naturalness:** all 14 listings read as native, not MT-stiff. The two flagged hand-edits both pass (details in the Translation section). No locale needs a from-scratch rewrite.

**Character-limit headroom:** nothing is over cap. But these are at/near the ceiling and have **no room for future edits** — flagged P3 so the Leader knows a one-word change will overflow:

| App | Locale | Field | Count |
|-----|--------|-------|-------|
| Sudoku | en | subtitle | 29/30 |
| Sudoku | es | subtitle | 29/30 |
| Sudoku | es | promotional_text | 168/170 |
| Sudoku | th | subtitle | 29/30 |
| Minesweeper | en | subtitle | **30/30** (exactly full) |
| Minesweeper | es | subtitle | 29/30 |
| Minesweeper | th | promotional_text | 168/170 |

---

## Prioritized action table

Priority key: **P1** = must-fix before next push (accuracy/compliance) · **P2** = should-fix (measurable ASO/consistency win) · **P3** = nice-to-have (polish/headroom).

| # | Pri | App | Locale | Field | Current | Issue | Suggested rewrite (within limits) |
|---|-----|-----|--------|-------|---------|-------|-----------------------------------|
| 1 | **P1** | MS | **all 7** | description | `• Resume any time — saves are automatic.` | The MS v1 review doc (`review/minesweeper-v1.md` §Pending-feature flags) says save-flow is a follow-up and to **"omit 'resume' until the save flow lands."** Claiming automatic-save resume is a factual-accuracy risk if the flow isn't wired in the submitted build. | **Remove the "Resume any time" bullet** from the "What's inside" list in all 7 locales (and the matching line in `whats_new` if present), OR confirm save-flow is wired in the submission build before keeping it. If kept, the claim must be true. (Leader: verify against `MinesweeperAppComposition/Live.swift` first.) |
| 2 | **P2** | MS | es-ES | promotional_text | `Sin rastreo salvo el banner opcional` | The hand-edit swapped `seguimiento`→`rastreo` to fit length. It reads naturally, **but Sudoku es still uses `sin seguimiento`** (promo line) — so the two apps now disagree on the tracking term. Apple's own es-ES ATT wording uses *seguimiento*. | For cross-app + Apple-consistency, prefer `seguimiento`. Length-safe rewrite (≤170): `El clásico de lógica, en calma. Principiante, Intermedio, Experto. El primer toque siempre es seguro. Sin seguimiento más allá del banner opcional, que quitas con una compra.` (= 169/170). If 169 is too tight for comfort, keep `rastreo` but **also** change Sudoku es to `rastreo` so both apps match — pick one term globally. |
| 3 | **P2** | Sudoku | en | keywords | `sudoku,daily,puzzle,logic,brain,number,offline,ipad,mac,no ads,pencil,notes` (75/100) | `sudoku` and `daily` are **already in the `name`** ("Sudoku — Daily & Practice"); ASC indexes the name, so both are wasted keyword chars. 25 chars of budget unused. | Drop `sudoku,daily`; spend the freed budget on high-intent terms: `puzzle,logic,brain,number,offline,ipad,mac,no ads,pencil,notes,sudoko,killer,solver,board` (sudoko = common misspelling traffic; killer/solver/board = adjacent search demand). Keep ≤100. |
| 4 | **P2** | Sudoku | es | keywords | `sudoku,diario,puzzle,logica,cerebro,numeros,offline,ipad,mac,sin anuncios,lapiz,notas` (85/100) | `sudoku` + `diario` both in the `name` ("Sudoku — Diario y Práctica") → wasted. `puzzle` is English; the es-relevant term is `puzle`/`rompecabezas`. | `puzle,logica,cerebro,numeros,offline,ipad,mac,sin anuncios,lapiz,notas,rompecabezas,sudoko,solver` (drop name-dupes, fix `puzzle`→`puzle`, add `rompecabezas` + misspell). Keep ≤100. |
| 5 | **P2** | MS | en | keywords | `minesweeper,mines,logic,puzzle,classic,brain,offline,ipad,mac,flag,number,board` (79/100) | `minesweeper` is in the `name` → wasted. Budget under-used (21 chars free) for a competitive category. | `mines,logic,puzzle,classic,brain,offline,ipad,mac,flag,number,board,bomb,sweeper,mine sweeper,sapper` — adds high-volume variants (`bomb`, `sweeper`, two-word `mine sweeper`, `sapper`). Keep ≤100. |
| 6 | **P2** | MS | es-ES | keywords | `buscaminas,minas,logica,puzzle,clasico,mente,sin conexion,ipad,mac,bandera,numero` (81/100) | `buscaminas` is in the `name` → wasted. `puzzle` is English (es term is `puzle`). | `minas,logica,puzle,clasico,mente,sin conexion,ipad,mac,bandera,numero,bomba,campo minado,buscamin` — drop name-dupe, fix `puzzle`, add `bomba` + `campo minado` (common alt name). Keep ≤100. |
| 7 | **P2** | Both | ja / ko / zh-Hans / zh-Hant | keywords | e.g. SU/zh-Hans 43/100, MS/zh-Hans 35/100, SU/ja 48/100, MS/ko 40/100 | **Half the keyword budget is unused** in every CJK locale — the single biggest ASO miss. CJK has no inter-word spaces, so more discrete terms fit. | Fill toward ~90/100 with locale-native long-tail. Examples — SU/zh-Hans add `数字游戏,解谜,填数字,九宫格,数独游戏`; SU/zh-Hant add `數字遊戲,解謎,填數字,九宮格`; SU/ja add `ナンプレ,数字パズル,脳トレゲーム,数独ゲーム`; MS/ja add `マインスイーパー,爆弾,マイン,パズルゲーム`; MS/ko add `지뢰,논리퍼즐,클래식게임,마인스위퍼`; MS/zh add `踩地雷,挖地雷,扫雷游戏`. (`ナンプレ` is the dominant JP search term for Sudoku — currently missing.) |
| 8 | **P3** | MS | en | subtitle | `Clean logic for iPhone and Mac` (30/30) | Exactly at cap — **zero room**; any future tweak overflows. Also "Clean" is the weakest of the brand adjectives vs. Sudoku's "Calm." | Optional: `Calm logic for iPhone & Mac` (27/30) — mirrors Sudoku's adjective for brand cohesion and buys 3 chars of headroom. Only if the Calm/Clean split wasn't a deliberate differentiation choice. |
| 9 | **P3** | MS | en/es/etc | description | `A daily set of boards to return to.` | Borderline vs. review-doc guidance ("describe as 'a daily set of boards' at most; no scoring claim"). Current wording is compliant, but "to return to" leans toward a persistence/resume implication that pairs with the P1 resume bullet. | If removing the resume bullet (#1), soften to `A daily set of boards to play.` so nothing implies cross-session continuation. |
| 10 | **P3** | Sudoku | th | subtitle | `ตรรกะเงียบๆ บน iPhone และ Mac` (29/30) | At cap; fine as-is. `เงียบๆ` (informal reduplication) is slightly colloquial for a calm/premium tone but reads natural to Thai users. | No change required. If a more composed register is wanted: `ตรรกะอันเงียบสงบบน iPhone และ Mac` — but this exceeds 30; keep current. |

---

## Per-locale translation naturalness notes

### Spanish (es) — both apps
- **Sudoku subtitle `Lógica serena en iPhone y Mac` (hand-edit, 29/30):** **Confirmed natural.** `serena` (serene/calm) is an excellent register match for the brand's quiet voice — arguably better than a literal `tranquila`/`calmada`. Native-sounding, no change needed.
- **MS promo `seguimiento`→`rastreo` (hand-edit):** **Reads naturally** — `rastreo` is correct, common Spanish for tracking and is actually punchier/shorter. The only caveat is *consistency*: Sudoku es uses `seguimiento`, Apple's own es-ES ATT UI uses `seguimiento`. Both words are native and correct; the recommendation (item #2) is purely to make the two apps agree on one term, leaning `seguimiento` for Apple-alignment.
- General es quality: high. `puzles`/`puzle` used in body copy (good), but `puzzle` (English) leaks into the **keywords** of both apps — fix in items #4/#6. `rompecabezas` (the fully-native term) is absent and worth adding.

### Japanese (ja) — both apps
- Natural, well-registered. `にぎやかさは要らない` / `雑音のためではなく` are idiomatic, not literal. Difficulty names (簡単・中級・上級) consistent. MS `初級・中級・上級` consistent.
- ASO gap, not translation: the dominant JP search term for Sudoku is **ナンプレ** (numbers-place), missing from keywords — high-value add (item #7). MS could add the long-vowel variant `マインスイーパー` (the name uses the short `マインスイーパ`; both spellings are searched).

### Korean (ko) — both apps
- The polite-informal `-요`/`-어요` ending is consistent and friendly without being childish — good fit. `소음이 아니라 사고를 위해` is natural. Difficulty names consistent (쉬움/보통/어려움 for Sudoku; 초급/중급/전문가 for MS — correctly different domains).
- Minor: `전문가` (Expert) vs Sudoku's `어려움` (Hard) — intentional and correct (MS uses classic Minesweeper tier names). No issue.
- ASO: budget under-used; add `지뢰,논리퍼즐` etc.

### Thai (th) — both apps
- Reads natural. Sudoku name `ซูโดกุ` and MS `เก็บกู้ระเบิด` are both the conventional Thai renderings. `พูดกันตรง ๆ` (privacy header) is nicely colloquial-warm.
- `เงียบๆ` in the Sudoku subtitle is slightly informal but acceptable (item #10).
- th promo for MS is 168/170 — watch headroom.

### Chinese Simplified (zh-Hans) & Traditional (zh-Hant) — both apps
- Both excellent and correctly differentiated (`扫雷`/`踩地雷` is the right S/T split for Minesweeper; `数独`/`數獨` for Sudoku). `留给思考，不留给嘈杂` / `不留給雜訊` is a clean, idiomatic parallel structure.
- Mixed-script choices (`UTC`, `seed`, `Daily`/`Practice`, `analytics`, `build`) are deliberate and read fine to a tech-comfortable CN/TW audience, but note **inconsistency**: some English tech words are left in (`analytics`, `seed`, `build`, `reset` in zh-Hant body) while others are translated. Acceptable for the target audience; flagging only as a consistency observation, not a defect.
- **Biggest opportunity is ASO, not translation** — CJK keyword fields are the most under-filled (35–48/100). See item #7.

---

## Cross-app & cross-locale consistency notes

1. **Subtitle adjective split:** Sudoku = "Calm/serena/静か/조용한/安静/安靜/เงียบ" logic; Minesweeper = "Clean/limpia/静か(ja same)/깔끔한/干净/乾淨/สะอาด" logic. Mostly a deliberate, well-executed differentiation. **Exception:** ja subtitle is **identical** for both apps (`iPhoneとMacの静かな論理`) — Sudoku's "calm" word was reused for MS instead of a "clean" equivalent. Minor; if differentiation is wanted in ja, MS could use `iPhoneとMacの澄んだ論理` ("clear/clean logic"). Low priority.
2. **Tracking term (es):** `seguimiento` (Sudoku) vs `rastreo` (MS) — pick one (item #2).
3. **IAP / no-ads framing differs by design:** Sudoku promo says "No ads" (it had a 7-day grace + banner); MS says "No tracking beyond the optional banner — remove it with one purchase." The MS framing is more accurate to the shipped monetization (banner + Remove Ads IAP) and is the better template. **Sudoku's promo "No ads, no tracking" may itself be inaccurate** if Sudoku v2.5 ships the banner — worth a separate check (the Sudoku review doc describes a live banner + Remove Ads IAP, so "No ads" in the Sudoku promo looks like stale v1.0 copy). Flagging as a **possible P1 for Sudoku** pending Leader confirmation of whether the live Sudoku build shows a banner.
4. **`whats_new` is stale (both apps, known):** the Sudoku review doc already tracks "v2.5 `whats_new` refresh" as a follow-up; the v1.0 release text is still in all 7 Sudoku files. Out of scope here but noted so it isn't lost.

> **Added P1 candidate (consistency item #3):** if the live Sudoku build shows a banner ad before the Remove-Ads IAP, the Sudoku promo line **"No ads, no tracking, no accounts beyond your own iCloud"** is inaccurate and should mirror the MS framing, e.g. `Three new Daily puzzles every day at midnight UTC. Pick up where you left off across iPhone and Mac. No tracking; an optional banner you can remove with one purchase.` (≤170 — verify count on apply). Leader to confirm banner state before deciding.

---

## Handoff

- **No `listing.yaml` files were modified.** All suggestions above are ready-to-apply strings; the Leader should apply the accepted ones and re-push via the ASC API.
- **Suggested apply order:** P1 first (MS resume claim #1; Sudoku "No ads" accuracy pending banner confirmation), then P2 keyword + es-consistency batch (#2–#7), then P3 polish.
- **Re-measure on apply:** items touching es/th promos and MS/en subtitle are near the cap — re-run a char count after editing before pushing.

— App Store Optimizer
