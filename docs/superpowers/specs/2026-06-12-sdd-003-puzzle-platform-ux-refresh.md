# SDD-003 — Puzzle Platform UX Refresh (v2.6 / MS v1.1)

- **Status**: Approved（user-authored，2026-06-12 落地）
- **Author**: Wei
- **Scope**: Sudoku v2.6 · Minesweeper v1.1 · Shared Platform
- **Source**: 外部 SDD 討論（ChatGPT session「SDD 設計與需求整理」），本檔為 repo 正式版

## Background

Puzzle Platform 已完成 Sudoku、Minesweeper、Resume Infrastructure、Shared
Completion Flow、Shared Monetization、Shared Reminder Flow。近期 review 發現多項
UX 與產品規格不一致問題。本次調整以 **GameShellKit / GameAppKit 為優先修改層級**，
避免在 SudokuKit / MinesweeperKit 產生特規與分叉實作（mirror principle）。

## Goals

- **UX**: 統一遊戲進入/離開流程、簡化完成流程、修復 Reminder UX、修復 Resume
- **Business**: 提高 Banner Impression / Ad Revenue
- **Architecture**: 維持 Shared Layer 設計，避免兩款 app 分叉

## Architecture Constraints

### AC-001 Shared Layer First

以下功能必須實作於 `GameShellKit` / `GameAppKit`（依 zero-dep 規則分層），
禁止落在 SudokuKit / MinesweeperKit 特規，除非需求明確屬於遊戲規則：

Navigation Flow · Completion Flow · Banner Strategy · Resume Flow · Leave Confirmation

> 註：GameShellKit 維持 zero-dependency；需要 Persistence / Monetization 的部分
> 落在 GameAppKit（見 repo CLAUDE.md「mirror principle」）。

### AD-001 Banner Coverage Expansion 定性為 Feature（非 Bug）

目標：提高 Ad Impression / eCPM / Fill Rate。Current: Home + Board。

### AD-002 Pause Redesign 取消

維持現有 `PauseOverlayView` + Tap To Resume，**不列入本次 scope**
（Auto Pause / Auto Resume 不做）。

### AD-003 Completion Popup 不顯示 Banner

Banner 維持由底層 Game Screen 承載，Popup 內不處理廣告生命週期。

---

## Epic 1 — Game Navigation Redesign（P0）

Push → **Modal Presentation**（fullScreenCover）。

- **R1.1** Game View 改 present；禁止 Back 行為
- **R1.2** 右上角新增 `[X]` Close Button
- **R1.3** Timer 保持現況；Designer 可研究 Navigation Bar Item 形式（OQ-001）

## Epic 2 — Leave Confirmation（P0）

Trigger：點擊 `[X]`。

- Dialog — Title: `Leave Game?` / Message: `Your progress will be saved automatically.` / Actions: `Cancel` `Leave`
- **Cancel**: 返回遊戲，不影響 Timer
- **Leave**: Save Game State → Dismiss Game → Return Home
- Daily Challenge 進行中 Leave 後重新進入 = **Resume** Daily（非重開）
- Designer 建議：Bottom Sheet 而非 iOS 預設 Alert

**AC**: (2.1) 必定顯示 Dialog；(2.2) Cancel 不影響遊戲；(2.3) Leave 後成功保存進度。

## Epic 3 — Resume Game Fix（P0）

**Current problem**: Home 的 Resume Game 無法完整恢復遊戲。

恢復範圍：Board State · Notes · Elapsed Time · Mistakes · Difficulty · Daily Challenge State。

Investigation：盤點 `ResumeCandidate` / `ResumePill`（GameAppKit）+
`PersistenceKit` restore flow，確認缺失資料。

> 註：resume seam 本身已完工（見 `2026-06-10-resume-seam-design.md` §as-built，
> 兩款 app 的 `fetchResume` 已接線）。本 epic 修的是 seam 上游 —
> per-game persistence 保存/還原的資料完整性，勿重新設計 seam。

**AC**: (3.1) 棋盤一致；(3.2) Notes 一致；(3.3) Timer 一致；(3.4) Mistakes 一致；
(3.5) Daily Challenge 可恢復。

## Epic 4 — Completion Flow Redesign（P1）

Full Screen Completion → **Popup Completion**（GameShellKit `CompletionScreen`，
兩款 app 共用 — 這是 GameShellKit breaking change）。

- 移除：Retry · New Game · Leaderboard；保留：Close
  > 註：`CompletionScreen` 的 CTA 是各 app 經 `actions:` ViewBuilder 注入的——
  > 「移除」發生在各 app 的注入點，不是刪共用元件的按鈕；Close 由 `actions`
  > 注入或新增 `onClose` callback。
- 顯示：Success/Failed · Time · Mistakes
- Banner Rule：Popup 不顯示 Banner（AD-003）

## Epic 5 — Banner Coverage Expansion（P1，Feature）

Target 頁面全部掛 Banner：Home · Game · Daily · Settings · Statistics · Reminder Flow。

Architecture：由 GameShellKit 統一處理（如 `ScreenContainer = Content + BannerSlot`），
避免各畫面自行掛 `BannerSlotView()`。

> 註：`BannerSlotView` 在 AppMonetizationKit；GameShellKit 的 `ScreenContainer`
> **不得 import AppMonetizationKit**（zero-dep 規則）——banner slot 以閉包/
> ViewBuilder 注入，組裝在 GameAppKit。

CR Task：研究 Sudoku.com / Microsoft Sudoku / Minesweeper Classic 的 banner placement。

## Epic 6 — Reminder UX Fix（P0）— `ReminderPrimerSheet`

> 註：`ReminderPrimerSheet` 在 **SettingsKit**（SettingsUI/Reminders/），
> 不屬 AC-001 的 GameShellKit 範圍——就地修，勿搬移。

- **R6.1** 任意位置點擊產生 Highlight → 修正互動區域
- **R6.2** Not Now Button 無 Highlight → 補 Pressed / Focused / Accessibility state
- **R6.3** Sheet 可上拉造成 layout 損壞 → `.presentationDetents` / `isModalInPresentation` 限制拖曳
- **R6.4** 文字截斷 → 覆蓋 iPhone SE / 15 / 16 Pro Max + Large Text

## Epic 7 — Home Cleanup（P2）

Home 移除 `Remove Ads` button；Settings 入口保留。

## Epic 8 — Daily Challenge Failure UX（P2）

Proposed：失敗後顯示 `Failed / Score: 0`（保留歷史紀錄）。
CR Research：Sudoku.com / NYT Games / Microsoft Sudoku 的失敗呈現（OQ-002）。

## Epic 9 — Sudoku Interaction Fix（P0，Sudoku only）

預設數字（`isFixed == true`）：不可選取 · 不可編輯 · 不可 Highlight，點擊無反應。
Designer：定義 Fixed Cell vs Editable Cell 視覺差異。

---

## Not In Scope

Pause Flow Redesign · Auto Pause · Auto Resume（維持 `PauseOverlayView` + Tap To Resume）。

## Backlog — Game Center Achievements

掛上既有 `GameCenterKit` / `AchievementEvaluator`：
First Win · Perfect Run · 7 Day Streak · 30 Day Streak · Expert Solver。

## Sprint Plan

| Sprint | Priority | 內容 |
|---|---|---|
| 1 | P0 | Game Modal Flow · Leave Confirmation · Resume Fix · Reminder UX Fix · Sudoku Fixed Cell Fix |
| 2 | P1 | Completion Popup · Banner Coverage Expansion |
| 3 | P2 | Home Cleanup · Daily Failure UX · Achievement Expansion |

## Open Questions

- **OQ-001** Game View Timer 是否改為 Navigation Bar Item？（Owner: Designer）
- **OQ-002** Daily Challenge Failure 最終規則？（Owner: CR/PM）
- **OQ-003** Banner 是否涵蓋所有 Modal / Sheet？（Owner: CR/Designer/RD）
  建議流程：CR → Designer 視覺稿 → RD 實作，避免直接改 GameShellKit 後返工。
