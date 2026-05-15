# Project Skills

> 本文件的英文版本見 [`README.md`](README.md)。

本目錄為本專案自含（self-contained）的 agent skill 集合。所有在本專案中使用 / 觀察到的 skill 都放這裡，不依賴 user-level `~/.claude/skills/` 的 project-specific 條目。

從 user-level `~/.claude/skills/swift-platform-defaults` 拆出的 10 條平台預設、加上 7 條本 session 觀察到並沉澱出的流程 / 安全 skill，共 **17** 條。

---

## 平台預設 (10)

從原 `swift-platform-defaults` skill 的 §1–§10 各自抽出一條獨立 skill。

| Skill | 一句話 |
|---|---|
| [`swift6-concurrency`](swift6-concurrency/SKILL.md) | Swift 6 語言模式 + complete concurrency checking；Sendable 預設；`@preconcurrency` 為 escape hatch |
| [`apple-platform-targets`](apple-platform-targets/SKILL.md) | 預設 iOS 18 / macOS 15、Xcode 16+；採 Liquid Glass / 最新 API 才上調至 26 |
| [`swiftpm-modularization`](swiftpm-modularization/SKILL.md) | 單 Package 多 target、薄 App、DI composition root、framework import 受限、一對一 test target |
| [`swift-testing-baseline`](swift-testing-baseline/SKILL.md) | swift-testing（不用 XCTest）+ pointfreeco snapshot；protocol fakes；snapshot 進 git；CI Xcode 鎖版 |
| [`xcode-cloud-single-track-ci`](xcode-cloud-single-track-ci/SKILL.md) | 單軌 Xcode Cloud；4 workflow（PR / Main / Release / Periodic）；PR CI 啟用 pre-merge |
| [`mise-tool-management`](mise-tool-management/SKILL.md) | mise 管 binary CLI；開發機 + CI 共用 `.mise.toml` |
| [`oslog-logger-defaults`](oslog-logger-defaults/SKILL.md) | `os.Logger`（不引第三方）；subsystem = bundle ID、category = module name；`.private` 預設 |
| [`apple-three-piece-analytics`](apple-three-piece-analytics/SKILL.md) | ASC Analytics + MetricKit + Game Center；不引第三方 tracking；`PrivacyInfo.xcprivacy` 必交付 |
| [`telemetry-facade-pattern`](telemetry-facade-pattern/SKILL.md) | 單一 `Telemetry` target、fan-out facade；OSLog / NoOp tracking / MetricKit / GameCenter sink |
| [`ai-translated-localization`](ai-translated-localization/SKILL.md) | 預設 7 locale（zh-TW、en、ja、zh-CN、es、th、ko）；AI 翻譯流程；`Localizable.xcstrings`；最小集 zh-TW + en |

---

## 流程與安全 (7)

從本 session 觀察到的協作 / 安全 pattern 沉澱出。

| Skill | 一句話 |
|---|---|
| [`session-to-meeting-log`](session-to-meeting-log/SKILL.md) | 把 Claude Code session JSONL 整理成 `meetings/{date}_{topic}.md`；摘要、非 verbatim |
| [`methodology-pattern-extractor`](methodology-pattern-extractor/SKILL.md) | 從 meeting log 抽出 ≥ 3 次重複的 pattern，追加至 `methodology.md §Patterns` |
| [`subagent-review-cycles`](subagent-review-cycles/SKILL.md) | Leader / Developer / Code-Reviewer 三角；round 1 cosmetic inline edit；limit(N) |
| [`spec-phase-orchestration`](spec-phase-orchestration/SKILL.md) | 6 file（README + foundations / design / plan / methodology + meetings/）；section-by-section；prerequisite gate；無 spec 不寫 code |
| [`backlog-routing-by-topic`](backlog-routing-by-topic/SKILL.md) | 散落想法依主題 route 到對應檔 §Backlog（玩法 / 工具 / 實作 / 協作 / fallback meeting log）|
| [`apple-public-repo-security`](apple-public-repo-security/SKILL.md) | Public iOS / macOS repo 三道防線（lefthook + gitleaks / Xcode Cloud post-clone / GitHub Secret Scanning）+ leak rotate-first SOP |
| [`leader-developer-handoff-contract`](leader-developer-handoff-contract/SKILL.md) | 派發 sub-agent 的 5 要件：scope / inputs / skills / return format / verification |

---

## 為什麼這些 skill 在 repo 內、而非 user-level

- **Repo 從 day 1 即 public**，這份 skill 集合是「Claude agent 應用紀錄」案例展示的一部分。
- **可重現性**：任何讀者 clone 後即取得同一套協作框架。
- **演進透明**：skill 隨專案演進、PR 留下 diff 紀錄。

未來若某條 skill 證明在多個 Apple 平台專案皆適用，可考慮 promote 回 user-level。
