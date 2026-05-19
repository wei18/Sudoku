# Sudoku-spec

iPhone 與 Mac 雙平台 Sudoku App。同一個 repo 同時容納兩層內容：

- 規格層：[`docs/`](docs/)、[`meetings/`](meetings/)、[`.claude/skills/`](.claude/skills/)。
- 實作層：`App/` 與 `Packages/SudokuKit/`，將於 [`docs/plan.md`](docs/plan.md) Phase 1 起建立。

> 2026-05-17 起，原本規劃的 sibling `Sudoku/` repo 已合併進本 repo。理由：作為 portfolio，單一可閱讀單元優於跨 repo 跳轉。

## 雙重交付目標

1. 上架一款可玩的 Sudoku App（iOS 與 macOS）。
2. 留下一份「如何把 Claude agent 應用到實際 iOS 專案」的可重現紀錄。

## 閱讀順序

1. [`docs/design.md`](docs/design.md) — 產品要做什麼（§What）與技術上怎麼做（§How）。
2. [`docs/plan.md`](docs/plan.md) — 由 design 推導出來、依 TDD 順序排列的可勾選實作計畫。
3. [`docs/methodology.md`](docs/methodology.md) — Claude agent 在本專案的應用模式，持續更新。
4. [`meetings/`](meetings/) — 各次 session 的原始決策紀錄，是上述三份文件「為什麼長成這樣」的真相來源。

## 狀態

v1 程式碼層已完工（[`docs/plan.md`](docs/plan.md) Phase 0 至 Phase 9 已執行完畢）。剩下 Phase 10 為操作型工作，內容包含：

- App Store Connect 後台設定。
- TestFlight 發佈。
- 簽署與憑證。

實作階段採 TDD。

## 安全姿態：公開 repo

本 repo 自第一個 commit 起即為公開 spec repo，不含任何 secret、PII 或可識別玩家資料。任何 commit 歷史均不得包含上述內容；違規一律視為已洩露，並依 [`docs/foundations.md §7.3`](docs/foundations.md) SOP 處置。

本 repo 遵循 [`docs/foundations.md §7`](docs/foundations.md) 全套規範，包含 gitleaks pre-commit hook、Xcode Cloud `ci_post_clone.sh` secret scan、GitHub secret scanning alerts，以及 `.gitignore` 黑名單。
