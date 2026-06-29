[English](README.md) | 繁體中文

# Sudoku-spec

兩款沉靜、尊重隱私、跨平台的邏輯遊戲——建構於單一 monorepo 中，這個 repo 同時是一份作品集，展示 (a) 乾淨、模組化的 **Swift 6** 架構，以及 (b) 一套有完整文件紀錄的**人類 + Claude agent 工程協作流程**。

- **Sudoku** 是主要 App（功能完整、App Store 送審進行中）。
- **Minesweeper** 是第二款 App，存在的目的是驗證共用的 `GameShellKit` 架構能組裝出一款新遊戲——它在每一層都鏡像 Sudoku，唯一不同的是玩法畫面。

兩款 App 皆以單一 codebase 同時運行於 **iPhone 與 Mac**，透過玩家自己的 iCloud 同步，並刻意維持極小的足跡：無自家分析、除 iCloud 外無帳號、無追蹤——在含商業模式的 build 中，廣告也僅限於一個可移除的 banner。

> 本 repo **自第一個 commit 起即為公開**。每一個架構決策、每一輪審查、以及完整的協作方法論，都可在 `docs/`、`meetings/` 與 `.claude/skills/` 中閱讀。這份公開性本身就是重點之一。

---

## 兩款 App

| | **Sudoku**（主要） | **Minesweeper**（第二款 App） |
|---|---|---|
| 一句話 | iPhone 與 Mac 上的每日 & 練習邏輯遊戲 | 經典玩法，化繁為靜——iPhone 與 Mac |
| 狀態 | 功能完整；v2.6 monetization（banner + Remove-Ads IAP）；App Store 送審進行中 | 除棋盤外每一層皆鏡像 Sudoku——已建置並測試；v2.6，App Store 送審進行中 |
| 模式 | Daily（每日 3 題、全球同題、進排行）+ Practice（隨機、不計排行） | Beginner / Intermediate / Expert，首次點擊必安全 |
| 跨裝置 | 存檔與紀錄經 iCloud Private DB 同步 | 設定與購買狀態經 iCloud 同步；尚無存檔續玩流程 |
| 平台 | iOS 26 / macOS 26，真正的 SwiftUI Mac App（非 Catalyst） | 同上 |

**兩款 App 共通的理念。** 不收集任何個人資料、不嵌入第三方分析 SDK。存檔存於玩家自己的 iCloud Private Database；Game Center 提交交由 Apple 處理。在含商業模式的 build 中，*唯一*的第三方 SDK 是 Google 的 banner 廣告函式庫，隔離於單一模組內——且該 banner 可透過一次性、非消耗型的 In-App Purchase 永久移除。

---

## 這個 repo 為什麼值得一看

這不是一個教學專案。它是一個真實、公開的 iOS codebase，並列承載兩條獨立的敘事：

1. **一套乾淨的模組化 Swift 6 架構**，刻意切分，好讓*第二款*遊戲能複用第一款的殼。
2. **一份將 Claude agent 應用於實際上架 iOS 專案的可重現紀錄**——一套 Leader / Developer 狀態機方法論，並完整保留原始決策紀錄。

---

## 架構

整個 codebase 是兩層薄殼 App，疊在一組本地 Swift Package Manager package 之上。每個 App target 只含 `@main`、Info.plist / entitlements / assets，以及一個 DI composition root；所有畫面、邏輯與儲存都在 package 內。

```
Sudoku/                      # 薄殼：@main + DI composition root
Minesweeper/                 # 薄殼：@main + DI composition root（鏡像 Sudoku）
Packages/
├── SudokuCoreKit/           # 純 Swift 核心：SudokuEngine + GameState（leaf，可移植）
├── MinesweeperCoreKit/      # 純 Swift 核心：MinesweeperEngine + MinesweeperGameState（leaf）
├── TimeKit/                 # 純 Swift 核心：UTCDay 日期工具 + MonotonicClock（leaf，可移植）
├── DeterminismKit/          # 純 Swift 核心：SplitMix64 / DeterministicRNG，兩引擎共用（leaf）
├── TelemetryKit/            # Logger + Tracking 抽象 + TelemetryTesting fixtures
├── PersistenceKit/          # CloudKit Persistence + PersistenceTesting
├── GameCenterKit/           # GameCenterClient + GameCenterTesting
├── RemindersKit/            # 共用本地通知提醒（UserNotifications 隔離於 Live）
├── GameAudioKit/            # 共用 SFX / BGM / 觸覺回饋音訊引擎（AVFoundation 隔離於 Live）
├── GameShellKit/            # GameShellUI——兩款 App 共用的導覽殼
├── SettingsKit/             # SettingsUI——兩款 App 共用的設定區塊
├── GameAppKit/              # 共用 app-composition 層:GameRootViewModel / GameRoot / ResumePill / ResumeCandidate
├── AppMonetizationKit/      # MonetizationCore/UI + AdsAdMob + IAPStoreKit2（第三方 SDK 隔離）
├── SudokuKit/               # Sudoku 專屬：PuzzleStore / SudokuUI / AppComposition
├── MinesweeperKit/          # Minesweeper 專屬：MinesweeperUI / MinesweeperAppComposition
└── ASCRegisterKit/          # macOS-only 的 App Store Connect dev CLI（不在任一 App binary 內）
```

**依賴只向內**（leaf 核心 ← 共用 kits ← 各 App kits ← App target；禁止反向 import——見 [`docs/foundations.md §2`](docs/foundations.md)）。幾條原則撐起整個形狀：

- **可移植的 leaf 核心。** `SudokuCoreKit` 與 `MinesweeperCoreKit` 只 import Foundation——不碰任何 Apple framework——所以這套題目 / 引擎數學可被搬到另一個前端（Android port 是明確列在 backlog 的項目）。
- **受限的 framework import。** CloudKit 只存在於 `PersistenceKit`、GameKit 只在 `GameCenterKit`、UserNotifications 只在 `RemindersKit` 的 Live 檔、Google Mobile Ads SDK 只在 `AppMonetizationKit/AdsAdMob`。上層一律透過 protocol seam 取用，讓 UI 與邏輯層維持可單元測試、可 preview。
- **共用一個殼，而非複製貼上。** 當 Minesweeper 需要同樣的導覽、hub、toast 與 banner-slot 介面時，這些被抽進 `GameShellKit`（`GameShellUI`），而非複製；共用的設定區塊則放在 `SettingsKit`（`SettingsUI`）。第二款 App 複用這個殼，只交付*自己*的玩法 UI 與真正不同的部分——這正是「Minesweeper 除了棋盤之外鏡像 Sudoku」之所以是事實、而非口號的原因。
- **Game-prefixed target。** 當兩款遊戲需要同一個 domain target 時（每款遊戲都有自己的 `GameState`），名稱以遊戲名前綴（`MinesweeperEngine`、`MinesweeperGameState`、`MinesweeperUI`），讓 Tuist 生成的 Xcode workspace 無 module 名稱衝突；真正共用的 target 則以*功能*命名（`GameShellUI`）。

---

## AI 協作這條線

這個 repo 同時是一份在實際 iOS 專案上運行 Claude agent 的工作紀錄。三個層次與程式碼並列：

- **`docs/`** — 規格層。產品與技術設計（`v1/`、`v2/`）、跨版本的工程 foundations，以及方法論本身。
- **`meetings/`** — 原始、有日期的決策紀錄。它們是 docs「為什麼長成這樣」的真相來源，包含審查輪次、被否決的替代方案，以及 root-cause 分析。
- **`.claude/skills/`** — 從反覆出現的 pattern 結晶出的專案專屬、可複用 agent skills（例如 AdMob 識別碼的 build-time secret 注入 pattern）。

協作模型是一套 **Leader / Developer 狀態機**，定義於 [`docs/methodology.md`](docs/methodology.md)：

- **Leader**（協調的 session）理解意圖、撰寫並審核文件、拆解工作、派發任務——但不直接寫實作程式碼。
- **Developer / Reviewer / Designer / Architect** 子 agent 依照精確的派發契約（scope、應讀文件、應 invoke 的 skill、回傳格式、驗證標準）進行實作、審查與設計，其產出在抵達使用者之前一律由 Leader 把關。

工作沿著明確的狀態推進——`GOAL_RECEIVED → PROPOSAL → RFC → USER_APPROVED → IMPL → CLOSED`——並在改動規模大或觸及敏感模組時插入一輪 code review。方法論文件也記錄了跨 phase 觀察到的**模式**與**反模式**，這部分最能直接複用到另一個專案。

---

## Repo 地圖與閱讀順序

1. [`docs/v1/design.md`](docs/v1/design.md) — v1 做什麼（§What）與技術上怎麼做（§How）。
2. [`docs/v2/design.md`](docs/v2/design.md) — v2 monetization layer（AdMob banner + Remove-Ads IAP + UMP / ATT）。
3. [`docs/foundations.md`](docs/foundations.md) — 跨版本的工程平台決策（Swift 6、模組化、testing、CI、Logger、secrets）。
4. [`docs/methodology.md`](docs/methodology.md) — Claude agent 協作模式、派發契約與 backlog 路由。
5. [`meetings/`](meetings/) — 上述一切背後的原始 per-session 決策紀錄。

完整文件地圖見 [`docs/README.md`](docs/README.md)；可複用的 agent skills 見 [`.claude/skills/`](.claude/skills/)。

> 原本規劃為獨立 codebase 的 sibling `Sudoku/` repo 已於 2026-05-17 合併進本 repo——作為作品集，單一可閱讀單元優於跨 repo 跳轉。

---

## 技術事實

- **語言：** Swift 6 語言模式 + **complete** concurrency checking，從第一行程式碼起套用。
- **打包：** Swift Package Manager——一組本地 package、薄 App target。
- **平台：** iOS 26 / macOS 26 為底線（為採用 Liquid Glass API）；Mac build 是真正的 SwiftUI App，非 Catalyst。
- **測試：** [swift-testing](https://github.com/swiftlang/swift-testing) 跑單元 / 整合測試（不用 XCTest），加上 [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing)；CloudKit 與 Game Center 透過 protocol fakes 驗證，讓測試套件能在乾淨的 CI runner 上跑過。
- **Apple 服務：** CloudKit（private-DB 存檔 / 紀錄同步）與 Game Center（recurring daily leaderboards + 成就，Sudoku）。
- **CI / 工具鏈：** Xcode Cloud 為主 CI 軌（PR / Main / Release workflow）、advisory 的 GitHub Actions 做 lint / link / metadata 檢查、[Tuist](https://tuist.io) 從 `Project.swift` 生成 umbrella `Game` Xcode project、[mise](https://mise.jdx.dev) 為版本 + 任務的 source of truth，並以 lefthook + gitleaks 做 pre-commit hook。
- **商業模式（v2，Sudoku）：** 單一可移除的 AdMob banner 與一次性 Remove-Ads IAP，含 UMP consent 與 ATT，全部隔離於 `AppMonetizationKit` 內。

---

## 安全姿態

這是一個公開的 spec repo，且自第一天起即如此。任何 commit 都不得出現 secret、PII 或可識別玩家資料——由 gitleaks pre-commit hook、Xcode Cloud post-clone secret scan、GitHub secret-scanning alerts，以及 `.gitignore` 黑名單共同把關。「上架後本就 app-public、但上線前敏感」的識別碼（如 AdMob ID）採 build-time 注入而非進 git。完整規範見 [`docs/foundations.md §7`](docs/foundations.md)。
