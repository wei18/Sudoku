# MS Monetization Phase 2 — ASCRegister Extension (impl-notes)

Live notes captured during execution. Distinct from the post-hoc meeting log.

## Scope

Extend ASCRegister to support the Minesweeper `remove_ads` IAP without
restructuring per-app config — both products coexist in `Config.iaps`,
runtime targeting via `--app-id` discriminates.

## Key decisions

### 1. `shortId` derivation must handle multiple bundle namespaces

The existing `shortId` implementation hard-stripped
`com.wei18.sudoku.iap.` — that returns the unmodified MS productId
(`com.wei18.minesweeper.iap.remove_ads`), which then forms a malformed
key `iap.com.wei18.minesweeper.iap.remove_ads.name`.

Per dispatch spec, MS keys must be `iap.minesweeper.remove_ads.{name,description}`.
So Sudoku shortId = `remove_ads`, MS shortId = `minesweeper.remove_ads`.

**Rule chosen**: strip the literal `com.wei18.sudoku.iap.` if the
productId begins with it (preserves the shipped Sudoku key shape);
otherwise strip the `com.wei18.` vendor prefix and collapse the `.iap.`
infix to a single dot. Yields:
- `com.wei18.sudoku.iap.remove_ads` → `remove_ads`
- `com.wei18.minesweeper.iap.remove_ads` → `minesweeper.remove_ads`
- Future `com.wei18.<otherapp>.iap.<x>` → `<otherapp>.<x>`

This keeps Sudoku's shipped key bytes unchanged (no migration on the
existing en + zh-Hant entries in `Sudoku/Resources/Localizable.xcstrings`)
while giving MS a deterministic namespaced key.

### 2. MS xcstrings catalog lives in Minesweeper/Resources, not Sudoku/

Per dispatch instruction — don't merge MS keys into Sudoku's catalog.
The MS catalog is currently `{}` and gets the 2 new keys directly.

### 3. iap-strings.xcstrings.patch documents both apps

Single patch file with both Sudoku (already merged) and MS (to-be-merged)
fragments is awkward. Chose to ADD a parallel
`iap-strings.minesweeper.xcstrings.patch` colocated with the existing
one, mirroring the same locale coverage convention. The original
`iap-strings.xcstrings.patch` stays as the Sudoku reference; new file
is the MS reference.

Actually — re-evaluating. Spec wording: "Add 2 MS IAP keys mirroring
Sudoku's pattern". Simpler: extend the existing patch with both keys
under a clear header section. But mixed-app patches risk confusing the
"merge into which catalog?" instruction. Decision: SEPARATE FILE
`iap-strings.minesweeper.xcstrings.patch` makes the catalog target
obvious from filename.

### 4. char count verification — both ≤55

- en description "Remove all in-app ads forever. Family Sharing." = 46 chars ✓
- zh-Hant description "永久移除 App 內所有廣告。支援「家人共享」。" = 22 chars ✓ (CJK + ASCII mix counted by Character)
- en name "Remove Ads" = 10 chars ✓
- zh-Hant name "移除廣告" = 4 chars ✓

(Will verify with actual count below.)

## Open questions for Leader / CR

- Should the MS xcstrings file also pre-seed empty entries for the
  other 5 locales (ja/zh-Hans/es/th/ko) with `<TRANSLATE>`? Doing so
  matches Sudoku's pattern and gives the translation flow a clean
  target. **Decision**: yes — mirror Sudoku exactly.

- The `referenceName` reuses "Remove Ads v1" verbatim. ASC distinguishes
  by `--app-id` so name collision across apps is fine. Leaving as-is.
