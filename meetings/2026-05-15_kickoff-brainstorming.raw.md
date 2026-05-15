# 2026-05-15 — Kickoff Brainstorming

Session id：`ae54f5ea-6b89-4f59-9d9f-cafb8dff08f6`
模式：AI Collaboration Mode（Leader / Developer）；本次只有 Leader。

## 目標

為 Sudoku iOS + macOS App 定錨整體方向、決定 spec 階段要產出哪些文件，並在動工前把文件管線搭好。

## 決策

1. **雙重交付**：可玩的 Sudoku App 與「Claude agent 應用紀錄」皆為一等公民交付物。
2. **平台**：iPhone (iOS) + Mac (macOS)。iPad / Watch / visionOS 暫緩。
3. **v1 遊戲功能**：筆記 + Undo/Redo + 錯誤提示；存檔與個人紀錄；Game Center 成就 + 分數排行；單題世界 / 朋友圈排行。
4. **題目來源**：混合策略 — 策劃題庫存於 **CloudKit 公開 DB**；**Xcode Cloud** 排程工作流定期推送新題。**不自建 backend**。每題有穩定 `puzzleId` 以支援單題排行。
5. **個人資料同步**：CloudKit 私人 DB（提案中，尚未在 design.md 確認）。
6. **文件管線（精簡版）**：
   - `README.md`
   - `docs/design.md`（產品規格 + 技術設計合一）
   - `docs/plan.md`（TDD-ordered checklist）
   - `docs/methodology.md`（Claude agent 應用方式 — living doc）
   - `meetings/{date}_{topic}.md`（原始 session 紀錄）
7. **不寫實作程式碼**，直到 design + plan 通過。實作階段採 **TDD**。
8. **文件語言**：繁體中文（zh-TW）作為主要語言。

## 否決的替代方案

- **實作里程碑切法 A/B/C**（縱向切片 / 基礎建設先行 / 雙軌並行） — 駁回原因：屬於實作階段討論，現在還在 spec 階段。
- **方法論隱含於 spec/RFC/plan，不另外寫文件** — 駁回原因：使用者明確要求要有專屬的方法論文件。
- **8 檔案版的文件結構**（spec、rfc、plan、tasks、methodology、adr、README、meetings 各自獨立） — 駁回原因：對 solo v1 過度結構化。合併為 5 檔（spec+rfc 合成 design.md；tasks 由 plan.md 的 checkbox 吸收；ADR 延後至真正需要時再開）。

## 交接（Hand-offs）

本次未派發 Developer subagent。下一個 session 預計派發 Developer 草擬 `docs/design.md §What`。

## 未決問題

- 在地化範圍（提案 zh-TW + en，尚未確認，或只做 zh-TW？）。
- 商業模式（免費 / 免費+IAP / 付費） — 未討論。
- 難度等級數量（題庫隱含分級，但未在 v1 功能列表寫死） — 需在 §What 確認。
- 是否在此階段就拆 SwiftPM 模組（Engine package vs. App target）。
- 本資料夾何時 `git init`（提案：design.md §What 通過後）。

## 下一個 session

逐節草擬 `docs/design.md §What` → 通過 → `§How`。

---

## 後續同 session 進展（補記）

本 session 在 kickoff 之後一路推進到 spec phase 完成。補記重大里程碑：

### Foundations.md 七節（Leader 主導）

§1 Swift 6 complete concurrency；§2 單 Package + 薄 App + 7 target；§3 swift-testing + snapshot-testing；§4 Xcode Cloud 單軌（GH Actions 入 backlog）；§5 `os.Logger`；§6 Apple 三件套（不引第三方 tracking）；§7 plan 體系採 superpowers writing-plans。

### swift-platform-defaults skill 建立

由 foundations.md 抽取可重用部分為個人預設 skill：`~/.claude/skills/swift-platform-defaults/SKILL.md`。

### Methodology.md 角色分工

主 agent = PM + Lead 不寫 code；subagents：Developer（`swift-platform-defaults` + `swiftui-expert-skill` + TDD/debug skills）/ Designer（`ui-ux-pro-max` + `swiftui-expert-skill`）/ Code reviewer。派發契約：scope / 依賴文件 / skill 指定 / 回傳格式 / 驗證標準。

### Design.md 完整完成

- **§What**：Daily Mode（每日 3 題、recurring daily leaderboard、UTC reset、同 puzzleId 不重計分）+ Practice Mode（Starter Pack 90 + 退役 Daily 自動入池）+ 7 locale + 免費無 IAP
- **§How.1**：模組依賴 + 動態資料流 4 場景 + DI composition root
- **§How.2**：CloudKit Public DB `Puzzle` + Private DB `SavedGame` / `PersonalRecord`（mode × difficulty = 6 筆）+ schema 演進策略
- **§How.3**（subagent round 1）：3 條 recurring daily leaderboard + 10 個 achievements（用滿 1000 點）+ `GameCenterClient` protocol + 認證降級 + 朋友圈 + Sandbox/Production
- **§How.4**（subagent round 1）：題庫採 curated bank + technique-tier 難度校準 + uniqueness validator + Xcode Cloud 每月排程 + secret rotation。Status：DRAFT，含 4 條 prerequisite 須於 plan.md 驗證
- **§How.5**（subagent round 1）：8 個 View + NavigationStack/SplitView 切換 + `GameSession.Status` 狀態機 + `@Observable` + `@MainActor` VM + debounce token 落 VM 層 + Localizable.xcstrings + A11y baseline + 18 張 v1 snapshot
- **§How.6**（subagent round 1）：6 個錯誤型別 + per-source matrix + 離線可用性表 + iCloud 帳號 3 case + 同步衝突 per-field LWW + schema mismatch + 4 種 UI presentation pattern
- **§How.7**（subagent round 1）：7 production target × 6 fields（pyramid layer / coverage / test categories / fakes / sample @Test）+ cross-cutting infra（Clock/UUID/RNG 注入、SudokuKitTesting 共用 fake target）+ CI 整合 + v1 不做的測試清單

### 否決的替代方案（補）

- 「隨機題庫 + 過濾已完成」題目模型 — 改為「每日 3 題 + Practice 退役回收」
- All-time leaderboard 與 per-puzzle leaderboard 各自獨立 — 改為 3 條 recurring daily 取代兩者
- Tracking 引入 TelemetryDeck / Firebase — v1 走 Apple 三件套（NoOp TrackingSink）
- 8-file 文件結構 — 改 6 file（加 foundations.md）
- GitHub Actions 與 Xcode Cloud 雙軌 — v1 暫不採 GH Actions
- Subagent 派發 §How.3-§How.7 採每節最多 10 round；實際各節 1 round 即通過（Leader 以編輯方式做小幅調整代替再 round），符合「limit 是上限不是要求」精神

### Code Reviewer 派發（round 1）

派 Code Reviewer subagent 在 user review 前做技術正確性審查（禁 CLI、可 WebSearch）。產出 7 BLOCKER / 11 MAJOR / 7 MINOR。

**用戶裁示**：OS floor 採選項 A（拉至 iOS 26 / macOS 26）；其餘 24 條全部 Leader ACCEPT。

**全部套用清單**：

| 類別 | 改動 |
|---|---|
| OS Floor | iOS 18/macOS 15 → **iOS 26/macOS 26**（foundations §1、§2 Package、design §What positioning；swift-platform-defaults skill 保持 iOS 18 預設，本專案視為 deviation）|
| GC Leaderboard | 跨午夜完成 skip submission（Apple `submitScore` 永遠寫 active occurrence、無法 retarget）；新增 score > 2 小時上限視為 abandon |
| GC Achievements | 砍至 8 個、總 550 點（保留 450 點 v2 餘裕）；移除 `daily.streak_30` 與 `practice.complete_500` 至 v2 候選 |
| GC Protocol | 加 `friendsAuthorizationStatus()` + `requestFriendsAuthorization()`；`currentAuthState` 改 `nonisolated` snapshot + `authStateUpdates()` AsyncStream；`GameCenterError.underlying` 保留 `code: Int`；認證觸發改 `.task` modifier |
| CloudKit Schema | Index 欄細分 Q / Q+S / Q+S+Search；新增 Private DB custom zone `com.wei18.sudoku.userZone` + `CKDatabaseSubscription`；新增 Public DB record type `PuzzleDeliveryLedger`（取代 `consumed.json`）|
| Puzzle Delivery | `forceReplace=false` → `operationType="create"` + RECORD_EXISTS verify-then-skip；移除 `consumed.json` git commit / GitHub PAT；ledger 改寫 CloudKit Public DB；30 天月界限明確（連續 30 個 UTC 日）|
| Solver / Calibrator descope | xWing / swordfish / xyWing 等 technique-tier solver **整體延後 v2**；v1 僅 nakedSingle + hiddenSingle + nakedPair + DFS uniqueness；難度由人工 curated label 主導、自動 verifier 僅檢 clueCount + propagation 可解性 |
| Persistence | `PersistenceProtocol: Sendable` 顯式宣告 + 完整列表（latestInProgress / loadOrCreate / save / markCompleted / fetchCompletedDailyIds / fetchPersonalRecord）；`SavedGameSummary` value type 定義；`flush()` 改 async |
| ViewModel | `vm.pause()` / `vm.abandon()` 改 async；scenePhase 只 `.background` 觸發 pause、`.active` **不**自動 resume；改顯示 "Tap to resume" |
| Mac 鍵盤 | `.focusable()` + `@FocusState` + `.onKeyPress(phases: .down)` + `.keyboardShortcut` on Menu commands |
| iCloud 帳號 | 偵測信號從 `NSUbiquityIdentityDidChange`（iCloud Drive identity）改為 `CKAccountChanged` + `CKContainer.fetchUserRecordID(...)` |
| PersonalRecord race | 初次 create race 用 `.ifServerRecordUnchanged` policy + server tag 重發 modify；deterministic recordName 自動降級 create→update |
| Test infra | 新增 §How.7.4b `GameViewModelTests`（debounce 在 VM 層測，非 Persistence 層）；補 swift-testing parallel + 共享 fake 須加 `.serialized` trait |
| OSLog | 修正 `.private` 語意精確化（debugger attach 時可見，僅遠端 sysdiagnose 遮罩）|
| §How.4.9 Prerequisites | 4 條剩 2 條（`forceReplace` + solver 兩條已 Resolved）；剩 Xcode Cloud `ci_scripts` 環境 + 排程 UTC 對齊兩條留 plan.md 驗證 |

### Code Reviewer round 2

回頭審 round 1 修正成果，發現 3 個遺漏：

1. **MAJOR regression**：§How.7.1 仍寫「9 種 technique」，未隨 §How.4.3 descope 同步 → 改為 3 層 propagation + verifier 邊界 test
2. **BLOCKER 新**：`GameCenterSink` `guard mode == .daily else { return }` 把 Practice 成就也擋了 → 改為「Achievement evaluation 永遠執行；submitScore 才受 daily-only 限制」
3. **MAJOR**：§How.5.1 「啟動後 1s 內」與 §How.3.4 `.task` modifier 衝突 → 改為「於 `.task` modifier 內呼叫」

全部 ACCEPT + 修正。Round 2 結果：1 regression, 2 new issues identified；round 1 accept rate 24/25。

### 用戶新需求（同 session 追加）：public GitHub repo + secrets 控管

用戶宣告 v1 將為 public repo from day 1。新增：

- **foundations.md §7 Secrets 與 public repo 規範**（章節順序：原 §7 Agent skills 變 §8；Secrets 進 §7）
- §7.1 公開承諾 from day 1（沒有「先 private 再公開」的後路）
- §7.2 Secret 分類（CloudKit PEM、ASC API Key、簽章證書、玩家識別資料等）
- §7.3 不可進 git 的東西 + 洩露處置 SOP（rotate → filter-repo → 通知 GitHub support → incident log）
- §7.4 `.gitignore` 黑名單起手版
- §7.5 `.mise.toml` + `lefthook` + `gitleaks` 本機 pre-commit hook
- §7.6 Xcode Cloud PR CI gitleaks 第二道防線
- §7.7 `.env.example` / `docs/setup.md` 設定範本
- §7.8 Privacy / telemetry 公開承諾（不收 PII / 無第三方 SDK / 無我方伺服器）
- §7.9 Code reviewer 責任清單
- §7.11 Open items：`ci_pre_xcodebuild.sh` hook 命名、lefthook mise plugin、gitleaks 自訂規則 — 留 plan.md 驗證

