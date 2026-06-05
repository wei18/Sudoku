# Competitor Gap & Differentiation (DRAFT)

**Status:** Positioning analysis draft. Differentiators below are restricted to BRIEF
Verified Facts. No competitor names, download counts, or rankings are asserted as fact —
the App Store Sudoku/Minesweeper categories are described by their *well-known generic
pattern*, which is observable from any storefront browse, not from private data.

**Method note.** I am characterising the *typical generic clone* archetype that dominates
both categories (a pattern any user sees browsing "sudoku" / "minesweeper"), not a specific
named app. No invented metrics. Where a specific competitive claim would need data I do not
have, it is flagged.

---

## The generic Sudoku/Minesweeper listing archetype (what we position against)

The free-puzzle category is crowded with near-identical listings that share a recognisable
shape:

1. **Hype-stacked copy.** Names and subtitles packed with superlatives ("Best", "#1",
   "Brain Booster", emoji). Screenshots shout "MILLIONS OF PLAYERS!" with confetti.
2. **Ad-heavy, interstitial-driven.** Monetised through frequent full-screen interstitials
   and rewarded video, often with no clean removal path or a subscription paywall.
3. **Aggressive tracking.** SDKs for attribution, analytics, and ad networks; an App Privacy
   "nutrition label" listing data linked to the user for tracking.
4. **Phone-first, Catalyst-or-absent on Mac.** Mac presence is usually an iPad app resized,
   or nonexistent. No real keyboard/menu/window behaviour.
5. **No genuine daily loop.** "Daily challenge" is often a cosmetic re-skin of the same RNG,
   not a shared, ranked, resetting event.
6. **English-centric.** Thin or machine-garbled localization; Game Center titles untranslated.

This archetype defines the gaps we can own.

---

## Our differentiators (each backed by a Verified Fact)

| # | Differentiator | Verified Fact (BRIEF) | Generic-clone gap |
|---|---|---|---|
| D1 | **Privacy-first, no third-party tracking** | "No third-party tracking SDK. Apple-only: App Store Analytics + MetricKit + Game Center. PrivacyInfo.xcprivacy shipped" | Clones track aggressively; our App Privacy label is near-empty. A concrete, checkable claim. |
| D2 | **iCloud sync of your saves (Sudoku)** | "Full game saves + records sync via CloudKit" (Sudoku) | Most free clones keep progress device-local or behind an account. Ours syncs via *your own* iCloud Private DB — we can't see it. |
| D3 | **Real, ranked Daily** | "Leaderboards + **daily** leaderboards, live" (Sudoku); "per-difficulty **daily** leaderboards, live" (MS) | Same three puzzles for everyone, resetting at UTC 00:00, with Game Center ranking. A genuine shared event, not a re-skinned RNG. |
| D4 | **True Mac-native (not Catalyst)** | iOS + macOS (SwiftUI), and listing copy: "a real SwiftUI Mac app — not iPad-on-Mac, not Catalyst" | Clones are phone apps; ours has real window resizing, keyboard nav, native menus. |
| D5 | **Calm, no-hype design** | Brand voice contract: "calm, precise, understated… sage-and-warm-paper visuals" | Direct contrast to confetti/superlative clones. The whole listing *is* the differentiator. |
| D6 | **Honest, removable monetization (Sudoku)** | "Free; removable banner ad + one-time Remove Ads IAP" | A single, non-consumable, Family-Sharing Remove Ads — no interstitials, no subscription. |
| D7 | **Genuine 7-locale localization** | "7 locales (zh-TW, en, ja, zh-CN, es, th, ko)" incl. Game Center titles + store metadata | Clones are English-centric; ours is hand-source + reviewed-translation across 7 markets. |

### Accuracy guards (do NOT cross these — BRIEF Do-Not-Claim)
- **Sudoku is NOT "ad-free."** It ships a removable banner. Frame as "free, with an optional
  one-tap Remove Ads" — D6. Never "no ads / ad-free" for Sudoku.
- **Minesweeper does NOT sync saved games.** Only MonetizationState syncs (Verified). So D2
  applies to **Sudoku only**. For Minesweeper, the iCloud claim is limited to "your Remove
  Ads purchase follows you" — do not say "syncs your games" for MS.
- **Minesweeper has NO resume / saved-game flow.** Do not position continuity/"pick up where
  you left off" for MS.
- No award/userbase/ranking numbers anywhere — we have none (BRIEF).

---

## Per-app positioning

### Sudoku — "The calm, private daily Sudoku that's real on Mac."
Lead differentiators: **D1 (privacy) + D3 (real Daily) + D2 (iCloud continuity) + D4 (Mac)**.
This is the strongest stack — all four are simultaneously true and rare in the category.
The current listing already does much of this well; the ASO opportunity is to surface
**privacy** and **Daily** *earlier* (subtitle/keywords) where browsers and search see them,
not buried in the description.

### Minesweeper — "Classic Minesweeper, calm and private — first tap always safe."
Lead differentiators: **D5 (calm) + D1 (privacy) + first-click-safety + D4 (Mac) + D3 (daily
leaderboards)**. First-click-safety (Verified in listing) is the most demo-able single
feature and few clones state it. **Do not** lean on continuity (no resume) or game-sync (only
monetization syncs). Daily is currently under-surfaced for MS — both a keyword and a
screenshot opportunity.

---

## Keyword-gap opportunities (cross-ref `keyword-research.md`)
- **`daily`** — a Verified differentiator (D3) for BOTH apps, currently **absent** from the
  Minesweeper keywords field and under-weighted in Sudoku's. Highest-leverage gap to close.
- **`offline` / privacy framing** — generic clones can't honestly claim it; we can (D1).
- **Mac-native** — not a search term users type often, so this is a *description/screenshot*
  differentiator (D4), not a keyword play. Keep it in long copy, not keywords.

## Flags
- `[UNVERIFIED — Leader confirm]` any *named* competitor comparison — this doc deliberately
  uses only the generic-archetype framing to stay within "no invented data."
- `[UNVERIFIED — Leader confirm]` whether the Minesweeper daily set is *ranked* the same way
  Sudoku's is (BRIEF says "per-difficulty daily leaderboards, live" for MS, so ranking is
  Verified; "a daily set of boards" in the listing is the playable side — both appear true).
