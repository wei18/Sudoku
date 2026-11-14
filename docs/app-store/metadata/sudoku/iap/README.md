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
plugin skill `apple-dev-skills:ai-translated-localization`.

## Sync to ASC

The IAP is synced with the `ASCRegister` CLI, not from this YAML:

- `ASCRegister iap plan` / `iap apply` create or update the product and its
  localizations. Product ids and review notes come from `Config.iaps`
  (`Packages/ASCRegisterKit/Sources/ASCRegister/Config.swift`); names and
  descriptions come from the app's `Localizable.xcstrings`.
- `ASCRegister iap screenshots` uploads `remove-ads/review-screenshot.png`.
- The price and the `Ready to Submit` status are set by the user in the ASC web UI.

Keep this YAML in step with those sources when either changes. Who may run each
command: `.claude/skills/asc-ops-handoff/SKILL.md`.
