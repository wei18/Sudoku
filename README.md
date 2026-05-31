# Sudoku-spec

iPhone 與 Mac 雙平台 Sudoku App。同一個 repo 同時容納兩層內容：

- 規格層：[`docs/`](docs/)、[`meetings/`](meetings/)、[`.claude/skills/`](.claude/skills/)。
- 實作層：`Sudoku/`（薄殼，只含 `@main` + DI composition root）與 `Packages/`（4 個本地 SPM package，見下）。

> 2026-05-17 起，原本規劃的 sibling `Sudoku/` repo 已合併進本 repo。理由：作為 portfolio，單一可閱讀單元優於跨 repo 跳轉。

## 雙重交付目標

1. 上架一款可玩的 Sudoku App（iOS 與 macOS）。
2. 留下一份「如何把 Claude agent 應用到實際 iOS 專案」的可重現紀錄。

## 閱讀順序

1. [`docs/v1/design.md`](docs/v1/design.md) — v1 產品要做什麼（§What）與技術上怎麼做（§How）。
2. [`docs/v2/design.md`](docs/v2/design.md) — v2 monetization layer（AdMob banner + Remove Ads IAP + UMP / ATT）。
3. [`docs/foundations.md`](docs/foundations.md) — 跨版本的工程平台決策（Swift 6、模組化、testing、CI、Logger、Tracking、secrets）。
4. [`docs/methodology.md`](docs/methodology.md) — Claude agent 在本專案的協作模式（含 §派發契約、Backlog 路由），持續更新。
5. [`meetings/`](meetings/) — 各次 session 的原始決策紀錄，是上述文件「為什麼長成這樣」的真相來源。

完整文件地圖見 [`docs/README.md`](docs/README.md)。

## 模組結構

```
Sudoku/                           # 薄殼：@main + DI composition root
Packages/
├── SudokuCoreKit/                # 純 Swift 核心：SudokuEngine + GameState（leaf，可移植 Android）
├── TelemetryKit/                 # Logger + Tracking 抽象 + TelemetryTesting fixtures
├── AppMonetizationKit/           # AdMob + IAP（third-party SDK 隔離，見 foundations §9）
└── SudokuKit/                    # PuzzleStore / Persistence / GameCenterClient / SudokuUI / AppComposition
```

依賴方向（內 → 外，禁止反向）詳見 [`docs/foundations.md §2`](docs/foundations.md)。

## 狀態

- **v1** — 程式碼層完工並上架（[`docs/v1/plan.md`](docs/v1/plan.md) Phase 0–9 全部 ship）。
- **v2.5** — Monetization layer 在 final sprint；AdMob banner 已 wire（test IDs），production IDs 待 v2.5.3 切換。Pre-flight 進度見 [`docs/v2/v2.5-readiness.md`](docs/v2/v2.5-readiness.md)。

實作階段採 TDD（swift-testing + swift-snapshot-testing）。

## 工具鏈（SSOT）

- **mise** — 工具版本鎖（`.mise.toml`）+ 任務 SSOT（`mise-tasks/` file-based tasks；lefthook / GH Actions / Xcode Cloud 三邊同源呼叫 `mise run <task>`）
- **lefthook** — pre-commit hooks（gitleaks、hygiene、swiftlint）
- **Xcode Cloud** — v1 主 CI 軌；PR / Main / Release 三 workflow
- **GitHub Actions** — Phase 1 advisory（`.github/workflows/lint.yml` 三 job：pr-metadata / docs-link-check / swift-lint）
- **Tuist** — 從 `Project.swift` 產生 `Game.xcodeproj`（Sudoku target + 未來 Minesweeper target 共 umbrella）

## 安全姿態：公開 repo

本 repo 自第一個 commit 起即為公開 spec repo，不含任何 secret、PII 或可識別玩家資料。任何 commit 歷史均不得包含上述內容；違規一律視為已洩露，並依 [`docs/foundations.md §7.3`](docs/foundations.md) SOP 處置。

本 repo 遵循 [`docs/foundations.md §7`](docs/foundations.md) 全套規範，包含 gitleaks pre-commit hook、Xcode Cloud `ci_post_clone.sh` secret scan、GitHub secret scanning alerts，以及 `.gitignore` 黑名單。
