# App Store Review Notes — Sudoku v2.5

> Paste the **Review Information → Notes** field into App Store Connect at
> submission. Demo account is N/A (no login). Contact = ASC account email.
> This file is the source of truth; diff the live ASC page against it after
> upload. Refs #236.

- **App**: Sudoku (`com.wei18.sudoku`, Apple ID `6771248206`)
- **Version**: 2.5 (monetization-enabled round)
- **Platforms**: iOS 26+, macOS 26+ (universal, true SwiftUI Mac app — not Catalyst)
- **Sign-in**: none required (no demo account)

---

## Review Information — Notes (paste verbatim)

```
No account or login is required. The app runs fully on first launch.

REMOVE ADS — IN-APP PURCHASE (sandbox test)
Product: com.wei18.sudoku.iap.remove_ads  (Non-Consumable, Family Sharing on)
This is the only IAP. It permanently removes banner ads app-wide.
To test:
  1. Sign the device into a Sandbox Apple Account (Settings → Developer →
     Sandbox Apple Account, or it will prompt at purchase).
  2. Launch the app. A banner ad placeholder shows at the bottom of Home and
     during Daily / Practice play (after the 7-day new-user grace period the
     gate is force-enabled in this build for review — ads are visible
     immediately).
  3. Open Settings → Remove Ads (or the Remove Ads row on Home) and confirm
     the StoreKit purchase sheet with the sandbox account.
  4. After purchase the banner disappears everywhere and the Remove Ads row
     hides. A "Restore Purchases" row remains in Settings for new-device
     restore.
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
design (issue #228) — the marker tells the player mid-game that the run is
practice-only.

GAME CENTER
Three daily leaderboards (Easy / Medium / Hard, recurring, reset 00:00 UTC,
one scoring attempt per puzzle) and eight achievements (500 points total).
Game Center sign-in is optional; gameplay works fully signed-out. All score
and achievement traffic is mediated by Apple's GameKit.

ATT / UMP CONSENT
On first launch the Google UMP consent flow runs, followed (where applicable)
by Apple's App Tracking Transparency prompt
(NSUserTrackingUsageDescription is declared). Declining tracking is fully
supported — ads still serve, just non-personalized. No tracking occurs before
consent.

CLOUDKIT
Saved games, statistics, and the Remove-Ads entitlement mirror sync through
the user's own iCloud Private Database (container
iCloud.com.wei18.sudoku). The CloudKit schema is deployed to the PRODUCTION
environment at submission time. No app-owned backend exists.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is Google
Mobile Ads (AdMob) for the banner, declared in PrivacyInfo.xcprivacy
(NSPrivacyTracking = true, AdMob ad-serving tracking domains, OtherUsageData
used for third-party advertising). The Remove Ads IAP eliminates the ad SDK's
runtime ad calls.
```

---

## Pre-submission verification checklist (Leader/user)

- [ ] CloudKit schema deployed to **Production** (not just Development) — confirm in CK Dashboard before submit.
- [ ] Sandbox Apple Account provisioned for the reviewer's region (per `asc-ops-handoff` — user-owned).
- [ ] Production AdMob App ID + banner unit ID swapped in (paired flip, v2.5.3 — see `docs/v2/v2.5-readiness.md §v2.5.3`).
- [ ] App Privacy questionnaire in ASC matches `Sudoku/Resources/PrivacyInfo.xcprivacy` (user-owned; no API — `v2.5-readiness.md §App Privacy`).
- [ ] Remove Ads IAP status = "Ready to Submit" and attached to this version.

## Screenshots / attachments to prepare (NEED BUILT APP — deferred)

These are App-Review attachment images, distinct from the storefront
screenshots in `screenshot-strategy.md`. Capture from a real build, scrub any
personal Game Center alias / iCloud name, then drop into
`docs/app-store/review/sudoku-v2.5/`:

| # | Attachment | Shows | Source | Status |
|---|---|---|---|---|
| 1 | `iap-flow-01-offer.png` | Home/Settings with the Remove Ads row visible | iPhone build | pending-built-app |
| 2 | `iap-flow-02-sheet.png` | StoreKit purchase sheet (sandbox) | iPhone build | pending-built-app |
| 3 | `iap-flow-03-after.png` | Banner gone + Remove Ads row hidden post-purchase | iPhone build | pending-built-app |
| 4 | `gamecenter-leaderboard.png` | A daily leaderboard slice (alias scrubbed to "Player One") | iPhone/Mac build | pending-built-app |
| 5 | `late-completion-marker.png` | Board header "won't score" marker on a past-day daily | iPhone build | pending-built-app |
| 6 | `att-ump-consent.png` | The UMP + ATT consent prompts at first launch | iPhone build | pending-built-app |

> The single per-IAP **Review Screenshot** required by ASC for the Remove Ads
> product is tracked separately in
> `docs/app-store/metadata/iap/remove-ads.yaml` (`screenshot.expected_path`).

## Follow-ups (out of scope this round)

- **Sudoku v2.5 `whats_new` refresh** — the 7 `listing.yaml` files still carry
  the v1.0 release text. v2.5 adds the banner + Remove Ads IAP and should get
  a fresh `whats_new` block per locale before this submission. Tracked as a
  small follow-up task.
