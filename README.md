# Sudoku-spec

iPhone + Mac 雙平台 Sudoku App。同 repo 同時容納：(a) spec 文件層（`docs/` / `meetings/` / `.claude/skills/`），(b) v1 實作（`App/` / `Packages/SudokuKit/` 將於 plan.md Phase 1 開始建立）。

> 2026-05-17 起合併原本規劃的 sibling `Sudoku/` repo 至本 repo；理由：portfolio 單一可閱讀單元，避免讀者 cross-repo 跳轉。

## 雙重交付目標

1. 上架一款可玩的 Sudoku App（iOS + macOS）。
2. 留下一份「如何把 Claude agent 應用在實際 iOS 專案」的可重現紀錄。

## 閱讀順序

1. [`docs/design.md`](docs/design.md) — 產品要做什麼（§What）與技術上怎麼做（§How）。
2. [`docs/plan.md`](docs/plan.md) — 由 design 推導出來的 TDD-ordered、可勾選實作計畫。
3. [`docs/methodology.md`](docs/methodology.md) — Claude agent 在本專案的應用模式。Living document。
4. [`meetings/`](meetings/) — 各次 session 的原始決策紀錄。上面三份文件「為什麼長成這樣」的真相來源。

## 現況

Spec 階段已收線，即將進入實作 Phase 0（generator prerequisite gates）。實作階段採 TDD。

## 安全姿態 — Public Repo

本 repo 為 **public spec repo from day 1**，不含任何 secret、PII 或可識別玩家資料。任何 commit 歷史均不得包含上述資料；違規一律視為已洩露並走 [`docs/foundations.md §7.3`](docs/foundations.md) SOP 處置。

本 repo 從第一個 commit 起就遵循 `docs/foundations.md §7` 全套規範（gitleaks pre-commit hook、Xcode Cloud `ci_post_clone.sh` secret scan、GitHub Secret Scanning Alerts、`.gitignore` 黑名單）。實作碼將於 Phase 1 起加入。
