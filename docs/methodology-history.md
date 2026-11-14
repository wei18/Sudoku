# 協作模式歷史紀錄（Patterns / Anti-patterns）

狀態：**歷史紀錄**。本檔保存各協作模式的來源案例（trigger、當時的做法、結果、sightings）。現行規則只看 [`docs/methodology.md`](methodology.md)；兩者不一致時以 `methodology.md` 為準。

- 新模式的案例加在本檔；由案例得出的規則寫進 `methodology.md`，一條規則一行。
- 文中的 skill 名稱沒有 plugin 前綴，是當時的寫法；現在的名稱是 `collaboration-skills:<skill>`。

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
- **Next-time adjustment**: prerequisite 在 draft 階段就由 Developer 自填，避免 reviewer 才補；formal 版本見 `collaboration-skills:spec-phase-orchestration` 的 prerequisite checklist
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
- **Action**: dispatch brief 明確要求 subagent 先產出 PROPOSAL_DRAFT（含 Verified ✓ / Unconfirmed ? prerequisite checklist），commit 進 `docs/` 後暫停等 Leader review；只有 PROPOSAL 通過後才進 IMPL_DRAFT
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

### Pattern: Leader pre-flight before each subagent dispatch

- **Trigger**: 要派 Developer subagent 接著一個既有 WIP branch / worktree
- **Action**: Leader dispatch 前必跑 (a) `mise trust` 新 worktree 路徑、(b) `git fetch origin <wip-branch>` + 本地 `git rebase main` + `git push --force-with-lease`、(c) `ps aux | grep swift-test` + kill orphans、(d) prompt 內明寫「Leader 已處理 rebase / mise trust / 殘留 procs，subagent 只要 `git fetch + reset --hard`」
- **Outcome**: subagent 起步即可動工，不需處理 rebase/merge/kill 等 sandbox-denied 操作；省下「subagent 撞牆 → abort → 我修 → 重派」一輪 cold-start cost
- **Next-time adjustment**: pre-flight 失敗（例：rebase conflict）→ Leader 自己 resolve 後再 dispatch；不要把 conflict resolution 丟給 subagent（subagent 無法 cross-branch 操作）
- **Sightings**: #67 / #64 re-dispatch（2026-05-25，pre-flight 缺漏的 2 次連續 abort 後制定）

### Pattern: Scope-split heavy refactors into 3–5 file batches

- **Trigger**: issue 的實作 scope 超過 ~10 個檔案 / 多個跨 module 決定 / 含 module placement + call-site refactor + UI surface 三類混合
- **Action**: Leader 拆成 3–5 個小 sub-issue（每個 ≤ 5 檔案 / 單一決定面），各自獨立 subagent + PR；前一個 PR merge 後再派下一個（讓 main 累積為 base）
- **Outcome**: 失敗回滾粒度小、Code Reviewer 認知負荷低、cold-start 重讀範圍小；中間任一段卡住不會炸整個 issue
- **Next-time adjustment**: 拆 sub-issue 時先確認依賴順序（types → call-sites → UI），dispatch 之間要明確「上一個 PR 已 merge」才放下一個
- **Sightings**: #67 17-file 一次 dispatch → 47 min runtime + 多次 abort + 9 個 try? site 開放問題（反例，2026-05-25 — 本 pattern 的反向動機）

### Pattern: Adversarial pre-mortem before dispatch

- **Trigger**: 準備 dispatch subagent 前
- **Action**: Leader 自問「這次 dispatch 最可能怎麼失敗？」常見答案：lefthook deadlock、mise trust、swift-test hang、module dep missing、sandbox denial。逐項在 prompt 內預防或聲明「Leader 已處理 X」
- **Outcome**: 撞牆次數減少；prompt 攜帶足夠先驗知識
- **Next-time adjustment**: 把常見失敗模式累積進 `methodology.md` 的 Leader 規則與本檔 anti-patterns，讓未來 dispatch 自動繼承
- **Sightings**: Fix B 第三次 dispatch 才加入 commit-before-test 規則（2026-05-25）— 前兩次失敗是因為 pre-mortem 沒做

## 觀察到的反模式（Anti-patterns）

### Anti-pattern: Eager external-resource init crashing unit tests

- **首見**: `meetings/2026-05-19_phase-9-app-wiring.md`（CloudKit `CKContainer.default()` 在無 entitlements 的測試 process 中 trap；MetricKit `MXMetricManager` subscription register 同樣 crash）
- **問題**: composition root 在 `init` 直接構造 CloudKit gateway / 註冊 MetricKit subscription，導致 unit test 一啟動就 crash，逼測試只能 integration 化
- **解法**: 用 lazy NSLock-guarded field 延後 CloudKit init 到第一次實際 call；MetricKit register 加 `XCTestConfigurationFilePath` env-var 檢查跳過。Composition root 變得在 test process 中 safe-to-construct
- **教訓**: 跨 process boundary 的資源（CloudKit container、MXMetricManager subscription、GameKit auth）一律延後或加 test-env 短路

### Anti-pattern: Leader 接手 Developer 工作

- **首見**: 2026-05-25 #67 卡關，Leader 一度想「我直接做比較快」
- **問題**: subagent 卡住或進度差時，Leader 跳下去做實作 → 燒掉 Leader context window、破壞 agent team 模型、未來 session 缺少可繼承的 dispatch 紀錄
- **解法**: Leader 的 leverage 來自協調 multi-Developer，不是當最強 Developer。卡關時 Leader 該做的：(a) 環境清理（kill procs、mise trust）、(b) 用 better dispatch prompt 重派、(c) 把學到的東西沉澱進本檔。實作工作回到 Developer subagent
- **教訓**: 「我自己半小時搞得定」這念頭一冒出來，replace 成「kill procs + rebrief + 重派」。例外：trivial one-liner（typo、config flip）或 user 明確指定 Leader 動手

### Anti-pattern: lefthook `parallel: true` causing mise deadlock (RCA H4)

- **首見**: `meetings/2026-05-25_swift-test-hang-rca.md` §H4；實際被卡：Fix B 第二次嘗試的 final commit、#64 Phase 2 第二次 commit、Leader 自己 commit lefthook 修正檔本身
- **問題**: `lefthook.yml` 設 `pre-commit.parallel: true`，concurrent `mise exec swiftlint` + `mise exec gitleaks` 在 mise process-level cache lock 上死鎖；表現為 git commit 永久 hang at 0.02s CPU，subagent 無法 kill，逼出 `--no-verify` 或 abort
- **解法**: `pre-commit.parallel: false`（serialize gitleaks → swiftlint → hygiene）；latency 成本 < 1 秒，遠勝多分鐘 deadlock。Fix 已 land 為 PR #136
- **教訓**: 工具鏈 parallel 設定預設值不一定安全 — mise + lefthook 這組合就是個 footgun；任何「跑得很快但偶爾完全卡死」的 sign 都該嚴肅查 root cause（RCA 投入 1 個 subagent 半小時，省了無限多次 kill -9）

### Anti-pattern: swift test 全 suite 為第一驗證指令

- **首見**: 2026-05-25 多次 session；具體案例見 Fix B 前兩次 subagent dispatch
- **問題**: `swift test` 無 `--filter` 在本 repo 會撞 RCA H1 leaked-Task deadlock，subagent 直接 hang 18–68+ 分；subagent 自己不能 kill，重啟又疊出新 orphan 進程
- **解法**: 預設用 `swift test --filter <TestName>`；全 suite 必須包 `timeout 600 swift test 2>&1 | tail -50`，且只在 targeted tests 都過後才跑。Fix B（PR #135）解除根本 leak 後，此規則仍應沿用作為 defense in depth
- **教訓**: 在已知有 hang 風險的測試 stack 上，預設指令必須是「窄而快」的，subagent dispatch contract 強制指定（見 `CLAUDE.md` §Commands）

### Anti-pattern: Worktree wipe before commit causes lost work

- **首見**: 2026-05-25 Fix B 第一個 subagent 跑完完整驗證（含 full `swift test` PASS）但因「沒 commit 過」被 harness 自動清掉 worktree；所有 edits 丟失，只剩 transcript
- **問題**: `isolation: "worktree"` 預設行為「no commits = no changes」，會自動清 worktree。subagent 把 commit 排到「驗證通過後」的話會中招
- **解法**: `methodology.md` Leader 規則的 commit-early — chunk 完就先 commit（protective `--no-verify` WIP 可），再驗證；驗證過了再 amend message / squash
- **教訓**: harness 的「乾淨」行為對使用者是 footgun；commit 是免費的，丟 work 是天價

### Anti-pattern: Trial-and-error CLI 取代閱讀官方文件

- **首見**: Phase 1.2 lefthook 整合
- **問題**: 不熟的 API 或工具行為，第一反應是 `cmd --help` 跑跑看 → 看 error → 改 flag 再跑。產生雜訊、可能誤觸 destructive flag、且推論的「規格」可能只是當前版本的 quirk
- **解法**: 規則收錄於 `methodology.md` Leader 規則；遇到不熟 API 先讀 man page / 官方 doc / README，再下指令。Subagent dispatch brief 明確要求先 research 再 code（ASCRegister CLI 派發即帶此規則）
- **教訓**: CLI 是執行工具，不是規格逆向工程工具


---

## 已封存的 §Backlog 條目

以下兩條在 2026-05-20 記入 `methodology.md §Backlog`，觸發條件已過期，移到這裡存查。

- **遷移到 GitHub 平台原生專案管理工具**（2026-05-20）：目前 `meetings/*.impl-notes.md` + `docs/*` + GitHub issues (#15-#49) 三套並行追蹤；隨 issue 數量增加（已 49 條）+ Phase 10 操作流程上線後維護成本會變高。評估升級到 **GitHub Projects (v2)** 看板統籌 issues / PRs / milestones / status；其中 impl-notes 可改用 issue comment thread 或 wiki 收納。觸發點：(a) issue 數超過 100；(b) Phase 10 子任務開始平行；(c) 想做 release notes 自動化（從 closed issues 抓 changelog）。動工時需把現存 49 個 issues 分類進 backlog/v1/v2 columns，並把 49 條 PRs 對應到 issue 上（多數 PR 已 close 對應 issue 但 milestone 沒設）。同時補上 `.github/` 範本：issue/PR template、CODEOWNERS、labels schema。
- **GitHub App (bot) 身份取代用 user 個人 gh token**（2026-05-20）：目前所有 commits / PRs / merges 都用 user 個人 gh CLI auth 執行，audit trail 顯示為 user 本人，雖然實際上是 Leader subagent 在跑。user 不接受這個歸屬。解法：建立 GitHub App `wei18-sudoku-bot`、安裝在 Wei18/Sudoku、用 App ID + Installation ID + `.pem` 私鑰簽 JWT 拿 1-hour installation token，全部自動化 ops 走 bot token；local repo git config 改用 `wei18-sudoku-bot[bot]` 身份；commit message `Co-Authored-By: Wei <noreply@github>` trailer 取代現在的 `Co-Authored-By: Claude`。觸發點：當前 in-flight 結束後即動工（2026-05-20 已 unblocked，剩 user 端建 App）。實作含：`scripts/bot-gh-token.sh` 自動取 token、`.gitignore` 補 `.pem`（已有但 reaffirm）、`docs/foundations.md §7` 補 bot 身份章節、README 更新。
