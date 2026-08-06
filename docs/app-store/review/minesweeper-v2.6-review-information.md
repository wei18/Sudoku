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
| Email Address | `[ASC account email — supplied by the user directly at submission time; not stored in this repo]` |

**Demo Account:** None required — the app needs no login.

---

## Review Notes (paste verbatim into ASC "Notes" field)

```
No account or login is required. The app runs fully on first launch.

WHAT MAKES THIS APP DIFFERENT
This build adds an app-owned Daily Rank screen (Home → Leaderboard card) with
World and Friends scopes per difficulty, not just a link out to Apple's Game
Center sheet. Daily puzzles are identical for every player worldwide with one
scoring attempt per puzzle — deterministic generation, UTC rollover — so the
leaderboard stays fair. The first tap is always safe: mines are placed lazily
after the first reveal, so the opening cell and its neighbors can never be a
mine (see FIRST-CLICK SAFETY below). The macOS build is a native SwiftUI app
(Tuist `.mac` destination), not a Mac Catalyst wrapper. All UI text ships in
7 full localizations (en, zh-Hant, zh-Hans, ja, ko, es, th). Ads are
banner-only — no interstitials, no watch-to-continue prompts.

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
00:00 UTC, one scoring attempt per puzzle). Eleven achievements report
progress on wins (e.g. first sweep, difficulty milestones, daily streaks).
Game Center sign-in is optional; gameplay works fully signed-out. All score
and achievement traffic is mediated by Apple's GameKit.

The Daily Rank screen (new in this build) is reached from Home → the
Leaderboard card, and is an app-owned in-app screen, not a redirect to
Apple's Game Center sheet. It shows per-difficulty segmented tabs crossed
with a World/Friends scope toggle; each combination lists the top-ranked
players for today plus, when the local player falls outside that slice, a
separate "Your Rank" row. A persistent "Open Game Center" button stays
reachable for Apple's full dashboard — hidden only in the signed-out state,
where GKGameCenterViewController refuses to present and the button would be
a dead end otherwise. Every non-populated state is an explainer, never a
blank screen: signed-out shows a "Sign in to Game Center" prompt; Friends
scope without friends-list permission shows an "Allow Friends Access"
prompt; a network failure shows Retry; a scope/difficulty with no scores yet
shows "No Rankings Yet" with scope-specific copy.
To test: sign in to Game Center (Sandbox Apple Account) → complete or start
a Daily puzzle → open Home → Leaderboard → toggle World and Friends across
the three difficulty tabs.

PLATFORM DIFFERENCES (READ FIRST IF REVIEWING THE MAC BUILD)
The macOS build ships NO advertising: Google's AdMob and UMP SDKs have no
macOS slice, so no banner ever appears, the "Remove Ads" in-app purchase is
not offered in Settings, and the ATT / UMP consent prompts never run. The
three sections below marked "iOS only" therefore do not apply to the Mac
build and cannot be exercised there. Everything else in this document —
Daily / UTC rollover, Game Center, resume, CloudKit, privacy posture — is
identical on both platforms. Mac-specific input: flagging is secondary-click
(right-click / control-click) rather than long-press.

REMOVE ADS — IN-APP PURCHASE (sandbox test) — iOS only
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

ATT / UMP CONSENT — iOS only
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
runtime ad calls. On macOS the AdMob SDK is not linked at all, so none of that
ad-serving or tracking activity occurs on that platform; the manifest is shared
across both builds and describes the iOS worst case.
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
- [ ] Contact fields above filled in **by the user directly** — **not committed, not in secrets/.env**.
- [ ] Screenshots uploaded for all required device classes.
- [ ] IAP review screenshot attached to the Remove Ads product in ASC.
