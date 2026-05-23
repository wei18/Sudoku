# ASC App Privacy API Research — impl-notes

> Dispatched: 2026-05-23. Scope: investigate whether the official App Store
> Connect REST API supports automating the **App Privacy questionnaire**
> (ASC console → App → App Privacy), so we can extend `ASCRegister` (which
> today handles IAP + Game Center via JWT-signed REST).

## Verdict: Case B — No write API exists

The App Store Connect REST API (the JWT-signed `api.appstoreconnect.apple.com`
surface that `ASCRegister` already uses) **does not expose endpoints for the
App Privacy questionnaire**. The privacy nutrition labels can only be set via
the ASC web console (or via Apple's internal, session-cookie-authenticated
endpoints that fastlane reverse-engineers).

### Evidence

1. **Apple's "Manage app privacy" help page** documents only the web-console
   flow (Apps → [app] → App Privacy → Get Started). No API reference is
   cross-linked, in contrast to IAP / Game Center / TestFlight which all
   point at REST endpoints.
   <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>

2. **Apple's App Store Connect API doc index** (`/documentation/appstoreconnectapi`)
   has no `appPrivacyDetails`, `appDataUsages`, `appDataUsageCategories`, or
   `appPrivacyChoice*` resources. Adjacent resources that *do* exist for
   privacy-policy URL (a different thing) live under
   `appInfoLocalizations.privacyPolicyUrl` — that is just the URL string,
   not the questionnaire answers.

3. **Fastlane** maintains `upload_app_privacy_details_to_app_store`, which
   the docs explicitly caveat:
   > "The APIs this action uses are not available on the official App Store
   > Connect API, so the App Store Connect API Key cannot be used at this
   > time. Currently there is no endpoint for this, so you need to use
   > session login."
   — <https://docs.fastlane.tools/actions/upload_app_privacy_details_to_app_store/>

   i.e. fastlane drives ASC via Apple-ID + 2FA cookie against
   undocumented endpoints. That's the only known automation path and it
   does not fit `ASCRegister`'s JWT-only auth model. Adopting it would
   force us to store an Apple ID password / 2FA session in CI — a strict
   downgrade in security vs the current `.p8` key.

4. ASC API release notes (2024-2026) contain no entry adding a
   privacy-questionnaire endpoint.

### Implication for ASCRegister

We will **not** extend `ASCRegister` for App Privacy. Reasons:

- No JWT endpoint to call.
- Cookie-based automation (fastlane-style) violates `ASCRegister`'s
  Apple-only + `.p8`-key contract (`ASCClient.swift` lines 16-67).
- Frequency is low (once per app lifetime, plus on third-party SDK
  changes) — manual entry through the web console is acceptable.

If Apple ships an `appDataUsages` endpoint later (the naming convention
matches their pattern), re-open this investigation.

## Handoff: manual checklist

Added to `docs/v2/v2.5-readiness.md` under `## App Privacy questionnaire (manual)`
— a 1:1 mirror of `App/Resources/PrivacyInfo.xcprivacy` entries mapped to
ASC console field labels (English + zh-Hant), with the exact navigation path.

Estimate for the Case-A follow-up (Senior Developer extending `ASCRegister`):
N/A — Case B. **0 hours** for ASCRegister code. ~15 minutes for the user to
fill the ASC console form once, following the checklist.

## Sources

- <https://developer.apple.com/documentation/appstoreconnectapi>
- <https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/>
- <https://docs.fastlane.tools/actions/upload_app_privacy_details_to_app_store/>
- <https://developer.apple.com/app-store/app-privacy-details/>
