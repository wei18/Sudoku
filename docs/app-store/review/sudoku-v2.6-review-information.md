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
| Email Address | `[ASC account email — supplied by the user directly at submission time; not stored in this repo]` |

**Demo Account:** None required — the app needs no login.

---

## Review Notes (paste verbatim into ASC "Notes" field)

```
No account or login is required. The app runs fully on first launch.

WHAT MAKES THIS APP DIFFERENT
An app-owned Daily Rank screen (Home → Leaderboard card, new in this build)
shows World and Friends daily rankings per difficulty — not just a link out
to Apple's Game Center sheet. Daily puzzles are identical for every player
worldwide with one scoring attempt each (deterministic generation, UTC
rollover), so the leaderboard stays fair. The macOS build is a native
SwiftUI app, not a Mac Catalyst wrapper. All UI text ships in 7 full
localizations. Ads are banner-only — no interstitials — with a one-time
Remove Ads unlock.

PLATFORM DIFFERENCES (IF REVIEWING THE MAC BUILD)
The macOS build ships NO advertising: AdMob/UMP have no macOS slice, so no
banner ever appears, the Remove Ads purchase is not offered, and the ATT /
UMP prompts never run — the two sections marked "iOS only" cannot be
exercised on the Mac build. Everything else (Daily, Game Center, resume,
iCloud sync, privacy posture) is identical on both platforms.

REMOVE ADS — IN-APP PURCHASE (sandbox test) — iOS only
Product: com.wei18.sudoku.iap.remove_ads (Non-Consumable, Family Sharing).
The only IAP; it permanently removes banner ads app-wide. To test: sign
into a Sandbox Apple Account → banners show on Home and during play → open
Settings → Purchases → Remove Ads → confirm the StoreKit sheet. Afterwards
no ads appear anywhere and the row reads "Ads Removed"; a "Restore
Purchases" row remains for new-device restore. StoreKit 2 only — no server
is involved.

DAILY PUZZLES — UTC ROLLOVER
Three puzzles daily (Easy / Medium / Hard), identical worldwide, rotating
at 00:00 UTC rather than local midnight to keep the leaderboard fair.
Resuming a previous UTC day's puzzle shows a "won't score" marker — late
completions intentionally do not submit to the leaderboard.

GAME CENTER
Three daily leaderboards (recurring, 00:00 UTC reset, one scoring attempt
per puzzle) and eleven achievements. Sign-in is optional; gameplay works
fully signed-out. The Daily Rank screen (Home → Leaderboard card) is
app-owned: per-difficulty tabs crossed with a World/Friends toggle, today's
top players, and a separate "Your Rank" row when the local player falls
outside that slice. An "Open Game Center" button reaches Apple's full
dashboard (hidden when signed out, where the system sheet cannot present).
No state is a dead end: signed-out shows a Sign-In explainer, missing
friends permission shows "Allow Friends Access", a network failure shows
Retry, and an empty board shows "No Rankings Yet".
To test: sign in to Game Center (Sandbox Apple Account) → play a Daily
puzzle → Home → Leaderboard → toggle World and Friends across the tabs.

RESUME & ICLOUD
Progress auto-saves; Home shows a one-tap Resume pill. Saves, statistics
and the Remove-Ads entitlement sync via the user's own iCloud Private
Database (container iCloud.com.wei18.sudoku) — no app-owned backend. The
CloudKit schema is deployed to Production at submission time.

ATT / UMP CONSENT — iOS only
First launch runs the Google UMP consent flow, then (where applicable)
Apple's ATT prompt (NSUserTrackingUsageDescription declared). Declining is
fully supported — ads still serve, non-personalized. No tracking occurs
before consent.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is
Google Mobile Ads for the banner, declared in PrivacyInfo.xcprivacy; on
macOS it is not linked at all (the shared manifest describes the iOS worst
case).
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
- [ ] Contact fields above filled in **by the user directly** — **not committed, not in secrets/.env**.
- [ ] Screenshots uploaded for all required device classes (see `screenshot-strategy.md`).
- [ ] IAP review screenshot attached to the Remove Ads product in ASC.
