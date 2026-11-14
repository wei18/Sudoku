# Claude Agent 協作規則

本檔只寫現行規則。每條規則的來源案例在 [`docs/methodology-history.md`](methodology-history.md)；變更紀錄看 git log。

適用範圍：本 repo 特有的協作規則。Code review 流程、build 與 test 的預設做法由使用者的全域 engineering 規則決定，本檔不重述；本 repo 與全域規則不同之處寫在 `CLAUDE.md` §What CI covers。

## 運作模式

- **Spec-first**：非瑣碎的功能，先有使用者同意的規格（issue 內文或 `docs/` 的設計文件），再寫實作。流程見 `collaboration-skills:spec-phase-orchestration`。
- **TDD**：先寫測試，再寫讓測試通過的實作。
- **紀錄**：PR 描述與 issue 是每次變更的紀錄。Session 做了 PR 與 issue 都沒記到的決策時，才寫 `meetings/{YYYY-MM-DD}_{topic}.md`（`collaboration-skills:session-to-meeting-log`）。

## 角色

| 角色 | 是誰 | 做什麼 |
|---|---|---|
| **Leader** | 使用者對話的那個 session | 理解意圖、決策、寫與審文件、派發任務、審核產出、向使用者報告 |
| **Developer** | 被派發的 subagent | 實作一個任務：寫測試、寫程式、除錯 |
| **Designer** | 被派發的 subagent | 畫面 mockup、視覺與互動決策；產出交給 Developer 落地 |
| **Code Reviewer** | 被派發的 subagent | 審查 diff 或文件；只讀，不改檔 |

- Leader 何時可以自己動手改檔：見 `CLAUDE.md` §Roles。
- Subagent 回傳後，Leader 先讀 impl-notes，再對照 diff 與驗證標準；審核通過才向使用者報告。

## 派發 brief

每次派發都依 `collaboration-skills:leader-developer-handoff-contract` 寫齊它規定的必要欄位。本 repo 另外要求：

1. impl-notes 檔名用 `meetings/{YYYY-MM-DD}_{topic}.impl-notes.md`（格式見 `collaboration-skills:agent-impl-notes-log`）。
2. Developer 的驗證標準要包含：改到的每個 package 的 `swift test` 結果，以及改到的 Swift 檔通過 `mise run lint:swift_strict -- <files>`。
3. 會 build App 的任務，brief 要寫明 worktree 已經跑過 `mise trust` 與 `mise run worktree:seed <path>`。
4. Reviewer 的 brief 要寫明三件事：
   - 不用 heredoc。
   - 不執行會改動工作區的 git 指令（`reset`、`clean`、`checkout -- <path>`）。
   - 檔案內容一律從 PR head 讀（`git show <sha>:<path>`），不讀 session 的 checkout。
5. Reviewer 審跨 App 的 diff 時：一方有某個 UI 或文案、另一方沒有，而且找不到 `CLAUDE.md` §Conventions 規定的 exception comment，就當成未裁定項目回報 Leader。範例：`Packages/SettingsKit/Sources/SettingsUI/Settings/SettingsScreen.swift`（`Sudoku-only "Generator" row`）對應 `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/LiveRouteFactory.swift`（`No generatorVersionLabel`）。

## Leader 規則

派發之前：

1. 新 worktree 先跑 `mise trust`；要 build App 再從 main checkout 跑 `mise run worktree:seed <path>`。
2. 接續既有分支時，Leader 先把分支 rebase 到最新 `main` 並 push；subagent 用 `git fetch` 加 `git reset --hard origin/<branch>` 接手。
3. 清掉上一輪留下的 `swift-test`、`swiftpm-testing-helper`、`mise exec` 程序。
4. 自問「這次派發最可能怎麼失敗」，把預防方式寫進 brief。
5. 任務超過約 10 個檔案或 8 個實作步驟時，拆成每批最多 5 個檔案的子任務，一批一個 PR，前一個 merge 後再派下一個。
6. 規格或外部 API 有未驗證的假設時，先要求 subagent 交提案與 prerequisite checklist；提案通過才實作。

Subagent 執行期間：

7. Subagent 每完成一個大段落就 commit，impl-notes 也一起 commit。中途的 WIP commit 可以用 `CONTRIBUTING.md` §Pre-commit hooks 的例外；push 前的最後一個 commit 必須通過 hooks。
8. Subagent 的操作被 sandbox 拒絕時（`git rebase`、`git merge`、`kill`、push、進入別的 worktree），停下來回報，由 Leader 執行。push 一律由 Leader 做。
9. `swift test` 卡住時，subagent 不重跑；回報卡住的 PID，由 Leader 處理（指令見 `CLAUDE.md` §Commands）。
10. Subagent 卡關或進度差時，Leader 不接手實作：清理環境、寫更精確的 brief、重新派發。
11. 等 subagent 的時候，Leader 做不衝突的工作：下一個 brief、文件交叉檢查。不改 subagent 正在改的檔案。

回傳之後：

12. Reviewer 第一輪的小問題（改字、漏標 `Sendable`、章節順序）由 Leader 直接改；結構或行為的問題退回原 subagent 修。文件審查的輪數與裁定方式見 `collaboration-skills:subagent-review-cycles`。
13. 實作改了模組位置、檔名或狀態時，同一個 PR 內 grep `docs/` 與 `.claude/skills/`，把過期的路徑與狀態一起改掉。
14. 宣告一個 phase 或 feature 完成之前，對改動範圍跑：

    ```
    rg -n --no-heading -e 'TODO|FIXME|XXX|HACK|stub|placeholder|Phase [0-9]+ Part' Packages/<target>/Sources/
    ```

    每一條 match 必須屬於下列之一，否則不能宣告完成：
    - 已在本次修掉。
    - 已開 issue，並在 issue 附來源 `file:line`。
    - 在 PR 描述寫明刻意保留，並附後續追蹤的 issue。

    沒有 `TODO` 字樣的 stub 或 placeholder 程式碼也算。這個檢查由 Leader 做，不交給 subagent。

隨時：

15. 使用者中途追加約束時，先把它寫進負責的文件（`CLAUDE.md`、`docs/foundations.md` 或 issue），再繼續原本的工作。
16. 不熟的工具或 API，先讀 man page、官方文件或 README，再下指令。不用試錯的方式反推規格。
17. 與當下任務無關的想法不就地展開：開一個帶 `backlog` label 的 GitHub issue（指令與 label 見 `docs/foundations.md` §Backlog）。本 repo 不在文件裡維護 §Backlog 清單。

## 專案 skill 使用時機

只列本 repo 的專案 skill（`.claude/skills/`）。Plugin skill（`apple-dev-skills:`、`collaboration-skills:`）依各自的 description 觸發，這裡不列。

| Skill | 誰用 | 什麼時候 |
|---|---|---|
| `mise-task-operations` | 所有角色 | 要跑任何 build、scan、lint、產生、上傳指令之前 |
| `game-factory-composition` | Developer、Reviewer | 新增遊戲、改 `GameConfig` 或 `makeGameApp`、判斷某功能該共用還是各遊戲自有 |
| `interactive-sim-ux-audit` | Leader | 需要在 Simulator 實際操作 App 驗證流程 |
| `local-testflight-upload` | Leader | 要產生 archive 或上傳 TestFlight |
| `cloudkit-schema-ops` | Developer、Leader | 改 CloudKit record type、欄位或 index |
| `appstore-screenshot-pipeline` | Developer、Leader | 產生或更新 App Store 截圖 |
| `acknowledgements-generation` | Developer | 新增、移除或升級第三方 SwiftPM 相依 |
| `asc-ops-handoff` | Leader | 規劃或執行 App Store Connect 操作，判斷哪一步屬於使用者 |
