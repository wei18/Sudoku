# App Store metadata

Per-locale App Store Connect (ASC) listing copy for the project's apps.

## Per-app structure (multi-app, since 2026-06-04)

The repo now ships two apps (Sudoku, Minesweeper). The directory layout is
**asymmetric on purpose**:

```
metadata/
├── README.md            — this file
├── app-meta.yaml         — Sudoku app-level (non-localized) fields (SUDOKU-IMPLICIT)
├── <locale>/listing.yaml — Sudoku listings (SUDOKU-IMPLICIT, the original tree)
├── iap/remove-ads.yaml   — Sudoku Remove Ads IAP (SUDOKU-IMPLICIT)
└── minesweeper/          — Minesweeper listings (per-app subtree)
    ├── app-meta.yaml
    ├── <locale>/listing.yaml
    └── iap/remove-ads.yaml
```

**Why asymmetric (decision 2026-06-04, #236):** the Sudoku files at the
top level are the original single-app tree, already referenced by path from
`v2.5-readiness.md`, the `asc-ops-handoff` skill, `ASCRegister` future-mode
notes, and the IAP `remove-ads.yaml`. Symmetrising now (moving Sudoku into a
`sudoku/` subdir) is a churny rename for zero functional gain this round.
Adding a `minesweeper/` subtree is the minimal, reversible mirror. A future
symmetrisation to `{sudoku,minesweeper}/` is a known, cheap follow-up — do it
when a third app lands or when the ASCRegister `metadata` mode (see plan in
`meetings/2026-06-04_asc-app-metadata-api-plan.md`) needs a uniform per-app
glob.

When the `metadata` mode ships, it should take an `--app <sudoku|minesweeper>`
flag (or derive the subtree from `--app-id`) and read the matching tree.

## Files (Sudoku, top level)

```
<locale>/listing.yaml — en (SOURCE) · zh-Hant (SOURCE) · ja · zh-Hans · es · th · ko
```

`en` and `zh-Hant` are author-written sources. The other five are AI-translated derivatives per the `ai-translated-localization` skill convention, with locale-specific etiquette already applied (no honorific particles in ja, no ครับ/ค่ะ in th, 해요체 mid-formality in ko, neutral LATAM Spanish, term-level conversion not character-conversion for zh-Hans). The Minesweeper subtree follows the same source/translation tiering.

## App-level metadata (`app-meta.yaml`, since 2026-06-04, #309)

Some ASC fields are **global per app, not per locale** — duplicating them
across the seven `listing.yaml` files would be a denormalization that drifts.
They live once per app in `app-meta.yaml`:

- `<top level>/app-meta.yaml` — Sudoku (mirrors the SUDOKU-IMPLICIT placement)
- `minesweeper/app-meta.yaml` — Minesweeper

**Shape decision (#309):** a separate per-app `app-meta.yaml` (not a block
inside one locale's listing, not a single shared top-level file) — it keeps
the existing per-locale files untouched, matches Fastlane `deliver`'s split of
per-locale vs global/`review_information`, and slots into the asymmetric
SUDOKU-IMPLICIT + `minesweeper/` layout above. Field names are snake_case to
match the ASC API JSON keys.

| Field | Scope | Source of truth |
|---|---|---|
| `copyright` | app | repo `LICENSE` — `"2026 Wei18"` (ASC prepends ©) |
| `primary_category` + `primary_first/second_sub_category` | app | Games > Puzzle/Board (Sudoku) · Board/Puzzle (Minesweeper) |
| `secondary_category` + `secondary_first/second_sub_category` | app | Games > Family (Sudoku) · Strategy (Minesweeper) |
| `review_information.{first_name,last_name,email_address,phone_number}` | per submission | **PLACEHOLDER — see flags below**; never hardcode the real PII |
| `review_information.{demo_user,demo_password}` | per submission | `null` — N/A, no login |
| `review_information.notes_source` / `notes_summary` | per submission | the canonical Notes block is the fenced text in `docs/app-store/review/{sudoku-v2.5,minesweeper-v1}.md` — paste THAT verbatim; the summary just points to it |

**Flagged placeholders (need user confirmation before any ASC upload):**
`review_information.email_address` (the ASC account email — lives in private
memory `asc-api-credentials`, deliberately not committed), `phone_number`
(E.164 contact number), and the reviewer-contact `first_name` / `last_name`.

**Legacy note:** `primary_category`, `secondary_category`, and `age_rating`
also still appear inside each `listing.yaml` (they predate `app-meta.yaml`).
`app-meta.yaml` is now the canonical home for the category fields; the
per-locale copies are kept as-is this round to avoid a churny 14-file edit and
should be treated as read-only mirrors. `age_rating` stays per-listing for now
(it is genuinely app-global too; fold it into `app-meta.yaml` in a later
cleanup if the ASCRegister `metadata` mode wants a single source).

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

- Marketing URL — currently `null` everywhere; update if a project site is published.

## Locked decisions (2026-05-20)

- **Primary category**: `Games > Puzzle`
- **Secondary category**: `Games > Family`
- **Age rating**: `4+`
