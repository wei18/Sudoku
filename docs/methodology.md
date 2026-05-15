# Claude Agent 方法論 — Sudoku 專案

狀態：**LIVING DOCUMENT** — 隨真實模式浮現逐步補上。
最後更新：2026-05-15

本文件記錄 Claude agent 在 Sudoku 專案中的應用方式。起步時刻意保持精簡，模式真的出現後（透過 `meetings/` 與已完成里程碑）才向下生長。

---

## 運作模式

- **AI Collaboration Mode**（Leader / Developer 雙角色），完整定義見 `~/.claude/skills/ai-collaboration-mode/SKILL.md`。
- **Spec-first**：`design.md` 與 `plan.md` 未通過前不寫實作程式碼。
- **TDD**：`plan.md` 的實作步驟以「先寫測試」的順序排列。
- **Meeting log 是證據**：每次工作 session 結束後更新對應的 `meetings/{YYYY-MM-DD}_{topic}.md`。結晶過的決策搬進 `design.md`；原始上下文留在 meeting log。

## 角色分工

### 主 agent（current session）= **PM + Lead**

- 負責：理解使用者意圖、決策、撰寫 / 審核文件、派發任務、整合產出。
- **不直接寫實作程式碼**。實作一律派發 sub-agent。
- 文件層的編輯（design / plan / methodology / foundations / meeting logs）由主 agent 親自進行 — 因為這是「決策結晶」的最後一里。

### Sub-agent roster

| 角色 | 主要 skill kit | 派發時機 |
|---|---|---|
| **Developer** | `swift6-concurrency`、`swiftpm-modularization`、`swift-testing-baseline`、`swiftui-expert-skill`、`superpowers:test-driven-development`、`superpowers:systematic-debugging`、`andrej-karpathy-skills:karpathy-guidelines` | 任何寫 / 改 / refactor Swift 程式碼；TDD 步驟執行；除錯 |
| **Designer** | `ui-ux-pro-max:ui-ux-pro-max`、`swiftui-expert-skill`（Liquid Glass / 視覺實作部分） | View mockup、配色 / 字型決策、互動模式選擇；產出設計後再交 Developer 落地 |
| **Code reviewer** | `superpowers:requesting-code-review`（主 agent 端）、receiving 端在原 Developer subagent 內處理 | 模組初版完成、PR 前 |

### 派發契約

每次派發 sub-agent，主 agent 必須給出：
1. **任務 scope**：明確的可驗證目標（檔案、模組、行為）。
2. **依賴文件**：應該讀哪些 `docs/` 與 `meetings/` 章節。
3. **skill 指定**：明確列出該 sub-agent 應 invoke 的 skill。
4. **回傳格式**：實作 diff、設計稿、或文字決策。
5. **驗證標準**：通過什麼測試 / 達到什麼條件才算完成。

Sub-agent 回傳後由主 agent 審核，**通過審核才向使用者報告**。


## Agent skills 使用矩陣

每一個 skill 列出**使用時機**（觸發條件）與**對應到本專案的工作**。實際 session 中只要觸發條件成立，先 invoke skill，再執行。

### 常駐 / 全程沿用

| Skill | 為什麼是常駐 |
|---|---|
| `ai-collaboration-mode`（自家）| 整個專案的運作框架；session 啟動即套用 |
| `andrej-karpathy-skills:karpathy-guidelines` | 透過 `~/CLAUDE.md` 強制掛載；任何寫 / 改 / refactor 程式碼時生效 |

### Spec 階段

| Skill | 使用時機 | 對應工作 |
|---|---|---|
| `superpowers:brainstorming` | 開新主題、新 feature、要決定 backlog 是否升級進 design 前 | 每次 spec / design 章節的 section-by-section 推進 |
| `superpowers:writing-plans` | `design.md` 某節通過後，要把它變成 `plan.md` 步驟 | 緊接 spec phase 結束、進入實作前 |
| `superpowers:writing-skills` | 觀察到反覆出現的 pattern，想沉澱成 reusable skill 時 | 當 `methodology.md` 觀察到第 3 次同樣動作時 |

### 實作階段（v1 進入後）

主 agent 派發到 Developer subagent，主 agent 自己**不直接執行**。

| Skill | 屬於 | 使用時機 |
|---|---|---|
| `superpowers:test-driven-development` | Developer | 每個 `plan.md` 步驟動工前；對應本專案的 TDD 強制原則 |
| `superpowers:systematic-debugging` | Developer | 遇到任何 bug 或 test 失敗，**動手修之前** |
| `superpowers:executing-plans` | 主 agent → Developer | `plan.md` 寫好後，進入逐步執行模式 |
| `superpowers:subagent-driven-development` | 主 agent | `plan.md` 內有獨立子任務、要在同一 session 派發 |
| `superpowers:dispatching-parallel-agents` | 主 agent | 兩個以上獨立、無共享狀態的任務（例：snapshot 重做、CloudKit ingest CLI 撰寫）|
| `superpowers:using-git-worktrees` | 主 agent | 開新 feature branch、或要 parallel 工作 |
| `superpowers:verification-before-completion` | Developer 自驗 + 主 agent 把關 | 宣告「做完了」之前；每個 PR 合併前、每個 task 結案前 |
| `superpowers:requesting-code-review` | 主 agent | 模組初版完成、合併前 |
| `superpowers:receiving-code-review` | Developer | 收到 review 意見後、動手改之前 |
| `superpowers:finishing-a-development-branch` | 主 agent | 完成一條 feature，要決定 merge / PR / cleanup |
| `swiftui-expert-skill` | Developer / Designer | 寫 / review / refactor SwiftUI 程式碼；分析 hang / hitch / CPU / view updates（Instruments .trace）|
| `swift6-concurrency` / `apple-platform-targets` / `swiftpm-modularization` / `swift-testing-baseline` / `xcode-cloud-single-track-ci` / `mise-tool-management` / `oslog-logger-defaults` / `apple-three-piece-analytics` / `telemetry-facade-pattern` / `ai-translated-localization` | Developer | 寫 `Package.swift` / `.mise.toml` / Xcode Cloud workflow；做 Swift 6 / SwiftPM / 測試 / CI / Logger / Tracking / L10n 決策時，按主題挑相關條目 invoke |
| `apple-public-repo-security` | Developer / Main agent | 編輯 .gitignore / 引入新 secret / 設 lefthook+gitleaks / 寫 CI ci_post_clone.sh / 模擬 leak SOP 時 |
| `ui-ux-pro-max:ui-ux-pro-max` | Designer | View mockup、配色 / 字型 / 互動決策 |

### 排除（v1 不使用）

| Skill | 排除理由 |
|---|---|
| `claude-mem:make-plan` / `do` | 與 `superpowers:writing-plans` / `executing-plans` 功能重疊；二擇一以避免兩套 plan 體系（見 `foundations.md §8`）|
| `claude-mem:wowerpoint` / `timeline-report` | 非流程必需，需要時手動叫 |
| `claude-hud:setup` / `update-config` / `keybindings-help` / `fewer-permission-prompts` | 環境調校類，不直接服務專案 |
| 各種行業領域專家（China e-commerce / healthcare / real estate …）| 與專案不相關 |

---

## 累積中的模式（Patterns）

### Pattern: Section-by-section approval before next section

- **Trigger**: 主 agent 要產出多節文件（design.md / foundations.md），且使用者要求逐節推進
- **Action**: Leader 一次只草擬一節（§What → §How.1 → §How.2 …），每節等使用者明確 OK 才進下一節；未通過則回到該節 draft 重做，而非整檔重寫
- **Outcome**: design.md §What 與 §How.1–§How.7 全部以節為單位順序通過；foundations.md §1–§7 同樣以節為單位推進；單節 reject 不會牽動已通過的章節
- **Next-time adjustment**: 進入每節前先列出該節的 prerequisite checklist，避免到 review 階段才發現依賴未解；formal 版本見 `spec-phase-orchestration` skill
- **Sightings**: design.md §What、§How.1、§How.2、§How.3、§How.4、§How.5、§How.6、§How.7 共 8 次節為單位推進（2026-05-15）

### Pattern: Subagent review cycles with limit(N)

- **Trigger**: 大型結構性章節（design.md §How.3 GC / §How.4 題庫 / §How.5 View / §How.6 Error / §How.7 Test）需要技術深度的 draft 或對抗式審查
- **Action**: Leader 派 Developer subagent 草擬 → 派 Code Reviewer subagent（禁 CLI、可 WebSearch）對抗式審查 → Leader 收回，按 BLOCKER/MAJOR/MINOR 逐條 ACCEPT/REJECT；設定 round 上限 10，但「上限不是要求」，實際 §How.3–§How.7 各節皆 round 1 即通過
- **Outcome**: Round 1 產出 7 BLOCKER / 11 MAJOR / 7 MINOR；24/25 ACCEPT；Round 2 進一步抓到 1 regression + 2 new issues（§How.7.1 technique 數未同步 descope、`GameCenterSink` 把 Practice 成就擋掉、§How.5.1 與 §How.3.4 `.task` 衝突）
- **Next-time adjustment**: Round 1 後固定再排 Round 2 對「修正後的 diff」做 regression sweep，不要假設 round 1 ACCEPT = 完工；formal 版本見 `subagent-review-cycles` skill
- **Sightings**: §How.3 round 1、§How.4 round 1、§How.5 round 1、§How.6 round 1、§How.7 round 1、Code Reviewer round 2 regression sweep（2026-05-15，共 6 次）

### Pattern: Prerequisite checklist with Unconfirmed / Resolved gates

- **Trigger**: subagent 提案內含外部工具、API、第三方套件、環境權限的依賴（CloudKit schema / Xcode Cloud `ci_scripts` / `forceReplace` 行為 / solver tier 可行性 / lefthook mise plugin / gitleaks 自訂規則）
- **Action**: 提案內列 prerequisite checklist，每條標 Unconfirmed ? 或 Resolved ✓；Unconfirmed 條目阻擋 Leader approval；可在當 session 內研究釐清升為 Resolved，或留到 plan.md 階段驗證
- **Outcome**: §How.4.9 4 條 prerequisite 中 2 條（`forceReplace` 行為、solver 可行性）當場 Resolved；2 條（Xcode Cloud `ci_scripts` 環境、排程 UTC 對齊）留 plan.md；foundations §7.11 將 `ci_pre_xcodebuild.sh` hook 命名 / lefthook mise plugin / gitleaks 自訂規則 3 條 Open items 同樣留 plan.md
- **Next-time adjustment**: prerequisite 在 draft 階段就由 Developer 自填，避免 reviewer 才補；formal 版本見 `ai-collaboration-mode` SKILL.md 的 prerequisite 規則
- **Sightings**: §How.4.9 prerequisite gate、foundations §7.11 Open items、CloudKit schema 演進策略 prerequisite（2026-05-15，共 3 次以上）

### Pattern: Leader inline-applies round-1 cosmetic fixes

- **Trigger**: Code Reviewer 或自查發現的問題屬於小幅編輯（單行改字、章節順序調整、漏標 Sendable、descope 後章節未同步、scenePhase 行為微調），不值得消耗一輪 subagent round
- **Action**: Leader 直接在文件上 inline 編輯，不再派 Developer 重跑一輪；只有結構性 / 行為性大改才回 IMPL_DRAFT
- **Outcome**: §How.3–§How.7 各節皆 round 1 通過，符合「limit 是上限不是要求」精神；24 條 round 1 修正全部由 Leader 直接套用；OS Floor 拉至 iOS 26 / macOS 26、GC achievement 砍至 8 個 550 點、`PersistenceProtocol: Sendable` 顯式宣告 等均為 inline 修正
- **Next-time adjustment**: 訂出「inline 直接改 vs. 回 Developer round」的判準（行數 / 是否動到契約 / 是否需要重跑測試）；formal 版本見 `subagent-review-cycles` skill 的 round-1 cosmetic-grade 條款
- **Sightings**: round 1 24/25 inline 套用、round 2 三條 regression 全 inline 修、foundations §7 secrets 章節順序 inline 調整（原 §7 變 §8）（2026-05-15，共 3 次以上）

### Pattern: Backlog routing for stray ideas during focused work

- **Trigger**: 在 spec phase 專注討論某節時，浮現與當下節無關但有價值的想法（GitHub Actions 雙軌、achievement v2 候選、ADR、xWing/swordfish solver、技術細項…）
- **Action**: 不就地展開，依主題路由：產品想法 → design.md §Backlog；工程基礎 → foundations.md §Backlog；實作步驟 → plan.md §Backlog；協作流程 → methodology.md §Backlog；無法分類 → 當天 meeting log §未決問題
- **Outcome**: 「GitHub Actions 雙軌」入 foundations §4 backlog、「achievement v2 候選 `daily.streak_30` / `practice.complete_500`」入 design §Backlog、「8-file 文件結構」改 6-file 後其餘想法入 backlog、xWing/swordfish/xyWing 整體延後 v2 入 design §Backlog
- **Next-time adjustment**: 每次 session 結束前掃一次當天 backlog 增量，確認沒有遺漏；formal 版本見 `backlog-routing-by-topic` skill
- **Sightings**: foundations §4 GH Actions backlog、design §How.3 achievement v2 backlog、design §How.4 solver tier v2 backlog、文件結構 8→6 簡化（2026-05-15，共 4 次以上）

### Pattern: Foundations.md update triggered by mid-session new requirement

- **Trigger**: 使用者在 session 進行中追加先前未提的需求或承諾，影響工程基礎決策（v1 public repo from day 1、secrets 控管、OS floor 拉高、不引第三方 tracking）
- **Action**: Leader 暫停當下 section 推進，先把新需求落到 foundations.md 對應節（必要時開新節並重排章節順序），確認影響範圍與下游章節同步，才回到原推進線
- **Outcome**: 「public repo from day 1」觸發新增 foundations §7 Secrets 完整 9 小節（原 §7 Agent skills 順位後移為 §8）；OS floor iOS 18→26 / macOS 15→26 同步改 foundations §1、§2 Package、design §What、保留 swift-platform-defaults skill 為 deviation；tracking 決策落 foundations §6 Apple 三件套
- **Next-time adjustment**: session 開始前先問一次「有沒有任何尚未提的承諾／約束」，降低中途追加導致章節重排的機率
- **Sightings**: foundations §7 Secrets 新增、OS floor 拉高同步多檔、foundations §6 Apple 三件套 + NoOp TrackingSink 取代 TelemetryDeck/Firebase（2026-05-15，共 3 次）

## 觀察到的反模式（Anti-patterns）

_試過、發現不適合的做法寫在這裡，附上首次出現的 meeting log 連結。_

---

## §Backlog

_討論過程中浮現的協作模式、流程改善想法。每條一行。_
