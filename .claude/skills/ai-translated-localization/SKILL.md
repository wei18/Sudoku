---
name: ai-translated-localization
description: Default localization scope for Apple-platform Apps — 7 locales (zh-TW, en, ja, zh-CN, es, th, ko) translated via AI agent flow as a `plan.md` step, using `Localizable.xcstrings`. Minimum viable set is zh-TW + en. Invoke when starting a new project, deciding L10n scope, choosing string catalog format, or when asked "which languages to support / how to set up the translation flow".
---

# AI-Translated Localization

## When to invoke

- Starting a new App and deciding which locales to support.
- Choosing a string catalog format (`.strings` vs `.xcstrings`).
- Planning the translation flow (manual / agency / AI agent).
- User asks "are 7 locales too many", "how do translations enter git", "how to handle multi-locale App Store metadata".

## Default decisions

### Default 7 locales

| Locale | Code | Notes |
|---|---|---|
| Traditional Chinese (Taiwan) | `zh-TW` | Primary language, source of truth |
| English | `en` | International standard |
| Japanese | `ja` | Largest adjacent market outside the Chinese sphere |
| Simplified Chinese | `zh-CN` | Auto-converted from zh-TW + manual / AI review of phrasing |
| Spanish | `es` | World's second largest native-speaker base |
| Thai | `th` | Southeast Asia representative |
| Korean | `ko` | High-penetration Asian market |

- **Minimum set**: zh-TW + en (every project includes at least these two).
- Per-project locale lists can be adjusted, but **English and zh-TW are always included**.

### Translation flow

- **Handled by an AI agent**, recorded as a step in `plan.md`: "use zh-TW as source, produce the other 6 locales' strings, write into `Localizable.xcstrings`".
- Covers:
  - In-app strings
  - Game Center leaderboard / achievement names (for games)
  - App Store metadata (title / description / keywords / what's new)
  - Description text inside the Privacy Manifest
- Every time strings are added / modified, run another round of the AI translation flow; the diff lands in a PR.

### Catalog format

- Use Xcode's **`Localizable.xcstrings`** (String Catalog, introduced in Xcode 15+).
- Stop using legacy `.strings` / `.stringsdict` (unless an external tool forces it).
- xcstrings is JSON-structured: PR-friendly diffs and easy for AI to manipulate.

## Rationale

- 7 locales cover most of the global market while remaining a polish scope a solo developer can sustain.
- AI translation quality for App UI strings (short, clear context) is at commercial level; long marketing copy is still recommended for human review.
- xcstrings JSON structure is naturally friendly to AI / diff / version control.
- zh-TW as source reflects the author's native-language accuracy.

## Deviation considerations

- **Focused target market**: shrink to zh-TW + en + one target-market locale.
- **No budget / no time**: ship zh-TW + en first; mark others as `extractionState: stale` for later.
- **Regulated / sensitive content** (medical / financial / kids): **mandatory human review** after AI translation; add a review step to `plan.md`.
- **Special scripts / RTL** (Arabic / Hebrew): UI needs additional layout verification, not just translation.

## Verification checklist

- `Localizable.xcstrings` exists and each key has 7 locale entries (2 for the minimum set).
- App Store Connect metadata is complete per locale (including screenshot captions).
- Game Center / achievement display names are complete per locale.
- `PrivacyInfo.xcprivacy` description itself doesn't need to be multi-locale, but the corresponding App Store privacy policy page does.

## Related skills

- `apple-platform-targets`: xcstrings requires Xcode 15+; aligns with the deployment target's toolchain.
- `spec-phase-orchestration`: "translation" should be an explicit step in `plan.md`.
