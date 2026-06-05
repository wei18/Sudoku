# Sudoku v2.5 — "What's New" copy rationale

Refreshes `whats_new` across all 7 Sudoku locales for the v2.5 monetization
submission (issue #306). The prior text described v2.3.5 (a feature changelog).
v2.5 is the **monetization release**, so the copy now leads with what is
genuinely new in this submission: the optional banner ad and the one-tap
**Remove Ads** path.

**Edited file (one per locale):** `docs/app-store/metadata/{locale}/listing.yaml`
→ `whats_new:` field only. Locale directory names are `zh-Hant` / `zh-Hans`
(the dispatch's `zh-TW` / `zh-CN` map to these). No other field, file, or
marketing subdir was touched.

These are DRAFTS. No `metadata apply` / ASC API call was run. Leader applies later.

## Translation flow (`ai-translated-localization`)

- **Source pair authored by hand:** `en` (fan-out source) + `zh-Hant` (primary).
- **Fanned out from `en`** to `ja`, `zh-Hans`, `es`, `th`, `ko`.
- Locale gotchas applied: ja drops です/ます in the declarative bullets and uses
  semantic terms; ko uses 해요체; th drops politeness particles; es is neutral
  Latin-American; zh-Hans uses Mainland phrasing (恢复购买 / 个性化) converted
  from zh-Hant, not raw character conversion.
- Glossary kept consistent with the existing `description` blocks: "Remove Ads"
  renders as the same term already used in each locale's description
  (移除廣告 / 広告を非表示 / 移除广告 / Quitar anuncios / ลบโฆษณา / 광고 제거).

## Claim → backing Verified Fact

Every claim traces to a row in `docs/marketing/BRIEF.md` §Verified Facts.

| Claim in copy | Backing Verified Fact |
|---|---|
| "Sudoku stays free" | Monetization row: "Free; removable banner ad + one-time Remove Ads IAP" |
| Optional **banner** ad (NOT "no ads" / "ad-free") | Monetization row: "removable **banner** ad"; Do-Not-Claim ❌ "No ads"/"ad-free" — avoided |
| **Remove Ads**: one-time purchase, removes banner forever | Monetization row: "one-time **Remove Ads** IAP"; matches `docs/app-store/metadata/iap/remove-ads.yaml` (non-consumable) |
| Family Sharing included | See [UNVERIFIED] below |
| **Restore Purchases**: restore on any device | StoreKit 2 non-consumable IAP implies a restore path; standard ASC review requirement. See [UNVERIFIED] below |
| Free version → ads **non-personalized**, no tracking | Privacy row: "No third-party tracking SDK"; app-meta review notes: "UMP + ATT consent on first launch; declining is fully supported" → declining yields non-personalized ads |
| Privacy unchanged / no tracking | Privacy row: "No third-party tracking SDK. Apple-only analytics. PrivacyInfo.xcprivacy shipped" |
| Daily leaderboards | Game Center row: "Leaderboards + **daily** leaderboards, live" |
| iCloud sync for saves and records | iCloud row: "Full game saves + records sync via CloudKit" |

## `[UNVERIFIED — Leader confirm]` flags

1. **Family Sharing included** — asserted in the existing v2.3.5 `description`
   and `whats_new` (carried forward), but BRIEF §Verified Facts does not have a
   row for it. The Remove Ads IAP config (`iap/remove-ads.yaml`) should state
   whether `familySharable: true`. Leader: confirm the IAP is configured as
   Family Sharable before apply; if not, strike the Family Sharing line in all
   7 locales.

2. **Restore Purchases is user-visible** — the copy advertises a Restore action.
   StoreKit 2 supports restore for non-consumables, but this claims a **UI
   affordance** ("restore on any device with one tap"). Leader: confirm the app
   actually surfaces a Restore Purchases button in v2.5 before apply; if the
   restore entry point is not shipped, soften to "Purchases restore
   automatically when you sign in with the same Apple ID."

3. **"Non-personalized" framing** — backed by the UMP/ATT consent flow in the
   review notes (declining consent → non-personalized ads). This is accurate for
   users who decline, but a user who *grants* consent may receive personalized
   ads. The copy says ads are non-personalized "if you keep the free version,"
   which is slightly stronger than "non-personalized if you decline tracking."
   Leader: confirm whether the AdMob config requests personalized ads at all, or
   serves non-personalized unconditionally. If personalized ads can be served
   on consent, reword to "you choose whether ads are personalized — declining is
   fully supported, with no tracking."

## Per-locale character counts (whats_new value, trimmed, incl. newlines)

ASC `whats_new` limit = 4000 chars. All locales are far under; brevity was the
goal.

| Locale | Dir | Chars |
|---|---|---|
| English | `en` | 512 |
| Traditional Chinese | `zh-Hant` | 176 |
| Japanese | `ja` | 235 |
| Simplified Chinese | `zh-Hans` | 176 |
| Spanish | `es` | 593 |
| Thai | `th` | 437 |
| Korean | `ko` | 267 |

## en (source) — verbatim

```
Version 2.5

Sudoku stays free. This release adds an optional banner ad and a way to turn it off.

• Remove Ads: a one-time purchase removes the banner everywhere, forever. Family Sharing included.
• Restore Purchases: already bought it? Restore on any device with one tap.
• If you keep the free version, ads are non-personalized — no tracking, privacy unchanged.
• Daily leaderboards and iCloud sync for saves and records, as before.

Thank you for playing. Issues and feedback are welcome at the support link.
```

## zh-Hant (primary) — verbatim

```
版本 2.5

數獨依然免費。這個版本加入一條可選橫幅廣告，以及把它關掉的方法。

• 移除廣告：一次購買即可永久移除所有橫幅。含家庭共享。
• 還原購買：已經買過了？在任一裝置一鍵還原。
• 若你保留免費版，廣告為非個人化 — 無追蹤，隱私不變。
• 每日排行榜與 iCloud 存檔、紀錄同步，一如既往。

謝謝遊玩。問題與建議歡迎到支援連結回報。
```
