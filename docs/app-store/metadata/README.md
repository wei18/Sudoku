# App Store metadata

Per-locale App Store Connect (ASC) listing copy for Sudoku v1.0.

## Files

```
metadata/
├── README.md           — this file
├── en/listing.yaml     — English (US) — SOURCE
├── zh-Hant/listing.yaml — Traditional Chinese (Taiwan) — SOURCE
├── ja/listing.yaml     — Japanese — AI-translated
├── zh-Hans/listing.yaml — Simplified Chinese — AI-translated
├── es/listing.yaml     — Spanish (neutral Latin American) — AI-translated
├── th/listing.yaml     — Thai — AI-translated
└── ko/listing.yaml     — Korean (해요체) — AI-translated
```

`en` and `zh-Hant` are author-written sources. The other five are AI-translated derivatives per the `ai-translated-localization` skill convention, with locale-specific etiquette already applied (no honorific particles in ja, no ครับ/ค่ะ in th, 해요체 mid-formality in ko, neutral LATAM Spanish, term-level conversion not character-conversion for zh-Hans).

## Field reference (per Apple ASC limits)

| Field | Limit | Notes |
|---|---|---|
| `name` | 30 chars | Localized App name |
| `subtitle` | 30 chars | One-line value prop, appears under name |
| `promotional_text` | 170 chars | Editable without re-submit |
| `description` | 4000 chars | Long-form pitch |
| `keywords` | 100 chars | Comma-separated, ASCII comma `,` only |
| `whats_new` | 4000 chars | Release notes for this version |
| `marketing_url` | optional | Project marketing site |
| `support_url` | required | Where users file bugs / questions |
| `privacy_policy_url` | required | Linked from App Store privacy panel |

## How to use

### Manual (Phase 10 A7 today)

1. Open App Store Connect → My Apps → Sudoku → version 1.0.0 → App Information & Version Information.
2. For each of the 7 locales, paste the matching field from `<locale>/listing.yaml`.
3. After upload, **diff the live ASC page against this file** — ASC silently trims trailing whitespace and re-encodes some Unicode (e.g. half-width punctuation). If a diff appears, ASC wins; update this file to match.

### Future (ASCRegister CLI extension)

`tools/ASCRegister` already handles Game Center registration via ASC API. A future subcommand (e.g. `asc-register listing push --locale en`) can read these YAML files and POST to the ASC App Metadata endpoint. The field naming in YAML matches ASC API JSON keys (snake_case) to keep that path simple.

## Character counts

Counts are taken with Unicode grapheme clusters (i.e. the way Apple counts them in ASC). Each `listing.yaml` is hand-verified once at creation; re-verify on any edit.

| Locale   | name | subtitle | promotional_text | keywords |
|----------|------|----------|------------------|----------|
| en       | 17   | 28       | 152              | 95       |
| zh-Hant  | 7    | 12       | 49               | 70       |
| ja       | 8    | 13       | 56               | 78       |
| zh-Hans  | 7    | 12       | 49               | 70       |
| es       | 24   | 29       | 158              | 96       |
| th       | 14   | 25       | 88               | 88       |
| ko       | 9    | 14       | 60               | 82       |

(Long fields `description` and `whats_new` stay well under 4000 chars in every locale.)

## Brand voice rules these files follow

- Calm, focused, understated. No "AMAZING!", no exclamation stacks, no confetti emoji.
- Lead with privacy in markets where it resonates (en, ja, ko, de-leaning markets).
- "True Mac native, not Catalyst" is the differentiator and gets explicit mention in the description.
- Honest about scope: this is v1 from a single developer, not a unicorn launch.
- No future-features promised. No Apple Watch. No Vision Pro. No widgets in v1.

## Open items (see impl-notes log)

- App Store category(ies) confirmation (Primary `Games > Puzzle`; Secondary TBD).
- Age rating confirmation (4+ recommended).
- Marketing URL — currently `null` everywhere; update if a project site is published.
