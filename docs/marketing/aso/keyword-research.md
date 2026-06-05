# Keyword Research — Sudoku & Minesweeper (DRAFT)

**Status:** ASO analysis draft. Nothing applied to live metadata. Ground every claim in
`docs/marketing/BRIEF.md` Verified Facts (privacy framing = Path B). Items not backed by a
Verified Fact are flagged `[UNVERIFIED — Leader confirm]`.

**Method note — no invented numbers.** I do not have access to App Store search-volume,
difficulty, or popularity data (no third-party ASO tool, no Search Ads Popularity export).
Every "high / medium / low" below is *qualitative reasoning* from category structure, term
genericness, and intent — not a measured figure. Where a real decision needs a number,
it is flagged for the Search Ads "popularity" check the user can run in App Store Connect.

**How Apple indexing works (the rules these sets are built on):**
- The app **name** and **subtitle** are both indexed for search, weighted higher than the
  keywords field. So the head term living in the name (`Sudoku`, `Minesweeper`) is already
  covered — *do not* repeat it in the keywords field; that wastes characters.
- The **keywords field** (100 chars, comma-separated, no spaces after commas) is indexed as
  a token bag. Apple auto-combines tokens, so `daily` + `puzzle` already covers
  "daily puzzle" — *do not* spend characters on multi-word phrases that the tokens already
  recombine into.
- Plurals/stems: Apple does light stemming but it is unreliable; `mine` vs `mines` can differ.
- The category (`Games > Puzzle` / `Board`) already associates the app with platform and
  genre, so generic `ipad` / `mac` tokens in the keywords field are **low-value** — Apple
  ranks by device implicitly. (Current listings spend ~7 chars each on `ipad,mac`.)

---

## SUDOKU

### Head term (already covered by name — do NOT put in keywords field)
- `sudoku` — lives in the app name (`Sudoku — …`). Highest-intent, highest-competition
  term in the category. Covered. Confirmed present in current name; correctly **absent**
  from the en keywords field already.

### Tier 1 — primary keywords field candidates (high relevance, worth the characters)
| Token | Intent | Competition (qualitative) | Why |
|---|---|---|---|
| `logic` | genre browser | high | core descriptor; recombines with `puzzle`, `brain` |
| `puzzle` | genre browser | high | broad funnel; recombines with `number`, `daily` |
| `brain` | "brain game / brain training" seeker | high | strong adjacent-genre pull |
| `number` | literal mechanic | medium | recombines into "number puzzle / number game" |
| `daily` | **our differentiator** (Verified Fact: daily leaderboards) | medium | recombines into "daily puzzle / daily sudoku"; few generic clones own a real daily loop |
| `offline` | "works without internet" seeker | medium | true — game is local-first (Verified: saves in iCloud Private DB, playable offline) |
| `notes` / `pencil` | feature seeker (pencil marks) | low-medium | matches a real feature (Verified: pencil notes up to 9 candidates) |
| `classic` | "classic sudoku" seeker | medium | recombines into "classic sudoku" |

### Tier 2 — long-tail / lower-competition (higher intent per impression)
- `sudoko` — **deliberate common misspelling** of sudoku. High-value, low-competition: many
  users mistype, few competitors index it. Already present in current en keywords — **keep**.
- `killer` — "killer sudoku" variant seeker. **CAUTION:** the app does not ship Killer
  Sudoku as a mode. Indexing `killer` invites a wrong-expectation install / 1-star review.
  `[UNVERIFIED — Leader confirm]` whether a Killer mode exists. The BRIEF lists only Daily +
  Practice modes, so I recommend **dropping `killer`** unless Leader confirms the mode.
- `solver` — "sudoku solver" seeker. **CAUTION:** the app is a *player*, not a *solver/scanner*
  tool. `solver` intent is mismatched (people want to photograph a newspaper and auto-solve).
  Recommend **dropping `solver`** — mismatched intent hurts conversion and invites refunds.
- `board` — generic; weak for sudoku (board games ≠ sudoku). Low value here; candidate to cut.

### zh-TW (繁體中文) candidates
Apple does **not** tokenise CJK on spaces, so for zh-Hant the keywords field should be
discrete comma-separated terms; Apple does limited internal segmentation. Favour the exact
multi-character compounds real users type.

| Token | Intent | Note |
|---|---|---|
| `數獨` | head term | **already in the zh name** (`數獨 — …`) → can be dropped from keywords to save chars |
| `sudoku` | romaji/EN spillover searchers on a zh storefront | keep — many TW users search the EN word |
| `益智` | "puzzle/brain" genre | high-relevance genre word |
| `邏輯` | "logic" | core descriptor |
| `推理` | "reasoning / deduction" | strong adjacent intent |
| `動腦` | "brain / think" | colloquial brain-game term |
| `九宮格` | literal "nine-grid" — the sudoku grid | **high-value, sudoku-specific**, lower competition |
| `填數字` | "fill in numbers" — describes the act | descriptive long-tail |
| `數字遊戲` | "number game" | broad funnel |
| `離線` | "offline" | true, differentiator |
| `每日` | "daily" — **our differentiator** | recombines into 每日數獨 |
| `筆記` | "notes" (pencil marks) | feature term |

**zh-TW cut candidates:** `數獨遊戲` (redundant — `數獨` in name + `遊戲` adds little),
`ipad`/`mac` (category covers device), `腦力` (overlaps `動腦`).

---

## MINESWEEPER

### Head term (covered by name)
- `minesweeper` — in the app name (`Minesweeper — Classic`). Covered; keep out of keywords.

### Tier 1 — primary keywords field candidates
| Token | Intent | Competition | Why |
|---|---|---|---|
| `mines` | core noun | high | recombines into "mine sweeper / mines game" |
| `mine` | singular stem | high | Apple stemming is unreliable; worth a separate token if room |
| `logic` | genre | high | core; shared brand thread with Sudoku |
| `puzzle` | genre | high | broad funnel |
| `classic` | "classic minesweeper" seeker | medium | true (Verified: three classic difficulties) |
| `flag` | mechanic seeker | low-medium | real mechanic (Verified: long-press / right-click to flag) |
| `bomb` | alt mental model ("bomb game") | medium | many users call mines "bombs" |
| `board` | genre | medium | relevant — secondary category is Board |
| `offline` | "works offline" | medium | true (local game) |
| `brain` | brain-game seeker | high | adjacent pull |

### Tier 2 — long-tail / lower-competition
- `sweeper` — partial-term that recombines; cheap, catches "mine sweeper" two-word searches.
- `sapper` — military term for mine-clearer; **niche, low-competition**, intent-aligned for
  the small set who use it. Already present — keep (cheap, no downside).
- `minesweeper` two-word `mine sweeper` — current en keywords spend chars on the literal
  phrase `mine sweeper` AND `sweeper`. Apple recombines `mine` + `sweeper` tokens, so the
  explicit two-word phrase is **redundant** — drop `mine sweeper`, keep the cheaper component
  tokens `mine` + `sweeper`. Saves ~13 chars.

### Caution — do NOT index these for Minesweeper
- `daily` is defensible (Verified Fact: per-difficulty **daily** leaderboards + a daily set
  of boards). Worth adding — it is a real, differentiating feature currently **absent** from
  the MS keywords field.
- **Never** `resume` / `save` / `continue` — there is **no saved-game / resume flow**
  (BRIEF Do-Not-Claim). Indexing these invites a feature-expectation mismatch.

### zh-TW (繁體中文) candidates
| Token | Intent | Note |
|---|---|---|
| `踩地雷` | head term | **in the zh name** → can drop from keywords |
| `掃雷` | the other common TW/CN name for the game | **must keep** — half of users search this, and it is NOT the app name |
| `minesweeper` / `sweeper` | EN spillover | keep one |
| `地雷` | "mine" | core noun |
| `邏輯` | "logic" | genre |
| `益智` | "puzzle" | genre |
| `經典` | "classic" | true |
| `炸彈` | "bomb" | alt mental model |
| `標記` | "flag/mark" | mechanic |
| `動腦` | brain | adjacent |
| `離線` | offline | true |
| `每日` | "daily" | **differentiator — Verified, currently missing from MS zh keywords** |

**zh-TW cut candidates:** `挖地雷` (low-relevance synonym, "dig mines"), `踩雷`
(metaphor for "stepping on a landmine" = making a mistake — **wrong intent**, attracts
non-game searches; recommend drop), `掃雷遊戲`/`踩地雷遊戲` (redundant with the base terms +
`遊戲`), `ipad`/`mac`.

---

## Cross-cutting recommendations
1. **Reclaim wasted characters.** Both apps spend ~7 en chars on `ipad,mac` and (Sudoku)
   risk mismatched-intent terms (`killer`, `solver`). Reinvest in `daily` (both apps) and
   true feature/synonym terms.
2. **`daily` is the single most under-used differentiator** in the keyword sets — it is a
   Verified Fact for both apps and few generic clones own a real daily loop. It belongs in
   the keywords field of Minesweeper (en + zh) where it is currently absent.
3. **Verify before indexing mode-implying terms.** `killer` (Sudoku) and `踩雷` (MS) carry
   wrong-expectation risk. See flags above.
4. **Search Ads popularity check (user-owned):** before finalising, the user can paste these
   token sets into App Store Connect → Search Ads → keyword tool to get Apple's own
   popularity scores and replace the qualitative tiers above with real numbers.

## Flags summary
- `[UNVERIFIED — Leader confirm]` Sudoku ships a **Killer Sudoku** mode (gates `killer`).
- `[UNVERIFIED — Leader confirm]` qualitative competition tiers — no measured volume data;
  replace with Search Ads popularity scores before locking.
