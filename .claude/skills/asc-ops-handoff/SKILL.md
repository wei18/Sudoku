---
name: asc-ops-handoff
description: Decide who does each App Store Connect (ASC), TestFlight, AdMob or Apple Developer step for Sudoku and Minesweeper - the user (Apple ID, 2FA, web UI, decisions) or an agent (ASC API through the ASCRegister CLI and mise tasks). Use when planning a release or submission, before running any ASCRegister command, when a subagent asks "can I do X in ASC", when an ASC call returns ENTITY_ERROR or STATE_ERROR, or when asked how production AdMob IDs reach a build. Not for the TestFlight upload procedure (see local-testflight-upload) or screenshot generation (see appstore-screenshot-pipeline).
---

# ASC Ops Handoff

Terms: **user-owned** means only the user may do it (needs their Apple ID, a web UI, a decision or personal data). **Leader-orderable** means an agent may run it through a scripted, repeatable command.

## Current documents

| Need | File |
|---|---|
| Submission steps, in order | `docs/app-store/SUBMISSION-CHECKLIST.md` |
| App Review notes and contact table | `docs/app-store/review/<app>-v2.6-review-information.md` |
| Listing metadata schema | `docs/app-store/metadata/README.md` |
| Error codes and fixes | [`asc-entity-error-recipes.md`](asc-entity-error-recipes.md) |

`docs/v2/v2.5-readiness.md` is the v2.5 record. Do not use it for v2.6.

## Step 1: run the preflight (read-only)

```
mise run preflight:submission <sudoku|minesweeper|all> <ios|macos|all>
```

- It prints PASS, BLOCK or MANUAL-VERIFY per prerequisite and exits non-zero on any BLOCK.
- Run it before starting the checklist, and again right before the user clicks Submit.
- `--fix` changes only three things: `copyright` (from `app-meta.yaml`), `releaseType=MANUAL`, and attaching the newest processed build. It never sets pricing, age rating, content rights or review contact details.

## Step 2: classify the operation

### User-owned

Do not attempt these. Add them as unchecked items to the submission checklist or the tracking issue, and tell the user.

| Operation | Where |
|---|---|
| Apple Developer Program enrolment and renewal | developer.apple.com |
| Create the ASC API key (`.p8`, Key ID, Issuer ID) | ASC → Users and Access → Keys |
| Create the ASC app record | Developer Portal (App ID), then ASC → My Apps → + |
| App Privacy questionnaire and nutrition labels | ASC web UI. No API exists. Must match `App/<App>/Resources/PrivacyInfo.xcprivacy` |
| App pricing and availability | ASC → Pricing and Availability |
| Age rating, content rights | ASC → App Information |
| App Review contact name, email, phone | Typed by the user in ASC at submission time. Not stored in the repo or in `secrets/.env` |
| IAP price and the `Ready to Submit` status | ASC → In-App Purchases |
| Sandbox tester accounts | ASC → Users and Access → Sandbox |
| AdMob console: link the app, create the banner unit | apps.admob.com |
| TestFlight upload | `mise run tf:upload … --i-am-sure`, only when the user asks |
| Submit for Review, reply to App Review, cancel a review | ASC web UI |

### Leader-orderable

Run ASCRegister with `swift run --package-path Packages/ASCRegisterKit ASCRegister <command>`. Credentials come from `secrets/.env` (`source secrets/.env`). `ASCRegister --help` lists every flag.

| Operation | Command | Writes to ASC? |
|---|---|---|
| Submission preflight | `mise run preflight:submission …` | No (`--fix`: the three fields above) |
| Game Center leaderboards and achievements | `ASCRegister validate` / `plan` / `apply` | `apply` only |
| IAP product and its localizations | `ASCRegister iap plan` / `iap apply` | `apply` only |
| IAP review screenshot | `ASCRegister iap screenshots --iap-id <id> --screenshot <png> --i-am-sure` | Only with `--i-am-sure` |
| Listing text (description, keywords, what's new) | `ASCRegister metadata plan` / `metadata apply` | `apply` only |
| Version string | `ASCRegister metadata set-version --version <s>` | Yes |
| Screenshots | `ASCRegister metadata screenshots … --i-am-sure` (see `appstore-screenshot-pipeline`) | Only with `--i-am-sure` |
| Provisioning walkthrough HTML for the user | `mise run new_app:provisioning <asc\|admob\|cloudkit\|all> --app <name>` | No |
| Archive and export a build | `mise run tf:upload <app> <platform> --archive-only` | No |

Rules for these commands:

1. Run the `plan` (dry-run) form first and read its output.
2. Run an `apply` or `--i-am-sure` form only when the user asked for that change.
3. ASCRegister needs an existing app record (`--app-id`, or `apple_id` in `app-meta.yaml`). It cannot create one.

### Shared (agent prepares, user acts)

| Operation | Agent | User |
|---|---|---|
| Xcode Cloud signing | `ci_scripts/ci_post_clone.sh` writes `Tuist/Signing.xcconfig` from `$CI_TEAM_ID` | Connect ASC to Xcode Cloud once |
| Xcode Cloud secrets | Name the variables the scripts read (`SUDOKU_ADMOB_APP_ID`, `SUDOKU_ADMOB_BANNER_UNIT_ID`, `SUDOKU_APP_STORE_ID`, and the `MINESWEEPER_` set) | Enter the values as Secret environment variables in the workflow |
| Branch protection on `main` | Keep the workflow job names stable | Settings → Branches → required checks |

## Production AdMob IDs

Production AdMob IDs never appear in code, comments, docs or diffs. No source file changes when a build switches from test IDs to production IDs.

- `App/<App>/Info.plist` holds `$(ADMOB_APP_ID)` and `$(ADMOB_BANNER_UNIT_ID)`.
- The values come from the gitignored `Tuist/AdMob.xcconfig`. The committed template `Tuist/AdMob.xcconfig.example` holds Google's public test IDs.
- Local release builds: `mise run tf:upload` writes `Tuist/AdMob.xcconfig` from `<APP>_ADMOB_APP_ID` and `<APP>_ADMOB_BANNER_UNIT_ID` in `secrets/.env`. The user fills `secrets/.env`.
- Xcode Cloud builds: `ci_scripts/ci_post_clone.sh` writes the same file from the workflow's Secret environment variables.
- Debug builds always request Google's test banner unit, whatever the xcconfig holds. Release builds, including TestFlight builds, use the injected IDs.
- `mise run scan:admob` checks that only `LiveAdMobBridge.swift` imports the ads SDK. No gate detects an AdMob ID in a diff: read your diff before every commit.

If a task seems to need a production ID in a file, stop and ask the user. Mechanism details: `apple-dev-skills:build-time-secret-injection`.

## Facts that are often assumed wrong

- IAP is not fully automated. ASCRegister creates the product, its localizations and the review screenshot. Price and the `Ready to Submit` status stay in the web UI.
- The App Privacy questionnaire has no API.
- A `reviewSubmissions` record cannot be deleted. It can be cancelled only while in review. See the recipes file.
- An ASCRegister mode that works for Game Center says nothing about other modes. Check `ASCRegister --help` per mode.
