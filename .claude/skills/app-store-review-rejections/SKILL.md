---
name: app-store-review-rejections
description: Use when preparing an App Store submission, diagnosing an App Review rejection / Resolution Center message, or hardening these apps (Sudoku / Minesweeper / Tiles2048) against the rejection classes a free puzzle game with ads + Remove-Ads IAP + CloudKit + Game Center actually hits. Covers guideline 2.1 / 2.3 / 3.1.1 / 4.3 / 5.1.1 / 5.1.2, the ATT-vs-AdMob trap, privacy-label parity, and a pre-submit checklist.
---

# App Store Review Rejections

## Overview

App Review rejects on a small set of recurring guideline violations. Per Apple's
own transparency reporting, **performance/completeness (2.1) is the #1 cause**, and
**privacy (5.1.x)** is the leading policy cause. This skill maps the rejection
classes that **a free puzzle game with banner ads + a Remove-Ads IAP + CloudKit +
Game Center** (i.e. exactly Sudoku / Minesweeper / Tiles2048) realistically hits,
to a concrete pre-submission fix grounded in this repo's existing mechanisms.

It is the *content* companion to [[asc-ops-handoff]] (which says **who** may push
each ASC button); this says **why a build gets bounced and how to pre-empt it**.

## When to use

- Before any TestFlight→App Store submission ([[local-testflight-upload]] got the build up; this gates whether it passes review).
- A Resolution Center message arrived citing "Guideline X.Y" — find the row, apply the fix.
- Auditing a new game (game 4) for submission-readiness before #236-style work.
- NOT for the *mechanics* of submitting (that's [[asc-ops-handoff]]) or screenshot generation (that's [[appstore-screenshot-pipeline]]).

## Quick reference — rejection class → fix (weighted to these apps)

| Guideline | Why it bounces a puzzle-game-with-ads | Pre-submit fix here |
|---|---|---|
| **2.1 App Completeness** | Crash on reviewer's device/OS, dead-end flow, placeholder content, ad fails to load → blank space, debug/test ad shown in the prod build | Run the build on a *clean* device + the oldest supported OS. Ensure ads degrade gracefully (no empty frame on no-fill). TF builds carry **prod** AdMob ([[testflight-equals-prod-ads]]) — verify real ads render, not test units. No `<TRANSLATE>` / lorem strings. |
| **2.3.1 Hidden features** | Shipping dormant code / hidden toggles reviewers can reach | No DEBUG-only surfaces (NearWin hooks) reachable in Release. |
| **2.3.3 Screenshots** | Screenshots don't match the actual app, wrong dimensions, contain device frames Apple disallows, alpha channel | Do **not** upload snapshot-test baselines directly — they have an alpha channel + wrong dims ([[appstore-screenshot-pipeline]]). Use real device/sim captures at exact spec sizes. |
| **2.3.10 Irrelevant metadata** | Mentioning Android / "also on Google Play", other platform names in description/keywords | Strip platform references from all 7 locales' metadata. |
| **3.1.1 In-App Purchase** | Remove-Ads unlock sold outside IAP; **no "Restore Purchases" control**; price/【benefit】 unclear | Remove-Ads must be StoreKit IAP (it is — [[monetization-sdk-integration]]); a visible **Restore Purchases** button is mandatory or it's an auto-reject. Non-consumable must restore on reinstall. |
| **4.3(a) Spam / saturation** | **Highest latent risk for us** — "Sudoku" and "Minesweeper" are among the most saturated genres; a thin clone gets bounced as spam | Lead with genuine differentiation (design system, Daily Hub, Game Center, cross-platform). Distinct app name/icon/screenshots per app; never ship two near-identical binaries under different names. |
| **4.0 / 4.2 Minimum functionality** | Too simple, feels like a web wrapper or template | Native features (haptics, Game Center, iCloud resume, widgets if any) demonstrate platform depth. |
| **5.1.1(v) Account deletion / data** | App offers account creation but no in-app deletion path | We use **iCloud + Game Center** (Apple-managed identity, no app-account signup) — generally exempt from the *delete-account* control, BUT still provide a way to clear user CloudKit data + a privacy policy URL. **Verify the current exemption wording before relying on it.** |
| **5.1.1 Privacy policy** | Missing/unreachable privacy policy URL in ASC + in-app | Privacy policy URL set in App Privacy + reachable; covers ads (AdMob) + analytics data. |
| **5.1.2 Data Use — ATT** | **The AdMob trap.** App links the ad SDK / accesses IDFA but never shows the **App Tracking Transparency** prompt, or shows it with no `NSUserTrackingUsageDescription` | If ads use IDFA: `NSUserTrackingUsageDescription` present in **all 7 locales**, ATT prompt shown via UMP before personalized ads. **MS is missing `ATTPrimerCoordinator` (memory 6141 / SDD-005 §6) — that is a real MS submission blocker, fix before MS submit.** If you do NOT track, declare so and don't link IDFA. |
| **Privacy-label parity** | App Privacy "nutrition" answers in ASC contradict `PrivacyInfo.xcprivacy` / actual SDK behavior (AdMob collects identifiers + usage data) | ASC App Privacy answers must match the committed `PrivacyInfo.xcprivacy` and AdMob's declared collection. Keep them in sync ([[apple-three-piece-analytics]]). |
| **Age rating / 1.3** | Ads can serve mature content but rating says 4+ | Set AdMob max ad content rating appropriately; age rating must cover ad content. |
| **2.5.x / export compliance** | Build held "Processing" pending the encryption/export-compliance answer | Answer export compliance in ASC (uses standard crypto only) — user-owned, see [[local-testflight-upload]] footgun. |

## Pre-submission checklist (run before flipping a build to "Submit for Review")

1. Clean-device + oldest-OS smoke run; no crash, no blank ad frame, no debug surface.
2. `mise run scan:l10n` green — 0 `<TRANSLATE>`, all 7 locales (rejection-grade for 2.1/2.3).
3. ATT: `NSUserTrackingUsageDescription` localized ×7; **sim-verify the ATT prompt actually fires** on a fresh install (drive it with [[interactive-sim-ux-audit]] — reviewers reject on the *runtime* prompt being absent, not just the Info.plist key); **MS ATT primer exists**.
4. Restore-Purchases button visible; Remove-Ads restores on reinstall.
5. ASC App Privacy answers == `PrivacyInfo.xcprivacy` == AdMob's declared data use.
6. Screenshots are real captures at spec dimensions (not snapshot baselines).
7. Privacy-policy URL set and reachable; no other-platform mentions in any locale's metadata.
8. Per-app distinct name/icon/screenshots; differentiation visible in the first screenshot (4.3).

## Common mistakes

- **Trusting "it compiled / TF accepted it."** Upload success ≠ review pass; the gates above are orthogonal to a green build.
- **Re-using snapshot PNGs as store screenshots** — wrong dims + alpha → 2.3.3.
- **Adding the ad SDK but skipping ATT** — the single most common ads-app 5.1.2 bounce.
- **Filling App Privacy by guesswork** — must mirror the actual SDK + `PrivacyInfo.xcprivacy`, or it's a 5.1.x mismatch.
- **Shipping the second game as a near-clone** — 4.3 spam; the mirror principle is for *shared code*, not a duplicated *product*.

## Sources

Apple App Store Review Guidelines (developer.apple.com) + Apple App Store
Transparency Report (performance = top rejection cause); Google AdMob iOS privacy
strategies (ATT / UMP / `NSUserTrackingUsageDescription`). Re-verify guideline
numbers against the live Guidelines before quoting them in a Resolution Center
reply — Apple renumbers.
