# App Store Copy Correction — Path B "No tracking" defect

**Status:** DRAFT (not applied). Leader re-applies to ASC later with user authorization.
**Branch:** `fix/metadata-path-b-tracking-copy`
**Supersedes:** held PR #306 (its `whats_new` content would re-assert a "no tracking" claim — incompatible with Path B).
**Date:** 2026-06-05

## Defect

Live ASC metadata for Sudoku + Minesweeper (all 7 locales) asserted **"No tracking" / "無追蹤"**
in `promotional_text`, `description`, and a feature bullet / `whats_new` line. This is **false** for
v2+: AdMob uses the iOS advertising identifier (IDFA) for ad relevance behind the ATT prompt, and
`PrivacyInfo.xcprivacy` declares `NSPrivacyTracking=true`. Confirmed P1 copy-accuracy defect.

## Decision — Path B (user-confirmed 2026-06-05)

Keep personalized ads (with consent), framed **gently and accurately**: the tracking is for
**ad relevance**, not a personal profile. Source of truth: `docs/marketing/BRIEF.md` §Do-Not-Claim
"No tracking" entry + Privacy row.

## Approved framing (the only claim asserted)

> No first-party analytics building a profile of you. Ads may use an advertising identifier to stay
> relevant — only with your permission; you can decline (ads still show, just less tailored) or remove
> ads entirely. The identifier is for ad relevance, not a personal profile of you.

- **promotional_text** (≤170): short variant — "We don't profile you; ads tailor only with consent —
  or remove them." (decline/remove nuance carried fully in the description; promo is a hook).
- **description** (≤4000): full gentle paragraph; the third-party-SDK sentence now notes the ad
  identifier + permission + decline-still-works + remove option + "for relevance, not a profile".
- **feature bullet / whats_new** (Sudoku): reframed from "No tracking." to "No first-party profiling;
  ads tailor only with permission — decline, or remove."

## What is NOT changed

- **Minesweeper `description`** never claimed "no tracking" (it said "No first-party analytics / No
  CRM / No backend" — all true). It only gained the gentle ad-identifier note for honesty; no false
  claim was present there.
- **Minesweeper `whats_new`** had no tracking claim — untouched.
- `keywords`, `name`, `subtitle`, URLs, categories, age rating — untouched.

## Voice

Calm, precise, understated — mirrors the apps' brand contract and BRIEF voice rules. Deliberately
NOT alarming ("we track you") and NOT false ("no tracking").

## Honesty boundary check

- ❌ "No tracking" / absolute — removed everywhere.
- ❌ "we track you" / alarming — never used.
- ✅ "ad relevance with permission, not a personal profile; decline or remove ads" — used, per BRIEF.
