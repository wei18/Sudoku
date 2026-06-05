# ASCRegister screenshot upload — impl notes (in-flight)

Developer subagent, 2026-06-05. Branch `feat/ascregister-screenshot-upload`.

## Goal
`metadata screenshots` subcommand: upload committed PNGs to ASC per app+platform
into the correct appScreenshotSet via Apple's reserve→PUT→commit multi-part flow.
Gated behind `--i-am-sure`; default = plan (print what WOULD upload, no mutation).

## Prereq checklist (verified via WebSearch — fastlane spaceship + Runway guide + Apple docs)
- (a) screenshotDisplayType per our 3 sizes — **Verified ✓**
  - iPhone 6.9" (1290×2796) → `APP_IPHONE_67` (Apple reuses the 6.7" enum; no 6.9" enum exists in API)
  - iPad 13" (2064×2752 / 2048×2732) → `APP_IPAD_PRO_3GEN_129` (Apple reuses the 12.9" enum; no 13" enum)
  - Mac (≥1280×800) → `APP_DESKTOP`
  - Source: fastlane spaceship app_screenshot_set.rb DisplayType + deliver app_screenshot.rb ScreenSize→DisplayType map.
- (b) appScreenshots POST shape + uploadOperations — **Verified ✓**
  - POST /v1/appScreenshots, data.type=appScreenshots, attributes{fileName,fileSize},
    relationships.appScreenshotSet.data{type:appScreenshotSets,id}
  - Response attributes.uploadOperations[]: {method, url, offset, length, requestHeaders:[{name,value}]}
- (c) checksum algo — **Verified ✓** MD5 hex (Digest::MD5.hexdigest in spaceship; CryptoKit Insecure.MD5 here)
- (d) appScreenshotSet create-or-get — **Verified ✓**
  - GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets (filter by screenshotDisplayType)
  - POST /v1/appScreenshotSets attributes.screenshotDisplayType + rel appStoreVersionLocalization

## Design decisions
- **requestHeaders shape**: ASC returns `requestHeaders` as an array of `{name,value}` objects
  (NOT a dict). Decode accordingly. uploadOperations also returned as array of objects.
- **Multi-part**: slice bytes[offset..<offset+length] per operation; PUT each with its own
  headers + url. Most screenshots are single-part but the loop handles N parts.
- **Checksum**: MD5 over the FULL file bytes (not per-chunk). CryptoKit `Insecure.MD5`.
- **Idempotency**: GET existing appScreenshots in the set; if one with same fileName exists,
  SKIP (don't duplicate). Documented; replace is out of v1 scope (safer default — avoids
  destroying a manually-curated set). A `--replace` could come later.
- **Locale resolution**: reuse PlatformVersionResolver to pick editable version per platform,
  then GET its appStoreVersionLocalizations, match `--locale` (default en-US).
- **Plan vs apply**: default prints planned uploads (set ensure + per-file reserve+commit).
  `--i-am-sure` required to actually mutate (mirrors the apply gate intent). The ASCClient
  Mode is .plan unless --i-am-sure → .apply, but the screenshot PUT bypasses Mode (it's an
  external S3-style URL), so the command itself gates the whole upload sequence on i-am-sure.
- **PUT bypasses ASCClient.mutate**: the chunk PUT goes to an Apple-returned upload URL with
  NO JWT (the url carries its own auth token). New `uploadPart` method that does a raw PUT
  via the session, applying the returned requestHeaders, no Authorization injection.
- **No live calls**: all tests via URLProtocol stub (extends ASCClientURLProtocolTests harness).

## Device dir → displayType map (repo `<device>` segment)
- `iphone-6.9` → APP_IPHONE_67
- `ipad-13`    → APP_IPAD_PRO_3GEN_129
- `mac`        → APP_DESKTOP

## Open question / ambiguity
- Committed PNGs are PREVIEW-ONLY symlinks (786×1704 RGBA etc.), NOT ASC-valid (docs/app-store/
  screenshots/README.md). ASC will reject them server-side at the dimension/alpha check. The
  upload FLOW is correct + tested; submission-ready assets are a separate (documented) concern.
  The --i-am-sure gate + default-plan means we won't accidentally push invalid assets.
- Platform→device-dir mapping: ios covers `iphone-6.9` + `ipad-13`; macos covers `mac`.

## Final status (CLOSED)
- Build green; 136 tests pass (8 new screenshot tests); swiftlint clean on all touched files.
- New files: ASCClient+Screenshots.swift (client methods + UploadOperation/AssetChecksum),
  ScreenshotUpload.swift (pure discovery + device→displayType + set-index helpers).
- Edited: ASCClient.swift (send→internal + new `perform` un-signed seam), main.swift
  (`metadata screenshots` dispatch + usage + runMetadataScreenshots/uploadScreenshots/
  uploadOneScreenshot + Options.has for bare `--i-am-sure`), MetadataConfig.swift (`en→en-US`),
  ASCClientURLProtocolTests.swift (body-capture in harness + 8 tests), screenshots/README.md.
- The `--i-am-sure` gate: command builds an `.apply` client only when the flag is present;
  reserve uses `send` (not `mutate`) so it actually runs, but the whole reserve/PUT/commit
  sequence is only entered under apply (dry-run path returns before any mutation).
- NO live ASC calls anywhere; every test is offline via URLProtocol stub.
</content>
</invoke>
