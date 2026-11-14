# ASC error recipes

Use this file when an App Store Connect (ASC) call made by `ASCRegister` or `mise run preflight:submission` returns an error.

How to use it:

1. Find the error code in a table below.
2. Apply the fix. For Game Center codes the fix is an edit to `Packages/ASCRegisterKit/Sources/ASCRegister/Config.swift`.
3. Run the `plan` form again, then `apply`.

Each recipe is a hint. Check it against the current `Config.swift` and the ASC response before relying on it. "User-owned" means only the user can do it, in the ASC web UI.

`ENTITY_ERROR` comes from a create or update of one resource. `STATE_ERROR` comes from the call that creates a submission.

## Submission errors

| Code | Cause | Fix | Who |
|---|---|---|---|
| `STATE_ERROR.APP_PRICING_REQUIRED` | The app has no price schedule | ASC → app → Pricing and Availability: set a base territory and a price | User-owned |
| `ENTITY_ERROR.ATTRIBUTE.REQUIRED` (copyright) | `appStoreVersions.copyright` is empty | `mise run preflight:submission <app> <platform> --fix` (copies the value from `docs/app-store/metadata/<app>/app-meta.yaml`) | Agent |
| No code; creating a `reviewSubmissions` record fails | An earlier `reviewSubmissions` record is not in state `COMPLETE` | Wait until it enters review, then cancel it; or wait until it completes. See note 1 | User-owned |

Note 1, `reviewSubmissions`:

- The API has no DELETE for this resource.
- The only change is `PATCH /v1/reviewSubmissions/{id}` with `attributes.state = CANCELING`.
- ASC accepts that PATCH only while the record is `IN_REVIEW` or `UNRESOLVED_ISSUES`. It rejects it for `READY_FOR_REVIEW`.
- The preflight reports any record that is not `COMPLETE`.

Note 2, scripting a price schedule (not done in this repo, unconfirmed against Apple's reference):

- `POST /v1/appPriceSchedules` takes no attributes, only the relationships `app`, `territory` (the base territory) and `manualPrices`.
- The manual price is created in the same request's `included[]` array with a client-made local id of the form `"${local-id}"`, and `manualPrices` refers to that id.
- The preflight only detects a missing schedule (`GET /v1/apps/{id}/appPriceSchedule`). The price is a decision and stays user-owned.

## Game Center registration errors

| `ENTITY_ERROR` code | Cause | Fix |
|---|---|---|
| `LOCALE_INVALID` | ASC rejects the locale code | In `Config.ascLocaleCode` use `zh-Hant` and `zh-Hans` (no region), and bare `th` and `ko`. `en-US` and `es-ES` are accepted |
| `INVALID_POINTS_RANGE` | Achievement points outside 0–100 | Clamp every points value to 0–100 |
| `RECURRENCE_RULE_INVALID` | ASC wants an RFC 5545 rule | `"DAILY"` → `"FREQ=DAILY;INTERVAL=1"`; update `ConfigConsistencyTests` |
| `RECURRENCE_START_CANNOT_BE_PAST` | `recurrenceStartDate` is not in the future | Use `LeaderboardConfig.nextRecurrenceStartDateUTC()` |
| `RECURRENCE_DURATION_INVALID` | Duration lacks a time component | `"P1D"` → `"PT24H"`; update the tests |
| `RECURRENCE_START_DATE_REQUIRED` | A recurring leaderboard lacks `recurrenceStartDate` or `recurrenceDuration` | Send both fields; assert it in `ConfigConsistencyTests` |
| `SCORE_SORT_TYPE_INVALID` | Bad `scoreSortType`, or `submissionType` is missing | `scoreSortType` is `ASCENDING` or `DESCENDING`; `submissionType` is `RECURRING` or `MANUAL` |

## IAP review screenshot errors

| Code | Cause | Fix | Who |
|---|---|---|---|
| `MEDIA_ASSET_DELETE_NOT_ALLOWED` (HTTP 409 on `DELETE /v1/inAppPurchaseAppStoreReviewScreenshots/{id}`) | ASC locks the review screenshot once the IAP is `READY_TO_SUBMIT` or later. `ASCRegister iap screenshots` deletes the old asset before uploading, so it stops here | ASC → app → In-App Purchases → the IAP → Review Information: replace the screenshot | User-owned |

Note 3, why the API cannot replace it:

- `PATCH /v1/inAppPurchaseAppStoreReviewScreenshots/{id}` accepts only `sourceFileChecksum` and `uploaded`. It cannot attach new image bytes to an existing screenshot.
- Replacing content therefore needs DELETE then POST, and DELETE is the locked call.
- Do not try a PATCH-based replace: it cannot change the image and can mark a stale reservation as uploaded.
- When reading `ASCRegister` code: `assetDeliveryState` is a nested object in the raw response; `APIResource.flattenAttributes` reduces it to its `state` string.
