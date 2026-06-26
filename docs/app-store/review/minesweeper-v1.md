# App Store Review Notes — Minesweeper v1

> Paste the **Review Information → Notes** field into App Store Connect at
> submission. Demo account is N/A (no login). Contact = ASC account email.
> This file is the source of truth; diff the live ASC page against it after
> upload. Refs #236.

- **App**: Minesweeper (`com.wei18.minesweeper`)
- **Version**: 1.0 (first submission)
- **Platforms**: iOS 26+, macOS 26+ (universal, true SwiftUI Mac app — not Catalyst)
- **Sign-in**: none required (no demo account)

> **Feature-gating note for the drafter (not for ASC):** This app mirrors
> Sudoku's frame. As-built state (#592 refresh — matches the per-feature table
> below): **Game Center leaderboards ARE wired + live** (#291/#328 — 3
> per-difficulty recurring-daily leaderboards created via API), so they MAY be
> claimed. **Game Center achievements are NOT wired** (no MS achievements) —
> omit them. The **Daily hub IS wired** (#290/#307 — date-seeded trio,
> deterministic per UTC-day, snapshot-tested), so competitive Daily scoring may
> be described. Still gated: **saved-game resume** (persistence wired but the
> save-flow path is a follow-up) — don't claim "automatic saves"/"resume" yet.
> Confirm the wired state against `Live.swift` before each real submission.

---

## Review Information — Notes (paste verbatim)

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
future saved-game sync. The CloudKit schema is deployed to the PRODUCTION
environment at submission time. No app-owned backend exists.

PRIVACY
No first-party analytics, CRM, or backend. The only third-party SDK is Google
Mobile Ads (AdMob) for the banner, declared in PrivacyInfo.xcprivacy
(NSPrivacyTracking = true, AdMob ad-serving tracking domains, OtherUsageData
used for third-party advertising). The Remove Ads IAP eliminates the ad SDK's
runtime ad calls.
```

---

## Pending-feature flags (DO NOT claim until wired)

| Feature | Sudoku has it | Minesweeper state | Listing/notes treatment |
|---|---|---|---|
| Game Center leaderboards | yes | **WIRED + live in ASC** (#291/#328 — 3 per-difficulty recurring-daily leaderboards created via API) | may be listed/claimed; add the leaderboard block to notes + a leaderboard screenshot |
| Game Center achievements | yes | **not wired** (no MS achievements) | omit achievements from v1 listing + notes |
| Daily (date-seeded) | yes | **WIRED** (#290/#307 — date-seeded trio, deterministic per UTC-day) | may describe the daily puzzles + their daily leaderboards |
| Saved-game resume | yes (CloudKit) | persistence wired, **save-flow still a follow-up** (no SavedGameStore.fetch path) | omit "resume" / "automatic saves" until the save flow lands (copy already scrubbed, #236) |

Updated 2026-06-05: the MS mirror-Sudoku build-out epic (#293) shipped this
session — Game Center leaderboards and the Daily mode are now wired (the
earlier "not wired / stub" rows were pre-build-out). Saved-game resume remains
the one genuinely-unwired feature; the store copy was scrubbed of resume claims
accordingly (#236).

## Pre-submission verification checklist (Leader/user)

- [ ] Confirm wired feature set against `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift` (Game Center? Daily engine? save-flow?).
- [ ] CloudKit schema deployed to **Production** for `iCloud.com.wei18.minesweeper` — user-owned via CloudKit Console: container → Development → Schema → "Deploy Schema Changes to Production…" (cktool cannot push prod — foundations §7.7.2); sync Dev first with `mise run ck:schema deploy --app minesweeper --env development`. ✅ Done 2026-06-10 (prod == cloudkit/minesweeper.ckdb verified).
- [ ] `Minesweeper/Resources/PrivacyInfo.xcprivacy` reflects the real AdMob integration (it currently carries the Sudoku tracking stance — correct now that AdMob is wired, but the framing comment still says "copied in anticipation"; refresh the comment in a separate chore).
- [ ] Production AdMob App ID + banner unit ID swapped in (paired flip — project memory `minesweeper-admob-ids`, held until MS v1 ships).
- [ ] App Privacy questionnaire in ASC matches the MS PrivacyInfo (user-owned; no API).
- [ ] Remove Ads IAP created in ASC (`com.wei18.minesweeper.iap.remove_ads`) + status "Ready to Submit".
- [ ] `ITSAppUsesNonExemptEncryption=false` present in Info.plist (confirmed — skips the TestFlight export prompt).

## Screenshots / attachments to prepare (NEED BUILT APP — deferred)

Capture from a real build, scrub personal data, drop into
`docs/app-store/review/minesweeper-v1/`:

| # | Attachment | Shows | Source | Status |
|---|---|---|---|---|
| 1 | `first-click-safe.png` | First tap revealing a safe flood-fill region (illustrates first-click safety) | iPhone build | pending-built-app |
| 2 | `iap-flow-01-offer.png` | Settings with the Remove Ads row visible | iPhone build | pending-built-app |
| 3 | `iap-flow-02-sheet.png` | StoreKit purchase sheet (sandbox) | iPhone build | pending-built-app |
| 4 | `iap-flow-03-after.png` | Banner gone post-purchase | iPhone build | pending-built-app |
| 5 | `att-ump-consent.png` | UMP + ATT consent prompts at first launch | iPhone build | pending-built-app |

> The single per-IAP **Review Screenshot** required by ASC for the Remove Ads
> product will live in `docs/app-store/metadata/minesweeper/iap/remove-ads.yaml`
> (`screenshot.expected_path`) once that IAP config file lands.
