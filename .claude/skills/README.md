# Project Skills

> A Traditional Chinese version of this document is available at [`README.zh-TW.md`](README.zh-TW.md).

This directory is the project's self-contained set of agent skills. Every skill used or observed in this project lives here, with no dependency on project-specific entries under the user-level `~/.claude/skills/`.

10 platform defaults split out from the user-level `~/.claude/skills/swift-platform-defaults`, plus 7 process / security skills distilled from this session — **17** skills in total.

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
| [`spec-phase-orchestration`](spec-phase-orchestration/SKILL.md) | 6 files (README + foundations / design / plan / methodology + meetings/); section-by-section; prerequisite gate; no code before spec |
| [`backlog-routing-by-topic`](backlog-routing-by-topic/SKILL.md) | Route stray ideas by topic to the matching file's §Backlog (gameplay / tooling / implementation / collaboration / fallback to meeting log) |
| [`apple-public-repo-security`](apple-public-repo-security/SKILL.md) | Three lines of defence for public iOS / macOS repos (lefthook + gitleaks / Xcode Cloud post-clone / GitHub Secret Scanning) + rotate-first leak SOP |
| [`leader-developer-handoff-contract`](leader-developer-handoff-contract/SKILL.md) | 5 required elements when dispatching a sub-agent: scope / inputs / skills / return format / verification |

---

## Why these skills live in the repo rather than at the user level

- **The repo is public from day 1**, and this skill set is part of the "Claude agent application record" showcase.
- **Reproducibility**: any reader who clones gets the same collaboration framework out of the box.
- **Transparent evolution**: skills evolve with the project, and PRs leave a diff trail.

If a skill later proves applicable across multiple Apple-platform projects, the plan is to promote it back to the user level.
