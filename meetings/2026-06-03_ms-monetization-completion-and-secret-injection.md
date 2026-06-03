# 2026-06-03 — MS monetization completion + AdMob secret injection

Session id: `d096397c-c7cc-4644-b604-bd787b1e3ed0`
Mode: AI Collaboration Mode (Leader / Developer / Code Reviewer triad)

## Goal

Close the Minesweeper monetization mirror loop (Phase 3 → U15 banner wire), absorb the day's spec changes (AdGate grace period inverted), then design + land PR1 of an AdMob secret-injection migration that replaces hardcoded prod IDs + `fatalError` gates with xcconfig + Info.plist substitution.

## Decisions

1. **MS monetization wire — Option A (full mirror)**: Minesweeper gets the same monetization stack as Sudoku (AdMob + Remove Ads IAP). Confirmed Phase 1.a (extracted MonetizationUI, PR #249 from 2026-06-02) was the right move; built Phase 2 + 3 + U15 on top: PRs #257 (PrivateCKConfig.minesweeper), #258 (multi-app IAP config), #259 (AppComposition.Live wire + Settings rows), #263 (LiveAdMobAdProvider iOS + NoopAdProvider macOS + BoardView banner + toast overlay).
2. **AdGate `gracePeriodDays` spec INVERTED**: previous spec said "first-7-days no ads"; user changed mid-session to "banner always shows from first launch". Code keeps `gracePeriodDays = 0` permanently; docs/v2/design.md row #6/#7 updated; docs/privacy-policy.md user-facing copy updated to match shipped behaviour. PR #256.
3. **App Store product names stay short**: ASC display name = `Sudoku` / `Minesweeper`. Earlier proposal of `Let's play Sudoku` reversed by user same day. Memory entry deleted; no ASC edits needed.
4. **`scrub-prod-secrets-from-comments` rule**: production AdMob / ASC / etc. IDs MUST NOT appear in code comments, docstrings, or Info.plist explanatory blocks — only memory file names. Triggered by PR #263 incident (Info.plist comment leaked MS production App ID). Hot-fix PR #264 + memory entry + new feedback rule.
5. **AdMob secret injection — Option E hybrid (per Architect review) compressed to PR1**: Architect recommended xcconfig (App ID) + build-phase codegen (Banner Unit ID); Leader/user accepted Architect's xcconfig+Info.plist mechanism but dropped the codegen layer in favor of `Bundle.main` reads + runtime guard. 7-PR plan compressed to 3; PR1 (#265) landed scaffolding + Info.plist substitution + Live.swift Bundle.main migration + smoke tests + ci_post_clone.sh extension + secrets/ scaffolding. Mirrors existing `Tuist/Signing.xcconfig` precedent.
6. **Secrets store lives `<repo>/secrets/` (in-repo, gitignored)**, NOT `~/.config/wei18-secrets/`. User explicitly preferred in-tree to ease "fresh clone" onboarding. Deny-by-default inner gitignore with allowlist for `*.example` + `README.md`.
7. **`.env.example` doubles as documentation** — explicit README in `secrets/` instead of relying solely on `.example` docstring, since the layer-2 (.env for CLI) covers more than build-time secrets and needed `.p8` placement guidance.
8. **`build-time-secret-injection` skill landed**: codifies the xcconfig + Info.plist pattern + multi-app `CI_PRODUCT` dispatch + smoke-test-vs-runtime-guard layered safety net. CR'd and revised — leads with "Use when…" per CSO rule, includes Iron Law disclosure (skill shipped without TDD baseline), rationalizations table, verification checklist.
9. **Skill writing-skills Iron Law violated** when `build-time-secret-injection` was first written; partially remediated via post-hoc CR + content overhaul. Future skills must go through `superpowers:writing-skills` flow first.

## Rejected alternatives

- **xcconfig `$()` interpolation from shell env vars** — Architect verified Apple's xcconfig does NOT read process env; only positional `xcodebuild VAR=value` or `-xcconfig override.xcconfig` injects. Plan would have silently failed.
- **GitHub Secrets as the secret store** — XCC doesn't read GH Secrets; the two are separate storage. Would not propagate to Xcode Cloud builds.
- **`Bundle.main.object(...) as! String` force-cast** — SwiftLint rejected; replaced with `guard let ... as? String` + checks for empty + literal `$(...)` token + `preconditionFailure`.
- **`build-phase script + Generated/AdMobConfig.swift` codegen** (Architect's compile-time-safe recommendation) — accepted marginal safety loss in exchange for simpler PR scope and closer mirror of existing Signing precedent.
- **`Let's play Sudoku` / `Let's play Minesweeper` as App Store names** — user reversed same day after testing the cognitive load.
- **Phase 3 ASC app-level metadata implementation today** — deferred. Requires Phase 1.b pricing + app description copy decisions that user did not want to make today.
- **Skill kept solo (no review)** — user explicitly pushed back ("who did you review with?") and required Code Reviewer adversarial pass.

## Hand-offs

### Sub-agents dispatched (this session)
- **PR1 (#257) PrivateCKConfig.minesweeper** — Senior Dev + tests
- **PR2 (#258) Multi-app IAP Config + xcstrings** — Senior Dev (stalled at verification, Leader finished)
- **PR3 (#259) MS AppComposition.Live wire** — Senior Dev (1 round CR ACCEPT, Leader inline-applied cosmetic)
- **PR4 (#263) U15 LiveAdMobAdProvider** — Senior Dev (1 round CR NEEDS_WORK on production App ID in Info.plist, fixed inline)
- **PR5 (#256) AdGate grace period spec inversion** — Leader-direct (mirror principle + privacy-policy update)
- **AdMob secret-injection design** — Architect for adversarial review (NEEDS_REVISIONS → Option E hybrid recommended)
- **PR6 (#265) AdMob xcconfig PR1 scaffolding** — Senior Dev + 1 round CR ACCEPT with cosmetics (Leader inline)
- **`build-time-secret-injection` SKILL CR** — Code Reviewer (NEEDS_WORK → full rewrite landed)
- **PR1 (#265) code CR** — Code Reviewer (ACCEPT with cosmetics + 2 backlog issues)

### Issues filed
- #260 toast overlay on MinesweeperRoot (deferred follow-up)
- #261 FakePersistence for MS Preview (backlog architecture)
- #262 Hardened MS productId test (backlog testing)
- #266 Scrub pre-existing prod IDs in docs/ + meetings/
- #267 AppInfo.plist drift risk between test resources and real Info.plist

## Open questions

- **MS persistence wire**: PrivateCKConfig.minesweeper exists (PR #257) and Live.swift wires LivePersistence with it, but user has NOT deployed MS CloudKit Production schema via Dashboard. MS will fail Production CK writes until the user runs the equivalent of the Sudoku CK schema deploy walked through 2026-06-02.
- **MS ASC app-level metadata (Phase 3)**: ASCRegister extension to push app description / keywords / what's new / screenshots / age rating not yet built. Required for MS v1 submission. Decision deferred.
- **Theme tokens for Minesweeper**: parity audit flagged Theme lives in SudokuUI; MS uses SwiftUI defaults. User said wait for designer input.
- **Daily / Practice content for Minesweeper**: hub shells extracted to GameShellKit (PR #251), but MS stubs render dummy data. Real product definition (what is "today's Minesweeper Daily"?) deferred.

## Next session

Land the user-side post-merge ops for PR #265 (already partially done: local secrets/.env filled, .p8 moved into secrets/, AdMob.xcconfig copied from .example). Then either: (a) PR2 of secret-injection migration (build-phase substitution-resolution check + gitleaks rule for AdMob ID format), (b) Phase 3 ASC app-level metadata for ASCRegister, or (c) attack the backlog issues filed today.
