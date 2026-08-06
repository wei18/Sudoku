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
An app-owned Daily Rank screen (Home → Leaderboard card, new in this build)
shows World and Friends daily rankings per difficulty — not just a link out
to Apple's Game Center sheet. Daily boards are identical for every player
worldwide with one scoring attempt each (deterministic generation, UTC
rollover), so the leaderboard stays fair. The first tap is always safe (see
GAMEPLAY below). The macOS build is a native SwiftUI app, not a Mac
Catalyst wrapper. All UI text ships in 7 full localizations. Ads are
banner-only — no interstitials — with a one-time Remove Ads unlock.

GAMEPLAY & FIRST-CLICK SAFETY
Three classic boards: Beginner (9×9, 10 mines), Intermediate (16×16, 40),
Expert (16×30, 99). Tap to reveal; long-press (right-click / control-click
on Mac) to flag. Clearing every non-mine cell wins. Mines are placed
lazily, AFTER the first reveal, so the first tapped cell and its eight
neighbors are always mine-free — the first tap can never end the game, by
design. The board is deterministic given (difficulty, seed, first-click).

DAILY MODE
Three boards per day (Beginner / Intermediate / Expert), seeded by UTC
date — the same boards worldwide, rotating at 00:00 UTC. Completing a
daily board submits the time to the matching leaderboard (one scoring
attempt per board per day).

GAME CENTER
Three daily leaderboards (recurring, 00:00 UTC reset) and eleven
achievements. Sign-in is optional; gameplay works fully signed-out. The
Daily Rank screen (Home → Leaderboard card) is app-owned: per-difficulty
tabs crossed with a World/Friends toggle, today's top players, and a
separate "Your Rank" row when the local player falls outside that slice.
An "Open Game Center" button reaches Apple's full dashboard (hidden when
signed out, where the system sheet cannot present). No state is a dead
end: signed-out shows a Sign-In explainer, missing friends permission
shows "Allow Friends Access", a network failure shows Retry, and an empty
board shows "No Rankings Yet".
To test: sign in to Game Center (Sandbox Apple Account) → play a Daily
board → Home → Leaderboard → toggle World and Friends across the tabs.

PLATFORM DIFFERENCES (IF REVIEWING THE MAC BUILD)
The macOS build ships NO advertising: AdMob/UMP have no macOS slice, so no
banner ever appears, the Remove Ads purchase is not offered, and the ATT /
UMP prompts never run — the two sections marked "iOS only" cannot be
exercised on the Mac build. Everything else (Daily, Game Center, resume,
iCloud sync, privacy posture) is identical on both platforms. Mac input:
flagging is secondary-click rather than long-press.

REMOVE ADS — IN-APP PURCHASE (sandbox test) — iOS only
Product: com.wei18.minesweeper.iap.remove_ads (Non-Consumable, Family
Sharing). The only IAP; it permanently removes banner ads app-wide. To
test: sign into a Sandbox Apple Account → a banner shows on the game
surface → open Settings → Purchases → Remove Ads → confirm the StoreKit
sheet. Afterwards no ads appear anywhere and the row reads "Ads Removed";
a "Restore Purchases" row remains for new-device restore. StoreKit 2 only
— no server is involved.

ATT / UMP CONSENT — iOS only
First launch runs the Google UMP consent flow, then (where applicable)
Apple's ATT prompt (NSUserTrackingUsageDescription declared). Declining is
fully supported — ads still serve, non-personalized. No tracking occurs
before consent.

RESUME & ICLOUD
Progress auto-saves and syncs, with the Remove-Ads entitlement mirror, via
the user's own iCloud Private Database (container
iCloud.com.wei18.minesweeper) — no app-owned backend. The CloudKit schema
is deployed to Production at submission time.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is
Google Mobile Ads for the banner, declared in PrivacyInfo.xcprivacy; on
macOS it is not linked at all (the shared manifest describes the iOS worst
case).
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
