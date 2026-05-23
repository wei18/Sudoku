# Claude Agent 方法論 — Sudoku 專案

狀態：**LIVING DOCUMENT** — 隨真實模式浮現逐步補上。
最後更新：2026-05-19（v1 codebase feature-complete 後同步）

本文件記錄 Claude agent 在 Sudoku 專案中的應用方式。起步時刻意保持精簡，模式真的出現後（透過 `meetings/` 與已完成里程碑）才向下生長。

---

## 運作模式

- **AI Collaboration Mode**（Leader / Developer 雙角色），完整定義見 `~/.claude/skills/ai-collaboration-mode/SKILL.md`。
- **Spec-first**：`docs/v1/design.md` 與 `plan.md` 未通過前不寫實作程式碼。
- **TDD**：`plan.md` 的實作步驟以「先寫測試」的順序排列。
- **Meeting log 是證據**：每次工作 session 結束後更新對應的 `meetings/{YYYY-MM-DD}_{topic}.md`。結晶過的決策搬進 `docs/v1/design.md`；原始上下文留在 meeting log。

## 角色分工

### 主 agent（current session）= **PM + Lead**

- 負責：理解使用者意圖、決策、撰寫 / 審核文件、派發任務、整合產出。
- **不直接寫實作程式碼**。實作一律派發 sub-agent。
- 文件層的編輯（design / plan / methodology / foundations / meeting logs）由主 agent 親自進行 — 因為這是「決策結晶」的最後一里。

### Sub-agent roster

| 角色 | 主要 skill kit | 派發時機 |
|---|---|---|
| **Developer** / **Senior Developer** | `swift6-concurrency`、`swiftpm-modularization`、`swift-testing-baseline`、`swiftui-expert-skill`、`superpowers:test-driven-development`、`superpowers:systematic-debugging`、`andrej-karpathy-skills:karpathy-guidelines` | 任何寫 / 改 / refactor Swift 程式碼；TDD 步驟執行；除錯。Senior Developer 用於需要 architecture judgement 的 module-level 落地（Phase 7 GameCenterClient、ASC API CLI） |
| **Designer** | `ui-ux-pro-max:ui-ux-pro-max`、`swiftui-expert-skill`（Liquid Glass / 視覺實作部分） | View mockup、配色 / 字型決策、互動模式選擇；產出設計後再交 Developer 落地 |
| **Code reviewer** | `superpowers:requesting-code-review`（主 agent 端）、receiving 端在原 Developer subagent 內處理 | 模組初版完成、PR 前；亦用於 cross-doc consistency sweep（§8.11 amendment 後的 docs/** 路徑/狀態對齊）|
| **Architect**（cross-check）| 自家 + Apple 平台知識集 | 大型模組落地後做對抗式架構檢查（Phase 3 GameSession actor / Phase 4 Telemetry fan-out / Phase 5 Persistence conflict 策略）；找 protocol seam 漏洞與 module boundary smell |

### 派發契約

每次派發 sub-agent，主 agent 必須給出：
1. **任務 scope**：明確的可驗證目標（檔案、模組、行為）。
2. **依賴文件**：應該讀哪些 `docs/` 與 `meetings/` 章節。
3. **skill 指定**：明確列出該 sub-agent 應 invoke 的 skill。
4. **回傳格式**：實作 diff、設計稿、或文字決策。
5. **驗證標準**：通過什麼測試 / 達到什麼條件才算完成。
6. **Impl-notes log 要求**（適用於非 trivial 派發）：subagent 必須在任務開始時建立 `meetings/{date}_{topic}.impl-notes.md`，過程中持續更新 §設計決定 / §偏離 / §折衷 / §未決 四欄，回傳前 mark `Status: COMPLETE`。完整規範見 `agent-impl-notes-log` skill。
7. **Phase 收尾強制 TODO sweep**（適用於宣告 phase 完成前）：在合併 phase-completion PR 前，Leader 必須對該 phase 的 diff scope 跑一次：
   ```
   rg -n --no-heading -e 'TODO|FIXME|XXX|HACK|stub|placeholder|Phase [0-9]+ Part' Packages/<target>/Sources/
   ```
   每一條 match 必須屬於以下其中一類，否則阻擋 phase 收尾：
   - **Resolved**：在本 phase 內修掉或實作完成。
   - **Moved to §Backlog**：明確路由到對應文件的 §Backlog（產品 → design.md、工程 → foundations.md、實作步驟 → plan.md、協作 → methodology.md），且該 §Backlog 條目必須引用來源 `file:line`。
   - **Intentionally left**：在 phase meeting log 內以「intentionally left, see <follow-up issue / phase reference>」明文記錄。

   Stub / placeholder 程式碼即使註解未含字面 "TODO"，也必須在 phase log 內 flag。Subagent 可在工作中提出技術債，但「sweep 收尾」是 Leader 的職責，不可下放。formal 版本見 `subagent-review-cycles` skill §Phase TODO sweep checklist。

Sub-agent 回傳後由主 agent 審核，**通過審核才向使用者報告**。審核時 Leader 先讀 impl-notes，再對齊 diff 與驗證標準。

8. **Code Reviewer 強制插入門檻**（hybrid review，user-confirmed 2026-05-22）：Senior Developer / Frontend Developer 等 IMPL subagent 回傳後，Leader 在 commit 前**必須**插入一輪 `Code Reviewer` subagent，當以下任一條件成立：
   - **Diff 規模**：> 50 added/modified lines（累計 across 該 dispatch 全部檔案）
   - **核心模組命中**：任何 source 變動落在
     - `Packages/SudokuKit/Sources/Persistence/`
     - `Packages/SudokuKit/Sources/AppComposition/`
     - `Packages/AppMonetizationKit/Sources/MonetizationCore/`
     - `Packages/AppMonetizationKit/Sources/AdsAdMob/`（第三方 SDK isolation 契約）
     - `Packages/AppMonetizationKit/Sources/IAPStoreKit2/`
     - 頂層 `Project.swift`（Tuist）、`Package.swift`
     - `App/Resources/PrivacyInfo.xcprivacy`

   兩條都不命中（CI script 微調、doc fix、asset 替換、test-only 改動）→ Leader 自行讀 impl-notes + diff + 跑 focused build/test 即可，**不需**派 Code Reviewer。

   Code Reviewer 給 approve → Leader commit；reject → Leader 帶 feedback 回派 IMPL subagent（同一 agent 用 SendMessage，保留 context），revise 後 loop。borderline 情況一律派 Code Reviewer（門檻為 floor，非 ceiling）。


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
| `superpowers:writing-plans` | `docs/v1/design.md` 某節通過後，要把它變成 `plan.md` 步驟 | 緊接 spec phase 結束、進入實作前 |
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
| `agent-impl-notes-log`（自家）| Developer / Senior Developer / Designer | 任何非 trivial 的 subagent 派發 — 任務開始即建檔，持續記 設計決定 / 偏離 / 折衷 / 未決 四欄，回傳前 mark COMPLETE |
| `swiftui-interaction-footguns`（自家）| Developer | 寫 / review SwiftUI 互動程式碼（tap area、gesture priority、scenePhase、sidebar 點擊區）；macOS smoke test 抓到的互動 bug 修復前 |
| `ios-design-mockup`（自家）| Designer | 產出 View mockup HTML / SwiftUI prototype；配色 / 字型 / spacing 視覺決策；交 Developer 落地前 |

### 協作 / Review / Spec orchestration

| Skill | 屬於 | 使用時機 |
|---|---|---|
| `leader-developer-handoff-contract`（自家）| Leader（主 agent）| 派發 sub-agent 前撰寫 dispatch brief — 強制 5 元素（scope / docs / skills / 回傳格式 / 驗證標準）+ impl-notes log 要求 |
| `subagent-review-cycles`（自家）| Leader | 大型結構性章節 / 模組落地 — 派 Developer 草擬 → Code Reviewer 對抗式審查 → Leader 收回逐條 ACCEPT/REJECT；設 round 上限 N、round-1 cosmetic 改 Leader 直接 inline 套用 |
| `spec-phase-orchestration`（自家）| Leader | Spec phase 推進 — section-by-section approval（§What → §How.1 → §How.2 …），每節未通過不進下節；prerequisite checklist Unconfirmed / Resolved 兩態 gate |
| `backlog-routing-by-topic`（自家）| Leader / Developer | Session 中浮現與當下節無關的想法 — 依主題路由（產品 → design.md §Backlog、工程 → foundations.md、實作步驟 → plan.md、協作 → methodology.md、無法分類 → 當天 meeting log §未決） |
| `session-to-meeting-log`（自家）| Leader | Phase 收尾 / session 結束 — 把 chat session JSONL 轉成 `meetings/{date}_{topic}.md` 結構化決策紀錄 |
| `methodology-pattern-extractor`（自家）| Leader | 觀察到同一協作模式 ≥ 3 次 sightings — 抽出 trigger / action / outcome / next-time adjustment 四欄，沉澱進 `methodology.md` §累積中的模式 |

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

### Pattern: Leader-parallel work during background subagent dispatch

- **Trigger**: 主 agent 派出 background subagent（Phase 6 開始改用 `run_in_background: true`）後，session 處於「等回傳」狀態
- **Action**: Leader 不空轉 — 趁 subagent 跑的同時做下一階段 dispatch 預草稿、撰寫對應 phase 的 meeting log、做 cross-doc consistency 預檢；user 在 Phase 8 明確要求過「leader 你趁著 subagent 忙碌之餘 你也看一下有沒有能做的事情 像是撰寫 meetings」
- **Outcome**: Phase 6 之後每個 phase meeting log 都在 subagent 跑完前就寫好；Phase 8 Part 2 + Phase 9 dispatch 在 Part 1 跑期間就草擬完，回傳即派；單一 session 內推進 4 個 phase 不卡停
- **Next-time adjustment**: 派出 background subagent 後立刻列出至少 2 個非衝突的 leader-side 任務（meeting log、下一 dispatch 草稿、文件 cross-ref 預檢）；避免動到 subagent 正在改的檔
- **Sightings**: Phase 6 / 7 / 8 Part 1 / 8 Part 2 / 9 共 5 次（2026-05-19）

### Pattern: Heavy-phase pre-split to dodge usage limits

- **Trigger**: 單一 phase 預期 subagent 工作量 ≥ 10 個 step 或 ≥ 30 個新測試（從 plan.md 步數 + 預期測試矩陣估算）
- **Action**: 派發前主動將 phase 切為 Part 1 + Part 2 兩次 dispatch，每次 ≤ 6 step；Part 1 收尾時請 subagent 在回傳裡 flag Part 2 的 readiness 訊息
- **Outcome**: Phase 8 SudokuUI 切為 8.1–8.6 / 8.7–8.11，Part 1 32 個測試 / Part 2 29 個測試共 61 個全綠；對比 Phase 2.7 一次性派發在中途遭遇 budget 耗盡 + 手動清理 WIP 的痛點
- **Next-time adjustment**: 任何 phase plan.md 步數 ≥ 8 就強制 pre-split；snapshot-heavy（≥ 8 個 PNG baseline）也視為重型
- **Sightings**: Phase 2.7 budget 耗盡（反例）、Phase 8 主動 split 成功（2026-05-19）

### Pattern: PROPOSAL-first dispatch with prerequisite checklist

- **Trigger**: 派發新模組或工具給 subagent 前，spec / 外部 API / 第三方契約存在未驗證假設
- **Action**: dispatch brief 明確要求 subagent 先產出 PROPOSAL_DRAFT（含 Verified ✓ / Unconfirmed ? prerequisite checklist），commit 進 `docs/` 後暫停等 Leader review；只有 PROPOSAL 通過後才進 IMPL_DRAFT。對應 `ai-collaboration-mode/SKILL.md` 的工作流
- **Outcome**: Phase 0–9 每個 phase 開頭都先收到結構化提案（包含 rejected alternatives 與 prerequisite gate），Leader 可在 implementation 前抓出契約不一致；ASCRegister CLI 同樣以 PROPOSAL → IMPL → PR 流程進行
- **Next-time adjustment**: PROPOSAL 必含「self-review pass」要求 — subagent 在宣告 ready 前自己掃一遍 placeholder / 矛盾 / 模糊；避免 Leader 第一輪 review 全在抓低階問題
- **Sightings**: Phase 0–9 每 phase 1 次共 10 次、ASCRegister CLI 1 次（2026-05-19，共 11 次以上）

### Pattern: Post-execution doc sweep after structural changes

- **Trigger**: 實作階段出現偏離原 plan / design 的結構性事實（模組位置變動、baseline 數量調整、status 從 DRAFT → FINAL 可斷言）
- **Action**: Phase 完成後派 Code Reviewer 跑「documentation final sweep」— grep 所有 docs 抓 status header / file path / 數字 reference 的落差，按 (a) status / (b) path / (c) 需查 meeting log / (d) 模糊待 Leader 決議 分類，前三類直接修，最後一類 flag 回 Leader
- **Outcome**: §8.11 amendment（21 → 25 PNG baseline）+ LivePersistence 模組位置從 `App/CompositionRoot/` 改至 `Packages/.../Persistence/` 透過一次 sweep 在 plan.md / design.md / foundations.md / README.md / designs/README.md 全部對齊，4 commits 完成、0 ambiguity
- **Next-time adjustment**: 「實作完成」與「文件 final」是兩個 milestone，不是同一個；任何 phase 收尾後排一次 sweep dispatch
- **Sightings**: §8.11 amendment + LivePersistence 位置 sweep（2026-05-19，1 次）

### Pattern: Batch permission prompts via background subagent isolation

- **Trigger**: Leader 在前景同時操作多個會觸發 permission prompt 的工具（git write、gh API mutation、file write to sensitive paths）；user 反饋「可以減少一直詢問我 execute command permission 嗎」
- **Action**: 把多步驟工作集中派給 background subagent（自帶 permission inheritance），讓 Leader 在前景只做 read-only + 文件編輯這類 auto-allowed 行為；無法移到 subagent 的批次操作（如多個 gh api PATCH）用單一 Bash call 串接 `&&` 一次性 prompt
- **Outcome**: GitHub bootstrap（create + push + ruleset + 三項 security enablement）從預期 6 個 prompt 壓到 3 個；Phase 6–9 全程 Leader 前景幾乎只 Read / Edit / WebFetch，幾乎無 prompt 噪音
- **Next-time adjustment**: 任何需要 ≥ 3 個 write 動作的工作優先放 subagent；無法時用 chained Bash command；user 拒絕 allowlist 擴充時尊重該決定（skill rules forbid 寫操作 allowlist）
- **Sightings**: Phase 6–9 全程、GitHub bootstrap 今天（2026-05-19，共 5 次以上）

### Pattern: Phase-completion TODO sweep before declaring done

- **Trigger**: 任何 phase 即將宣告 feature-complete / 準備合併 phase-completion PR
- **Action**: Leader 對該 phase 的 diff scope 跑 `rg -n --no-heading -e 'TODO|FIXME|XXX|HACK|stub|placeholder|Phase [0-9]+ Part' Packages/<target>/Sources/`；每一條 match 必須 (a) 本 phase 內 resolved、(b) 路由到對應文件 §Backlog 並引用 `file:line`、或 (c) 在 phase meeting log 明文記錄為 intentional + follow-up reference。Stub / placeholder 程式碼即使沒有字面 TODO 註解也要 flag
- **Outcome**: 預期沒有「以為下一 phase 會接手、實際從未被撿起」的 stub 流到 v1 feature-complete；Leader 是 sweep 的責任歸屬，subagent 提出技術債、Leader 關閉迴圈
- **Next-time adjustment**: 每次新增 SwiftPM target 後，把 `<target>` 換成具體 target 列表寫進當下 phase 的 dispatch brief；若 false positive 多到失去訊號，調整 regex 而非放棄 sweep；formal 版本見 `subagent-review-cycles` skill §Phase TODO sweep checklist
- **Sightings**: Phase 8 Part 1 `RootView.swift` `sidebarPlaceholder` stub 帶 "Phase 8 Part 2 / 9 (DI step)" 註解，跨 Phase 8 Part 2 / 9 未被撿起，shipped 到 v1 feature-complete，僅在 macOS smoke test 時被 user 抓到（反例，2026-05-19 — 本 pattern 的反向動機）

## 觀察到的反模式（Anti-patterns）

### Anti-pattern: Eager external-resource init crashing unit tests

- **首見**: `meetings/2026-05-19_phase-9-app-wiring.md`（CloudKit `CKContainer.default()` 在無 entitlements 的測試 process 中 trap；MetricKit `MXMetricManager` subscription register 同樣 crash）
- **問題**: composition root 在 `init` 直接構造 CloudKit gateway / 註冊 MetricKit subscription，導致 unit test 一啟動就 crash，逼測試只能 integration 化
- **解法**: 用 lazy NSLock-guarded field 延後 CloudKit init 到第一次實際 call；MetricKit register 加 `XCTestConfigurationFilePath` env-var 檢查跳過。Composition root 變得在 test process 中 safe-to-construct
- **教訓**: 跨 process boundary 的資源（CloudKit container、MXMetricManager subscription、GameKit auth）一律延後或加 test-env 短路

### Anti-pattern: Trial-and-error CLI 取代閱讀官方文件

- **首見**: `CLAUDE.md` 規則收錄 / Phase 1.2 lefthook 整合
- **問題**: 不熟的 API 或工具行為，第一反應是 `cmd --help` 跑跑看 → 看 error → 改 flag 再跑。產生雜訊、可能誤觸 destructive flag、且推論的「規格」可能只是當前版本的 quirk
- **解法**: 「No CLI trial-and-error instead of documentation」寫進 CLAUDE.md；遇到不熟 API 先讀 man page / 官方 doc / README，再下指令。Subagent dispatch brief 明確要求先 research 再 code（ASCRegister CLI 派發即帶此規則）
- **教訓**: CLI 是執行工具，不是規格逆向工程工具

---

## §Backlog

_討論過程中浮現的協作模式、流程改善想法。每條一行。_

- **遷移到 GitHub 平台原生專案管理工具**（2026-05-20）：目前 `meetings/*.impl-notes.md` + `docs/*` + GitHub issues (#15-#49) 三套並行追蹤；隨 issue 數量增加（已 49 條）+ Phase 10 操作流程上線後維護成本會變高。評估升級到 **GitHub Projects (v2)** 看板統籌 issues / PRs / milestones / status；其中 impl-notes 可改用 issue comment thread 或 wiki 收納。觸發點：(a) issue 數超過 100；(b) Phase 10 子任務開始平行；(c) 想做 release notes 自動化（從 closed issues 抓 changelog）。動工時需把現存 49 個 issues 分類進 backlog/v1/v2 columns，並把 49 條 PRs 對應到 issue 上（多數 PR 已 close 對應 issue 但 milestone 沒設）。同時補上 `.github/` 範本：issue/PR template、CODEOWNERS、labels schema。
- **GitHub App (bot) 身份取代用 user 個人 gh token**（2026-05-20）：目前所有 commits / PRs / merges 都用 user 個人 gh CLI auth 執行，audit trail 顯示為 user 本人，雖然實際上是 Leader subagent 在跑。user 不接受這個歸屬。解法：建立 GitHub App `wei18-sudoku-bot`、安裝在 Wei18/Sudoku、用 App ID + Installation ID + `.pem` 私鑰簽 JWT 拿 1-hour installation token，全部自動化 ops 走 bot token；local repo git config 改用 `wei18-sudoku-bot[bot]` 身份；commit message `Co-Authored-By: Wei <noreply@github>` trailer 取代現在的 `Co-Authored-By: Claude`。觸發點：當前 in-flight 結束後即動工（2026-05-20 已 unblocked，剩 user 端建 App）。實作含：`scripts/bot-gh-token.sh` 自動取 token、`.gitignore` 補 `.pem`（已有但 reaffirm）、`docs/foundations.md §7` 補 bot 身份章節、README 更新。

