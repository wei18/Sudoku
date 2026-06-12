# Review Information — Sudoku v2.6 (ASC paste-ready)

> Paste each block verbatim into the matching field under
> **App Store Connect → My Apps → Sudoku → [version] → App Review**.
> Do NOT commit the filled-in contact fields — fill them at submission time only.
> Source of truth for the Notes block: this file. Ref: `app-meta.yaml` §review_information.

---

## Contact Information

| Field | Value |
|---|---|
| First Name | `[YOUR FIRST NAME]` |
| Last Name | `[YOUR LAST NAME]` |
| Phone Number | `[E.164 format, e.g. +886912345678]` |
| Email Address | `[ASC account email — from secrets/.env ASC_REVIEW_EMAIL]` |

**Demo Account:** None required — the app needs no login.

---

## Review Notes (paste verbatim into ASC "Notes" field)

```
No account or login is required. The app runs fully on first launch.

REMOVE ADS — IN-APP PURCHASE (sandbox test)
Product: com.wei18.sudoku.iap.remove_ads  (Non-Consumable, Family Sharing on)
This is the only IAP. It permanently removes banner ads app-wide.
To test:
  1. Sign the device into a Sandbox Apple Account (Settings → Developer →
     Sandbox Apple Account, or it will prompt at purchase).
  2. Launch the app. A banner ad placeholder shows at the bottom of Home and
     during Daily / Practice play.
  3. Open Settings → Remove Ads (or the Remove Ads row on Home) and confirm
     the StoreKit purchase sheet with the sandbox account.
  4. After purchase the banner disappears everywhere and the Remove Ads row
     hides. A "Restore Purchases" row remains in Settings for new-device restore.
No server is involved in the purchase — Apple StoreKit 2 only.

DAILY PUZZLES — UTC ROLLOVER
Daily mode serves three puzzles (Easy / Medium / Hard) that are identical for
every player worldwide. The set rotates at 00:00 UTC, not local midnight, so
near a UTC day boundary the "today" set may differ from the device's local
calendar day. This is intentional and keeps the leaderboard fair globally.

LATE-COMPLETION MARKER
If you resume a Daily puzzle from a previous UTC day, the board header shows a
"won't score" marker. Completing a past-day daily puzzle does NOT submit to
the Game Center leaderboard (only the current UTC day scores). This is by
design — the marker tells the player mid-game that the run is practice-only.

GAME CENTER
Three daily leaderboards (Easy / Medium / Hard, recurring, reset 00:00 UTC,
one scoring attempt per puzzle) and eight achievements (500 points total).
Game Center sign-in is optional; gameplay works fully signed-out. All score
and achievement traffic is mediated by Apple's GameKit.

RESUME / SAVED GAMES
The app auto-saves progress. The home screen shows a one-tap "Resume" pill
when a game is in progress. Saves sync via the user's iCloud Private Database
(container iCloud.com.wei18.sudoku) — no app-owned backend.

ATT / UMP CONSENT
On first launch the Google UMP consent flow runs, followed (where applicable)
by Apple's App Tracking Transparency prompt
(NSUserTrackingUsageDescription is declared). Declining tracking is fully
supported — ads still serve, just non-personalized. No tracking occurs before
consent.

CLOUDKIT
Saved games, statistics, and the Remove-Ads entitlement mirror sync through
the user's own iCloud Private Database (container iCloud.com.wei18.sudoku).
The CloudKit schema is deployed to the PRODUCTION environment at submission
time. No app-owned backend exists.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is Google
Mobile Ads (AdMob) for the banner, declared in PrivacyInfo.xcprivacy
(NSPrivacyTracking = true, AdMob ad-serving tracking domains, OtherUsageData
used for third-party advertising). The Remove Ads IAP eliminates the ad SDK's
runtime ad calls.
```

---

## Pre-submission checklist (user-owned)

- [ ] CloudKit schema deployed to **Production** — container `iCloud.com.wei18.sudoku`.
      Console: Development → Schema → "Deploy Schema Changes to Production…"
      (cktool cannot push prod). Sync Dev first: `mise run ck:schema deploy --app sudoku --env development`.
- [ ] Sandbox Apple Account provisioned for reviewer's region.
- [ ] Production AdMob App ID + banner unit ID swapped in (paired flip, see memory `admob-production-ids`).
- [ ] App Privacy questionnaire in ASC matches `Sudoku/Resources/PrivacyInfo.xcprivacy`.
- [ ] Remove Ads IAP (`com.wei18.sudoku.iap.remove_ads`) status = **Ready to Submit** and attached to this version.
- [ ] Contact fields above filled in from `secrets/.env` — **not committed**.
- [ ] Screenshots uploaded for all required device classes (see `screenshot-strategy.md`).
- [ ] IAP review screenshot attached to the Remove Ads product in ASC.
