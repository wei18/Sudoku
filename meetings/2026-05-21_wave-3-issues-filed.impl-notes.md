# Wave 3 audit findings — filed as GitHub issues

**Date**: 2026-05-21
**Source audits**: Code Reviewer + Architect Wave 3 reports (2026-05-20)
**Leader action**: filed inline after subagent (`af62ddc841ec45e6a`) hit gh permission wall

| Audit code | Issue # | Title |
|---|---|---|
| M1  | #64 | wire or remove dead Persistence + GameCenter infra (5 types) |
| M5  | #65 | replace string-typed mode/difficulty/status crossings with enums |
| M6  | #66 | unify Game Center identifier source across GameCenterClient + ASCRegister |
| M10 | #67 | unified UserFacingError + ErrorReporter funnel |
| M11 | #68 | convert LivePersistence from final class + NSLock to actor |
| M16 | #69 | extract utcDayString shared helper (deduplicate 4 sites) |

## Skipped (intentionally)

- **M4** (RouteFactory) — already promoted to v2.3.3 in `docs/v2/plan.md`; no separate issue needed
- **Other Wave 3 findings** — addressed in Wave 1/2 docs sweep + Wave 2 code fix PRs (#48–#54)

## Follow-ups

- Labels (`wave-3-audit`, `architecture`) not applied — repo doesn't have those custom labels yet. Optional: `gh label create wave-3-audit --color BFD4F2` then bulk `gh issue edit ... --add-label wave-3-audit`
- Milestone: no `v2-stabilization` milestone exists; leaving issues unmilestoned
