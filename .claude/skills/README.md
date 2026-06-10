# Project Skills

> A Traditional Chinese version of this document is available at [`README.zh-TW.md`](README.zh-TW.md).

This directory is the project's self-contained set of agent skills. Every skill used or observed in this project lives here, with no dependency on project-specific entries under the user-level `~/.claude/skills/`.

10 platform defaults split out from the user-level `~/.claude/skills/swift-platform-defaults`, plus 21 process / security / ops skills distilled from this session — **31** skills in total.

---

## Platform defaults (10)

One independent skill per section, extracted from §1–§10 of the original `swift-platform-defaults`.

| Skill | One-liner |
|---|---|
| [`swift6-concurrency`](swift6-concurrency/SKILL.md) | Swift 6 language mode + complete concurrency checking; Sendable by default; `@preconcurrency` as escape hatch |
| [`apple-platform-targets`](apple-platform-targets/SKILL.md) | Default iOS 18 / macOS 15, Xcode 16+; bump to 26 only when adopting Liquid Glass / latest-OS-only APIs |
| [`swiftpm-modularization`](swiftpm-modularization/SKILL.md) | Single Package, multiple targets, thin App, DI composition root, restricted framework imports, one-to-one test targets |
| [`swift-testing-baseline`](swift-testing-baseline/SKILL.md) | swift-testing (no XCTest) + pointfreeco snapshot; protocol fakes; snapshots in git; CI Xcode locked |
| [`xcode-cloud-single-track-ci`](xcode-cloud-single-track-ci/SKILL.md) | Single-track Xcode Cloud; 4 workflows (PR / Main / Release / Periodic); PR CI with pre-merge enabled |
| [`mise-tool-management`](mise-tool-management/SKILL.md) | mise manages binary CLI tools; dev machine + CI share `.mise.toml` |
| [`oslog-logger-defaults`](oslog-logger-defaults/SKILL.md) | `os.Logger` (no third-party); subsystem = bundle ID, category = module name; `.private` default |
| [`apple-three-piece-analytics`](apple-three-piece-analytics/SKILL.md) | ASC Analytics + MetricKit + Game Center; no third-party tracking; `PrivacyInfo.xcprivacy` mandatory |
| [`telemetry-facade-pattern`](telemetry-facade-pattern/SKILL.md) | A single `Telemetry` target, fan-out facade; OSLog / NoOp tracking / MetricKit / GameCenter sinks |
| [`ai-translated-localization`](ai-translated-localization/SKILL.md) | Default 7 locales (zh-TW, en, ja, zh-CN, es, th, ko); AI translation flow; `Localizable.xcstrings`; minimum set zh-TW + en |

---

## Process & security (7)

Distilled from collaboration / security patterns observed in this session.

| Skill | One-liner |
|---|---|
| [`session-to-meeting-log`](session-to-meeting-log/SKILL.md) | Consolidate Claude Code session JSONL into `meetings/{date}_{topic}.md`; summary, not verbatim |
| [`methodology-pattern-extractor`](methodology-pattern-extractor/SKILL.md) | Extract patterns recurring ≥ 3 times from meeting logs; append to `methodology.md §Patterns` |
| [`subagent-review-cycles`](subagent-review-cycles/SKILL.md) | Leader / Developer / Code-Reviewer triad; round-1 cosmetic inline edits; limit(N) |
| [`spec-phase-orchestration`](spec-phase-orchestration/SKILL.md) | 5 files + meetings/（README + foundations / design / plan / methodology）; section-by-section; prerequisite gate; no code before spec |
| [`backlog-routing-by-topic`](backlog-routing-by-topic/SKILL.md) | Route stray ideas by topic to the matching file's §Backlog (gameplay / tooling / implementation / collaboration / fallback to meeting log) |
| [`apple-public-repo-security`](apple-public-repo-security/SKILL.md) | Three lines of defence for public iOS / macOS repos (lefthook + gitleaks / Xcode Cloud post-clone / GitHub Secret Scanning) + rotate-first leak SOP |
| [`leader-developer-handoff-contract`](leader-developer-handoff-contract/SKILL.md) | 5 required elements when dispatching a sub-agent: scope / inputs / skills / return format / verification |

---

## Ops, review & process (14)

Workflow, review-discipline, monetization, ASC/icon ops, and mockup skills added as the project matured.

| Skill | One-liner |
|---|---|
| [`agent-impl-notes-log`](agent-impl-notes-log/SKILL.md) | Running `meetings/{date}_{topic}.impl-notes.md` during a sub-agent task — in-flight decisions, deviations, alternatives, open questions |
| [`pr-diff-verification`](pr-diff-verification/SKILL.md) | Before push / PR, verify `git show --stat HEAD` matches what the commit message claims |
| [`subagent-conflict-detection`](subagent-conflict-detection/SKILL.md) | Before dispatch, check the new sub-agent's target files don't overlap an in-flight sub-agent's worktree |
| [`swiftui-interaction-footguns`](swiftui-interaction-footguns/SKILL.md) | Checklist of known SwiftUI interaction bugs that slip past pure-code review (tap-target, safe-area, sizeClass, `.task` re-fire) |
| [`build-time-secret-injection`](build-time-secret-injection/SKILL.md) | xcconfig + Info.plist `$()` + `Bundle.main` for ship-in-binary-but-out-of-PR-diff IDs (AdMob / ASC `.p8`) |
| [`monetization-sdk-integration`](monetization-sdk-integration/SKILL.md) | Add / upgrade / audit any third-party monetization SDK; isolate `import GoogleMobileAds` to the live-bridge file |
| [`asc-ops-handoff`](asc-ops-handoff/SKILL.md) | Which App Store Connect / TestFlight steps are user-owned vs Leader-orderable via the ASC API + ASCRegister |
| [`app-icon-rasterize`](app-icon-rasterize/SKILL.md) | Rasterize a 1024 SVG app icon to the asset-catalog PNG via `qlmanage` — no Homebrew / cloud dependency |
| [`ios-design-mockup`](ios-design-mockup/SKILL.md) | Single-file HTML iOS design mockup from a spec — iPhone frames + SVG nav arrows + design-token panel |
| [`mise-task-operations`](mise-task-operations/SKILL.md) | Index / entry point for every repo ops task — before grepping "how is X done", check here; maps each `mise run` task → invocation + safety gate + owning skill |
| [`local-testflight-upload`](local-testflight-upload/SKILL.md) | Local archive→export→TestFlight via `mise run tf:upload`; temporary Xcode-Cloud-Main-CI substitute; upload gated behind `--i-am-sure` |
| [`cloudkit-schema-ops`](cloudkit-schema-ops/SKILL.md) | Export / validate / deploy CloudKit schema via `mise run ck:schema` (`xcrun cktool`); `.ckdb` source of truth; Production promote = CloudKit Console-only (user-owned) |
| [`appstore-screenshot-pipeline`](appstore-screenshot-pipeline/SKILL.md) | Sync App Store screenshot PREVIEWS from snapshot baselines via `mise run store:screenshots`; symlink-based, PREVIEW-ONLY (not ASC submission-spec) |
| [`acknowledgements-generation`](acknowledgements-generation/SKILL.md) | Regenerate Settings.bundle Acknowledgements from the SwiftPM dep graph via `mise run gen:acknowledgements` (LicensePlist); output gitignored |

> The `superpowers/` directory is a git **submodule** (`obra/superpowers`), not a checked-out skill set — a normal clone leaves it empty. Run `git submodule update --init` to populate it; its skills are not catalogued here.

---

## Why these skills live in the repo rather than at the user level

- **The repo is public from day 1**, and this skill set is part of the "Claude agent application record" showcase.
- **Reproducibility**: any reader who clones gets the same collaboration framework out of the box.
- **Transparent evolution**: skills evolve with the project, and PRs leave a diff trail.

If a skill later proves applicable across multiple Apple-platform projects, the plan is to promote it back to the user level.
