# 專案 Skills

> 英文版見 [`README.md`](README.md)。

本目錄收錄此專案可用的 skills，分兩部分：

1. **專案綁定 skills（8）**——下方扁平的 `SKILL.md` 目錄。這些點名本 repo 的特定
   App（Sudoku／Minesweeper）、`mise run` 任務與 pipeline，**不可移植**，
   故留在此處、無命名空間。
2. **`apple-dev-skills` marketplace（2 個 plugin，32 skills）**——可移植的 Apple 平台／
   AI agent 協作 skills 已抽離至
   [`wei18/apple-dev-skills`](https://github.com/wei18/apple-dev-skills)，以 git
   submodule 釘在 `apple-dev-skills/`、以 **兩個** Claude Code plugin 載入：
   **`apple-dev-skills:<skill>`**（20，Apple 平台工程）與
   **`collaboration-skills:<skill>`**（12，Leader-Developer 協作模式）。

---

## 專案綁定 skills（8）

| Skill | 一句話 |
|---|---|
| [`game-factory-composition`](game-factory-composition/SKILL.md) | 共用組裝模板——GameAppKit 的 `GameConfig<Route>` + `makeGameApp`、`<Game><Concern>` 命名、共用 Home／DailyHub-skeleton／board-redirect／GC-dashboard；只有 Game module 是 per-game（SDD-005） |
| [`mise-task-operations`](mise-task-operations/SKILL.md) | 每個 repo ops 任務的索引／入口——動手 grep「X 怎麼做」前先看這；每個 `mise run` 任務 → 呼叫法＋安全閘＋owning skill |
| [`local-testflight-upload`](local-testflight-upload/SKILL.md) | 本地 archive→export→TestFlight（`mise run tf:upload`）；Xcode-Cloud-Main-CI 的暫代；上傳由 `--i-am-sure` 把關 |
| [`cloudkit-schema-ops`](cloudkit-schema-ops/SKILL.md) | 以 `mise run ck:schema`（`xcrun cktool`）匯出／驗證／部署 CloudKit schema；`.ckdb` 為真相；正式環境推送＝CloudKit Console（user-owned） |
| [`appstore-screenshot-pipeline`](appstore-screenshot-pipeline/SKILL.md) | 以 `mise run store:screenshots` 從 snapshot baseline 同步 App Store 截圖 PREVIEW；symlink、僅預覽（非送審規格） |
| [`acknowledgements-generation`](acknowledgements-generation/SKILL.md) | 以 `mise run gen:acknowledgements`（LicensePlist）從 SwiftPM 依賴圖重生 Settings.bundle 致謝頁；輸出 gitignored |
| [`asc-ops-handoff`](asc-ops-handoff/SKILL.md) | App Store Connect／TestFlight 哪些步驟 user-owned、哪些 Leader 可經 ASC API + ASCRegister 下令 |
| [`interactive-sim-ux-audit`](interactive-sim-ux-audit/SKILL.md) | 用 idb 在 iOS 模擬器驅動遊戲 App（tap／describe／screenshot），找 snapshot 測不到的 UX／佈局 bug |

**已搬遷：** `screen-contract-spec` 已非專案綁定——方法論正本已移至 design-app playbook
（`~/GitHub/Wei18/design-app/skills/`），以 `bash skills/install.sh` 安裝到 user-level 生效。
本 repo 的 `docs/screen-contracts.md`＋`docs/navigation-flows.md` 仍是 worked example。

---

## `apple-dev-skills` marketplace（2 個 plugin，32 skills，帶命名空間）

可移植 skills 住在 [`apple-dev-skills`](apple-dev-skills/README.md) submodule——
一個 Claude Code plugin **marketplace**，內含兩個 plugin：

- **`apple-dev-skills`**（20）——Swift 6／SwiftPM／測試／CI／L10n／telemetry 預設；
  以 `apple-dev-skills:<skill>` 出現。
- **`collaboration-skills`**（12）——Leader-Developer 協作模式（派工契約、審查循環、
  spec 編排）；以 `collaboration-skills:<skill>` 出現。

接線已 commit、可重現：

- **submodule** `apple-dev-skills/` 釘確切版本（commit SHA）。
- **`.claude/settings.json`**（project scope）宣告它為 local-path plugin marketplace
  並啟用**兩個** plugin；clone ＋ trust workspace 後 Claude Code 自動註冊——
  **不需手動 `/plugin install`**。

32 個完整索引見 [`apple-dev-skills/README.md`](apple-dev-skills/README.md)。

> `superpowers` 內容以一般 tracked files 形式存在於 `docs/superpowers/`（並非 git submodule）；
> `.gitmodules` 只宣告了 `apple-dev-skills`。不在此編目。

---

## 為何這些 skills 放在 repo 內

- **repo 從第一天起即公開**，此 skill set 是「Claude agent 應用紀錄」展示的一部分。
- **可重現性**：任何人 clone（含 submodule）＋ trust workspace 即得到相同 skill set。
- **演進透明**：skills 隨專案演進，PR 留下 diff 軌跡。
