# Review Information — Minesweeper v2.6 (ASC paste-ready)

> **Version note:** Minesweeper's first App Store submission ships as **2.6.0**
> (versioning synced with Sudoku since a3e80d7; ASC confirmed 2.6.0 on
> 2026-07-04). Earlier drafts of this doc said "v1.0" — same first-release
> submission, corrected version string.

> Paste each block verbatim into the matching field under
> **App Store Connect → My Apps → Minesweeper → [version] → App Review**.
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

GAMEPLAY — CLASSIC MINESWEEPER
Three classic boards: Beginner (9×9, 10 mines), Intermediate (16×16, 40),
and Expert (16×30, 99). Tap to reveal a cell; long-press (or right-click /
control-click on Mac) to flag a suspected mine. Clearing every non-mine cell
wins; revealing a mine ends the game.

FIRST-CLICK SAFETY (why the first tap never loses)
Mines are placed lazily, AFTER the first reveal, so the first tapped cell and
its eight neighbors are always mine-free. This is the standard
"first-click-safe" Minesweeper convention — the first tap can never end the
game, by design. The full board is deterministic given (difficulty, seed,
first-click), which also makes runs reproducible.

DAILY MODE
Three puzzles per day (Beginner / Intermediate / Expert), seeded by UTC date —
the same boards for every player worldwide. The set rotates at 00:00 UTC.
Completing a daily board submits a time to the matching Game Center leaderboard
(one scoring attempt per puzzle per day).

GAME CENTER
Three daily leaderboards (Beginner / Intermediate / Expert, recurring, reset
00:00 UTC, one scoring attempt per puzzle). Game Center sign-in is optional;
gameplay works fully signed-out. All score traffic is mediated by Apple's
GameKit. Note: achievements are NOT implemented in this release (2.6.0).

REMOVE ADS — IN-APP PURCHASE (sandbox test)
Product: com.wei18.minesweeper.iap.remove_ads  (Non-Consumable, Family Sharing on)
This is the only IAP. It permanently removes banner ads app-wide.
To test:
  1. Sign the device into a Sandbox Apple Account.
  2. Launch the app. A banner ad placeholder shows at the bottom of the game
     surface.
  3. Open Settings → Remove Ads and confirm the StoreKit purchase sheet with
     the sandbox account.
  4. After purchase the banner disappears everywhere. A "Restore Purchases"
     row remains in Settings for new-device restore.
No server is involved in the purchase — Apple StoreKit 2 only.

ATT / UMP CONSENT
On first launch the Google UMP consent flow runs, followed (where applicable)
by Apple's App Tracking Transparency prompt
(NSUserTrackingUsageDescription is declared). Declining tracking is fully
supported — ads still serve, just non-personalized. No tracking occurs before
consent.

CLOUDKIT
The app uses the user's own iCloud Private Database (container
iCloud.com.wei18.minesweeper) for the Remove-Ads entitlement mirror and
saved-game data. The CloudKit schema is deployed to the PRODUCTION environment
at submission time. No app-owned backend exists.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is Google
Mobile Ads (AdMob) for the banner, declared in PrivacyInfo.xcprivacy
(NSPrivacyTracking = true, AdMob ad-serving tracking domains, OtherUsageData
used for third-party advertising). The Remove Ads IAP eliminates the ad SDK's
runtime ad calls.
```

---

## Pre-submission checklist (user-owned)

- [ ] Confirm wired feature set against `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift`
      (Game Center leaderboards, Daily engine, save-flow state).
- [ ] CloudKit schema deployed to **Production** — container `iCloud.com.wei18.minesweeper`.
      Console: Development → Schema → "Deploy Schema Changes to Production…"
      (done 2026-06-10 per review doc — re-verify if schema changed since).
- [ ] `Minesweeper/Resources/PrivacyInfo.xcprivacy` reflects live AdMob integration.
- [ ] Production AdMob App ID + banner unit ID swapped in (see memory `minesweeper-admob-ids`).
- [ ] App Privacy questionnaire in ASC matches the MS PrivacyInfo.
- [ ] Remove Ads IAP (`com.wei18.minesweeper.iap.remove_ads`) created in ASC + status **Ready to Submit**.
- [ ] `ITSAppUsesNonExemptEncryption=false` present in Info.plist (confirmed, skips export prompt).
- [ ] Contact fields above filled in from `secrets/.env` — **not committed**.
- [ ] Screenshots uploaded for all required device classes.
- [ ] IAP review screenshot attached to the Remove Ads product in ASC.
