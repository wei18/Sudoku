---
name: asc-ops-handoff
description: Use when planning, scoping, or executing user-owned App Store Connect / TestFlight / Apple Developer operations for Sudoku app — IAP product registration, App Privacy questionnaire, AdMob console linkage, sandbox tester provisioning, TestFlight upload + review, ASC submission, App Metadata uploads. Codifies which steps are user-owned (require Apple ID / 2FA / web UI) vs Leader-orderable (via ASC API + ASCRegister CLI), and the canonical doc + verification checklist for each.
---

# ASC Ops Handoff

## When to invoke

- Planning a release ship (current target: **v2.6 first App Store release**, both apps) → which steps are user vs Leader-orderable
- Subagent asks "should I do X" where X involves ASC web UI
- Drafting a release readiness checklist for user
- User says "I'm about to submit to App Store — what do I need to check"
- Code Reviewer flags an Apple-platform-ops question
- An `ASCRegister apply` run returns `ENTITY_ERROR.<CODE>` → see [`asc-entity-error-recipes.md`](asc-entity-error-recipes.md)

## Canonical doc

`docs/v2/v2.5-readiness.md` is the authoritative ops checklist as of v2.5 (a v2.6 readiness doc should supersede it at submission time). This skill explains WHO does WHAT and HOW; the readiness doc is WHAT'S DONE / OUTSTANDING.

## Operation taxonomy

### 🙋 User-owned (require human + Apple ID + 2FA)

Cannot be subagent-driven. Document in `v2.5-readiness.md` as `- [ ]` items; track via GitHub issue (e.g. #132).

| Op | Where | Notes |
|---|---|---|
| Apple Developer Program enrolment / annual renewal | developer.apple.com | One-time + yearly |
| Generate ASC API Key (.p8 + Key ID + Issuer ID) | App Store Connect → Users and Access → Keys | Required for ASCRegister + Xcode Cloud signing |
| App Privacy questionnaire | ASC web UI → My Apps → Sudoku → App Privacy | No REST API exists (verified 2026-05-23) — must align manually with PrivacyInfo.xcprivacy |
| IAP pricing tier + review screenshot + `Ready to Submit` | ASC → My Apps → … → In-App Purchases | Product creation + per-locale localization are now automated (`ASCRegister iap apply`, see Leader-orderable table); what remains web-UI is the price/availability, the IAP review screenshot, and flipping status to `Ready to Submit` |
| Sandbox tester account | ASC → Users and Access → Sandbox | One per region you want to test |
| AdMob console linkage | apps.admob.com | Link to ASC App ID; create banner ad unit |
| App Store nutrition labels | ASC web UI → App Privacy | Must align with PrivacyInfo |
| TestFlight build promotion to production | ASC → TestFlight → Build → Distribute | Tap "Submit for Review" |
| Apple Review response (rejection / approval) | ASC → App Store → Submission | Reply to Apple's notes |
| Production AdMob ID swap (paired with IAP unit) | `App/Info.plist` GADApplicationIdentifier + `LiveAdMobBridge.swift` Release branch | Triggered AT v2.5.3 submit; must be paired flip (see v2.5-readiness.md §v2.5.3) |

### 🤖 Leader-orderable (via ASCRegister CLI + ASC REST API)

Subagent-driveable. Document as "automated by ASCRegister X mode".

| Op | Tool | Status |
|---|---|---|
| Register Game Center leaderboards (3) | `tools/ASCRegister` | ✅ shipped (v1) |
| Register Game Center achievements (8) | `tools/ASCRegister` | ✅ shipped (v1) |
| Register IAP product | `ASCRegister iap plan\|apply` | ✅ **SHIPPED** — `iap` subcommand creates/updates the IAP from metadata xcstrings (the 2026-05-26 cancellation was later reversed; confirm via `ASCRegister --help`). Requires the ASC app record to already exist (`--app-id`). |
| Upload App Metadata (description / keywords / screenshots / what's new) | `ASCRegister metadata plan\|apply\|set-version\|screenshots` | ✅ **SHIPPED** — `metadata` subcommand uploads listings + screenshots per locale (the 2026-05-26 backlog item was implemented; `screenshots` gated behind `--i-am-sure`). |
| Create the ASC app record itself | — (none) | 🙋 **USER-OWNED** — ASCRegister consumes `--app-id`, it cannot create the app. Register the bundle id (Developer Portal) + create the app in ASC web UI, then feed its app-id to the tools. |

### 🤝 Hybrid (Leader prepares; user pushes the button)

| Op | Leader does | User does |
|---|---|---|
| Xcode Cloud signing | Pin Xcode version in `.mise.toml`; ci_post_clone.sh writes Tuist/Signing.xcconfig from `$CI_TEAM_ID` | One-time: connect ASC to Xcode Cloud, configure team |
| Branch protection on `main` | Methodology doc + workflow yml | Settings → Branches → required status checks |
| GitHub App bot identity (audit-trail clean) | `scripts/bot-gh-token.sh` JWT helper; `.gitignore` + foundations §7 | Create the GitHub App, install on repo, save `.pem` |

## When subagent asks "can I do X for ASC?"

Cross-reference the taxonomy above. If user-owned → respond "this is user step, add to `v2.5-readiness.md` checklist and surface to user". If Leader-orderable → confirm tool exists or scope the CLI extension. If hybrid → split the work in dispatch prompt.

## Documentation pointers

- **`docs/v2/v2.5-readiness.md`** — current ship checklist; user-owned items as `- [ ]`
- **`docs/v2/plan.md` §v2.5** — phase summary; defers to readiness doc for detail
- **`tools/ASCRegister/`** (project source: `Packages/ASCRegisterKit/Sources/ASCRegister/`) — existing CLI
- **`docs/app-store/metadata/README.md`** — yaml schema consumed by ASCRegister metadata mode (shipped)
- **`docs/foundations.md §Backlog`** — ASC API ops backlog entries
- **`docs/v2/design.md §Backlog`** — historical CANCELLED/BACKLOG ASC ops (note: the IAP + metadata modes listed there were later implemented — `ASCRegister --help` is current truth)

## Anti-patterns

- **"IAP is fully automated, no user step"** — NO. `ASCRegister iap apply` creates the product + localizations via the API, but pricing/availability, the IAP review screenshot, and the final `Ready to Submit` flip remain web-UI (user-owned). Automate the creation; hand the rest to the user.
- **"We'll fill App Privacy questionnaire later via API"** — NO. There is no API. Verified 2026-05-23.
- **Shipping with test AdMob IDs in production**: paired flip exists for a reason. Per RCA #149 Fix N1, Release build with test app ID + production ad unit ID will silently no-fill at best.
- **Conflating "ASCRegister handles Game Center" with "ASCRegister handles everything"**: explicit mode-by-mode tracking required. Game Center / IAP / metadata modes are all SHIPPED (`ASCRegister --help` is the source of truth). The one thing ASCRegister does NOT do is create the app record — it consumes `--app-id`, so the ASC app must be created in the web UI first (user-owned).

## Example application

User asks: "Should we automate the v2.5.3 production AdMob ID swap?"

Cross-reference:
- The swap touches `App/Info.plist` + `LiveAdMobBridge.swift` — both source-controlled
- Trigger: user-owned (decides WHEN to flip)
- Execution: Leader-orderable (it's just a 2-file PR)
- Verification: user-owned (TestFlight + real-device test ads run by user per `v2.5-readiness.md §v2.5.2`)

Verdict: hybrid. Recommend: at v2.5.3 user-says-ready, dispatch a subagent to do the 2-file flip in one PR, user merges + uploads TestFlight build.
