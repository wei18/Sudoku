# 2026-05-20 — zh locale (no region) for ASC Game Center

Status: COMPLETE

## Context

Issue #37. Round-7 ASC apply: `en-US` accepted; `zh-Hant-TW` rejected with `LOCALE_INVALID`. ASC's Game Center locale catalog uses script-only `zh-Hant` / `zh-Hans` (no region) for Chinese.

## Change

`Config.ascLocaleCode(for:)`: `"zh-Hant"` → `"zh-Hant"` (was `"zh-Hant-TW"`); `"zh-Hans"` → `"zh-Hans"` (was `"zh-Hans-CN"`). Other locales unchanged. Updated doc comment to cite both #31 and #37. Updated two test assertions to match. Updated a stale `zh-Hant-TW` example comment in `Reconciler.swift`.

## Verification

- `swift build` clean, no warnings.
- `swift test`: 363/363 passed.
