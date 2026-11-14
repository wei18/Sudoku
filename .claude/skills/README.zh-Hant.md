# 專案 Skills

> 英文版見 [`README.md`](README.md)。

本目錄收錄此專案可用的 skills，分兩部分：

1. **專案 skills**：下方列出的扁平 `SKILL.md` 目錄。它們寫的是本 repo 的 App
   （Sudoku、Minesweeper）、`mise run` 任務與 pipeline，不可移植，也沒有命名空間。
2. **Plugin skills**：可移植的 Apple 平台與 agent 協作 skills，來自
   [`wei18/apple-dev-skills`](https://github.com/wei18/apple-dev-skills)，以 git
   submodule 釘在 `apple-dev-skills/`。本 repo 啟用其中兩個 plugin：
   `apple-dev-skills:<skill>` 與 `collaboration-skills:<skill>`。

---

## 專案 skills

| Skill | 用途 |
|---|---|
| [`mise-task-operations`](mise-task-operations/SKILL.md) | 所有 `mise run` 任務的索引。執行或撰寫 ops 指令之前先查 |
| [`game-factory-composition`](game-factory-composition/SKILL.md) | 共用組裝模板（`GameConfig<Route>`、`makeGameApp`）、target 命名、哪些共用哪些各遊戲自有；新增遊戲 |
| [`interactive-sim-ux-audit`](interactive-sim-ux-audit/SKILL.md) | 在 iOS 模擬器操作 App 的專案設定：build 與安裝、DEBUG 啟動參數、登入狀態 |
| [`local-testflight-upload`](local-testflight-upload/SKILL.md) | 用 `mise run tf:upload` archive、export、上傳 TestFlight；上傳由 `--i-am-sure` 把關 |
| [`cloudkit-schema-ops`](cloudkit-schema-ops/SKILL.md) | 用 `mise run ck:schema` 匯出、驗證、部署 CloudKit schema；推到 Production 是使用者在 Console 的步驟 |
| [`appstore-screenshot-pipeline`](appstore-screenshot-pipeline/SKILL.md) | 擷取實機盤面、產生 App Store Connect 截圖、預覽與上傳 |
| [`acknowledgements-generation`](acknowledgements-generation/SKILL.md) | 用 `mise run gen:acknowledgements` 重新產生 `Settings.bundle` 授權頁 |
| [`asc-ops-handoff`](asc-ops-handoff/SKILL.md) | App Store Connect、TestFlight、AdMob 的步驟哪些屬於使用者、哪些 agent 可以執行；正式 AdMob ID 如何進入 build |

`screen-contract-spec` 不是專案 skill，它安裝在 user-level。
`docs/screen-contracts.md` 與 `docs/navigation-flows.md` 是它的實例。

---

## Plugin skills（`apple-dev-skills` submodule）

這個 submodule 是一個 Claude Code plugin marketplace。本 repo 啟用其中兩個 plugin：

- **`apple-dev-skills`**：Swift 6、SwiftPM、測試、CI、在地化、telemetry、
  模擬器與 Xcode 使用規範等 skills，以及 `swift-staff-reviewer` agent。
- **`collaboration-skills`**：Leader 與 Developer 的協作 skills（派發 brief、
  審查循環、spec 編排、PR diff 驗證）。

接線已經 commit：

- submodule 釘在 `wei18/apple-dev-skills` 的一個確切 release。clone 之後執行
  `git submodule update --init`。
- `.claude/settings.json` 把 submodule 宣告為本地 plugin marketplace，並啟用這兩個
  plugin。clone 並 trust workspace 之後 Claude Code 會自動註冊，不需要
  `/plugin install`。

Plugin skills 的目錄在 [`apple-dev-skills/README.md`](apple-dev-skills/README.md)。
只有那個檔案列出它們；本檔不寫數量。

> `docs/superpowers/` 是一般的 tracked files，不是 submodule，不在此編目。

---

## 為何這些 skills 放在 repo 內

- 這個 repo 是公開的，skill set 是「把 Claude agent 用在真實專案」這份紀錄的一部分。
- 任何人 clone（含 submodule）並 trust workspace，就得到相同的 skills。
- Skills 隨專案演進，每次修改都是可審查的 diff。
