# App Store Connect — IAP metadata

Per-IAP-product metadata (localizations, App Review notes, pricing) maintained as commit-trackable YAML.

## Files

```
iap/
├── README.md         — this file
└── remove-ads.yaml   — Remove Ads ($2.99 non-consumable)
```

## Conventions

Each `<product-slug>.yaml` is a single source-of-truth file covering:

- `product_id` / `reference_name` — match what's at ASC + `Sudoku.storekit`
- `localizations.<locale>.{name, description}` — per the app's 7 supported locales
  (en, zh-Hant, ja, zh-Hans, es, th, ko). `name` ≤ 30 chars, `description` ≤ 45 chars.
- `review_notes` — visible to App Review only. English. Triggers + observable behaviour.
- `pricing` — tier + family-sharing + availability flags
- `screenshot` — App Review screenshot spec + status (user-owned capture)

en + zh-Hant are author-written sources. Other 5 locales are AI-translated per the
[`ai-translated-localization`](../../../../../.claude/skills/ai-translated-localization/SKILL.md) skill convention.

## Sync to ASC

**Today (manual)**: for each IAP, open ASC → My Apps → Sudoku → App 內購買項目 →
the product → 本地化 (Localization). Paste `name` + `description` per locale.
Paste `review_notes` into 「審查備註」. Paste pricing tier. Upload screenshot.

**Future**: issue [#200](https://github.com/wei18/Sudoku/issues/200) extends
ASCRegister to consume these YAML files and drive the ASC API directly — at
which point edits land via `mise run asc:apply` and become commit-trackable in
the same flow as Game Center.
