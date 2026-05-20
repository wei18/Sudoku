# Sudoku v1 — 功能導覽

口語版的 App 功能介紹，給沒讀過 [`design.md`](design.md) 的人看。技術細節去那邊查；這份只談「玩家會經驗到什麼」。

更新：2026-05-20（v1 程式碼層完工，Phase 10 上架流程進行中）

---

## 🎮 玩法核心

兩種模式可以選：

- **Daily（每日挑戰）** — 全球玩家每天有 3 道題（簡單 / 中等 / 困難），時間從 UTC 00:00 reset。同一道題，看你比別人快多少完成。
- **Practice（自由練習）** — 想練哪個難度自己選，每次抽到不同的題、不會重複，純練手沒有時間壓力，也不會上排行榜。

## 📋 下棋盤面

標準 9×9 數獨格，你可以：

- 輸入 1-9 填格子
- **筆記模式**：每格塞 9 個候選小數字（適合困難題的推理）
- 填錯立刻有紅框提示，不用等到全填完才發現
- **Undo / Redo**（最多倒帶 20 步）
- 隨時 Pause，計時也會跟著停
- iPad + Mac 支援鍵盤操作（方向鍵移動、1-9 填字、delete 清除、`⌘Z` undo / `⌘⇧Z` redo）

## 💾 自動同步存檔

- 中途離開不會丟進度，玩到哪存到哪
- 同個 Apple 帳號的 iPhone + Mac 自動同步（透過 iCloud / CloudKit）
- 回到首頁會看到「上次玩到一半」的提示條，一鍵接著玩

## 🏆 Game Center 整合

- **3 條每日排行榜**（簡單 / 中等 / 困難各一條），看你 vs 全球 / vs 朋友
- **8 個成就**，總分 500 點：
  - 首次完成任何題（10 點）
  - 首次完成 Daily（20 點）
  - Daily 連 3 天 / 連 7 天（50 / 100 點）
  - 練習累積 10 題 / 100 題（30 / 100 點）
  - Hard 累積 25 題（100 點）
  - 同一天 3 難度全收（90 點）

## 🌏 7 個語言

繁中、英、日、簡中、西、泰、韓 —— 介面、Game Center 標題、App Store 描述都會跟著切。

## 🎨 設計風格

- 主色 sage 綠 `#5C7A4F`，背景 warm paper 米色 `#FAF8F3`
- Liquid Glass 模式卡片（iOS 26 / macOS 26 新效果）
- 完整 light / dark mode 切換
- 支援 Dynamic Type（系統字級放大功能）
- VoiceOver 朗讀完整、適合視障玩家

## 🔒 隱私姿態

- 不收個人資料、不接 Firebase / Mixpanel / 任何第三方追蹤
- 分析只用 Apple 自己的 MetricKit + os.Logger（資料只進 Xcode / App Store Connect 後台，玩家裝置外不外流）
- `PrivacyInfo.xcprivacy` 已宣告

## 🖥️ 跨平台

iPhone（iOS 26+）跟 Mac（macOS 26+）共用一份 codebase。SwiftUI multiplatform target，不是 Catalyst 的「iPad app 跑在 Mac 上」，而是真正的 Mac native。

---

## 目前狀態

- v1 程式碼**全部寫完**，364 個自動化測試全綠，25 張 UI snapshot 視覺驗證過
- 已修掉幾個 macOS smoke test 抓到的 bug（HomeView 點擊區、Mac sidebar 連結、ResumePill）

## 還沒做的（Phase 10 上架流程）

- Xcode Cloud 自動建置 workflows
- TestFlight 上傳第一個可裝 build
- 真機 Sandbox GameCenter / CloudKit 驗證
- App Store 商店素材（描述、截圖 × 7 locales）
- 送 App Store 審核
- Game Center 後台註冊已透過 `ASCRegister` CLI 進行中（API key 設好、setup wizard 完成、leaderboard POST shape 在迭代修正中）
