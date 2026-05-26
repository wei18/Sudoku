# Foundations — 工程底層與工具

狀態：**FINAL** — §1–§8 全部於 plan.md Phase 0–9 落地驗證（2026-05-19）。
最後更新：2026-05-19

本文件記錄 Sudoku 專案的工程平台選擇：語言版本、模組化、測試、CI、Logger、Tracking、Agent skills。這些決策在產品規格（`docs/v1/design.md`）之前定下，是 `docs/v1/design.md §How` 與 `plan.md` 的依附基礎。

章節順序：
1. Swift 6 / strict concurrency
2. Swift Package 模組化策略
3. Testing（swift-testing + swift-snapshot-testing）
4. CI（Xcode Cloud 單軌）
5. Logger
6. Tracking / Analytics
7. Secrets 與 public repo 規範
8. Agent skills 選用

---

## §1 Swift 6 / Strict concurrency

**決策**：Swift 6 語言模式 + **complete** concurrency checking，從專案第一行程式碼起即套用。

**牽連**：
- 工具鏈最低需求：**Xcode 16+**（首個正式支援 Swift 6 language mode 的版本）。
- 部署目標最低需求：**iOS 26 / macOS 26**。理由：對齊 §4 鎖定的 Xcode 26.5 工具鏈、保留 Liquid Glass（`.glassEffect()` 為 iOS 26+ API）；本 App 無向下相容歷史包袱、屬個人作品兼案例展示，cut off 26 以下用戶可接受。**偏離 [[apple-platform-targets]] 的 iOS 18 / macOS 15 預設**——該 skill 為一般專案預設，本專案因 Liquid Glass 採用而上調。
- 所有自寫型別預設視為需要 `Sendable`；跨 actor 共享型別必須顯式宣告。
- 第三方相依若尚未支援 Swift 6 complete check，需評估：(a) 用 `@preconcurrency` 隔離匯入、(b) 換套件、(c) 暫緩採用。此議題在 §2、§3、§5、§6 各別套件選擇時逐一核對。

**理由**：
- 全新專案，沒有歷史程式碼可遷移，complete checking 的痛點被攤平到「每寫一段 actor/Sendable」就解一次，而不是日後一次性遷移。
- 與「雙重交付目標」吻合：本 repo 作為案例展示，採用語言最前緣有展示價值。



## §2 Swift Package 模組化

**決策**：

1. **單 Package 多 target**：所有 module 收在一個 `SudokuKit` Swift Package 內，以 target 切分。
2. **App target 極薄**：只含 `@main`、`App` struct、Info.plist、entitlements、Assets，以及一個 DI composition root（把 protocol 與具體實作接起來）。所有畫面、邏輯、Storage 都在 Package。
3. **Package platforms 與 App target 對齊**：`iOS 26 / macOS 26`，與 §1 一致。
4. **Apple 框架 import 範圍受限**：`CloudKit` 只在 `PuzzleStore` + `Persistence` 直接 import；`GameKit` 只在 `GameCenterClient`。`SudokuUI` 與 `GameState` 透過 protocol 注入使用，不直接 import — 便於 UI/邏輯層的單元測試與 SwiftUI preview。**例外（issue #49, 2026-05-20）**：`SudokuUI/Leaderboard/GameCenterDashboard.swift` 直接 `import GameKit` / `UIKit` / `AppKit`，因 Apple 原生 Game Center dashboard（`GKAccessPoint` / `GKGameCenterViewController`）為終端 UI 表面、無 protocol-injectable seam 可走。檔案層級的局部 import 不污染 SudokuUI 其餘 Views 的測試性（其他 View 仍透過 `any GameCenterClient` 注入）。
5. **測試 target 一對一**：每個 production target 對應一個 `<Module>Tests` target。

**目標模組形狀**（同 repo，與 `docs/` / `meetings/` / `.claude/` 並列）：

```
<repo root>
├── App/                                # 薄殼
│   ├── SudokuApp.swift                 # @main + DI composition root
│   └── (Assets, Info.plist, entitlements)
└── Packages/
    └── SudokuKit/
        ├── Package.swift               # platforms: [.iOS(.v26), .macOS(.v26)]
        └── Sources/
            ├── SudokuEngine/           # 純 Swift 核心：board / rules / validator
            ├── GameState/              # 進行中局面：moves, undo/redo, notes
            ├── PuzzleStore/            # Puzzle source (v1 wraps local generator; v2 may add Public DB override)
            ├── Persistence/            # CloudKit private DB 存檔 / 紀錄同步
            ├── GameCenterClient/       # GC 排行 / 成就
            ├── Telemetry/              # Logger + Tracking 抽象（§5、§6 補完）
            └── SudokuUI/               # SwiftUI Views / ViewModels
        └── Tests/
            └── (每 production target 一個對應 *Tests target)
```

**依賴方向**（內 → 外，禁止反向）：

```
SudokuEngine  ←  GameState
                 ↑
                PuzzleStore, Persistence, GameCenterClient, Telemetry
                 ↑
                SudokuUI
                 ↑
                App target
```

**理由**：
- 單 Package：本 App 內模組無對外發佈需求，多 Package 只徒增 `Package.swift` 維護成本與 CI 解析時間。
- App target 極薄：所有可測邏輯都在 Package，App target 不需要被測試（也測不動）；SwiftUI preview 也直接從 Package 內跑。
- 框架 import 受限：是真正能落實「核心邏輯可移植到 Android」（見 backlog 第 2 條）的前提。

**演進（2026-05-26 module split）**：

`SudokuEngine` + `GameState` 已從 `SudokuKit` 抽離到 sibling local package `Packages/SudokuCoreKit/`，原因是要解 `Telemetry → GameState/SudokuEngine` 在 package 層級的耦合（同 package 內的 target 即使沒有直接 import，也綁在同一個 `Package.resolved` / build graph 上，未來若想單獨抽出 Telemetry 會被卡住）。決策細節見 `meetings/2026-05-26_module-split-proposal.md`。

- **抽出的範圍**：只動 `SudokuEngine`（純 Foundation）、`GameState`（→ SudokuEngine）兩個葉子 target；對應 test target 同步搬移。
- **未抽出的範圍**：`PuzzleStore` / `Persistence` / `GameCenterClient` / `Telemetry` / `SudokuUI` / `SudokuKitTesting` / `AppComposition` 仍留在 `SudokuKit`。Telemetry-only 抽出的 cost/benefit 暫不划算，本次只做 prerequisite。
- **依賴方向不變**：上方 §2 的 dep 圖仍然成立；差異只在 `SudokuEngine` 與 `GameState` 現在以 `.product(name:package:"SudokuCoreKit")` 形式被 SudokuKit 的其他 target 依賴。
- **Package naming convention**：sibling local packages 以 `<Domain>Kit` 命名（產品名或功能域 + `Kit` 後綴）— 目前 `SudokuKit` / `SudokuCoreKit` / `AppMonetizationKit` 各自符合。未來抽出（例：`TelemetryKit`）沿用同模式。

## §3 Testing 工具鏈

**決策**：

1. **單元 / 整合測試框架：swift-testing**，完全不採用 XCTest。理由：swift-testing 為 Apple 官方、Swift 6 對應佳；無歷史程式碼包袱所以零成本切換。
2. **快照測試框架：`pointfreeco/swift-snapshot-testing`**（swift-testing 對應版的 `assertSnapshot`）。
3. **快照覆蓋面（v1）**：先從**主要遊戲畫面**起步，逐步擴充至其他對外 View。每張快照同時覆蓋多語、iPhone / Mac、淺/深色、典型狀態（空棋盤 / 進行中 / 完成）。
4. **CloudKit / Game Center 測試替身**：`PuzzleStore`、`Persistence`、`GameCenterClient` 各定義一個 protocol；production 用具體實作，測試用 fake / stub。**單元測試不碰真實網路、CI 不跑 CloudKit/GC integration test**。真實互動只在開發機手動驗證。
5. **測試命名**：以「被測類型」分檔，如 `SudokuEngineTests/BoardTests.swift`；以 swift-testing `@Suite` 聚合相關 case。
6. **Snapshot 圖檔位置**：預設 `__Snapshots__/` 在 test 檔旁，**進 git**，方便 PR 審查時看視覺 diff。

**測試金字塔（v1）**：

```
            ┌─────────────────────┐
            │  Snapshot (UI)      │  少量、由主畫面起步
            ├─────────────────────┤
            │  Integration        │  PuzzleStore/Persistence/GC fakes
            │  (with fakes)       │
            ├─────────────────────┤
            │  Unit (logic)       │  最多、最快：Engine + GameState
            └─────────────────────┘
```

**牽連到 §4 CI**：
- 所有 test 必須能在純 CI runner（無 iCloud 帳號、無 Game Center 登入）跑過。
- Snapshot 在不同平台會產生不同基準圖；CI runner 的 OS / Xcode 版本需與基準圖一致，否則改動需更新 snapshot。



## §4 CI（Xcode Cloud 單軌）

**決策**：v1 CI 全押 **Xcode Cloud**；GitHub Actions 暫不採用（見 backlog 第 6 條的啟用條件）。Repo 仍 host 在 GitHub。

**Phase 1 GH Actions 補強（2026-05-26，advisory only）**：合併成單一 `.github/workflows/lint.yml`，內含 3 個 sibling jobs — `pr-metadata`（PR title Conventional Commits lint, ubuntu）、`docs-link-check`（`docs/` + `meetings/` lychee 連結檢查, ubuntu）、`swift-lint`（SwiftLint strict, ubuntu — swiftlint linux binary via mise；2026-05-26 user 決定移除 swiftformat 為 redundant）。三 job 透過 `gh api pulls/{n}/files` 拿改動檔案列表（不再用 `git diff` + fetch-depth 0）。皆為 advisory（未 required）；branch protection 與 required status check 屬 Phase 3（user-owned，issue #158）。Phase 2（PR 上的 review agent + meetings index 自動更新）待 GitHub App bot 身分就位再做（issue #156、blocked on #157）。

### Workflow 配置

v1 共 **3 條 workflow**（PR / Main / Release）；無排程 / cron 類 workflow（題目改由 App 本機 deterministic 產生，無 server-side 投放需求 — 詳見 `docs/v1/design.md §How.4`）。

| Workflow | 觸發 | 動作 |
|---|---|---|
| **PR CI** | PR open / push（**啟用「Merge with base branch before building」**）| Build + Test（單元 / 整合 fakes / snapshot）|
| **Main CI** | merge 到 `main` | Build + Archive + **上傳 internal TestFlight**；**不重跑 test**（已由 PR CI 在 pre-merged 狀態驗證）|
| **Release** | git tag `v*` | Build + 上傳 App Store Connect（手動送審）|

### 環境鎖定

- **Xcode 26.5**，與本機 `.mise.toml` 鎖同版。
- 升 Xcode 時 → 開一張集中更新所有 snapshot 基準圖的 PR。
- Test 環境關閉 iCloud / Game Center 登入；所有 test 走 protocol fakes（§3）。
- `ci_scripts/` 內任何工具優先透過 `mise` 啟用，避免 Xcode Cloud 預裝版本飄移。
- **Acknowledgements 頁（App Store 第三方授權清單）**：由 LicensePlist 在 `ci_post_clone.sh` 跑 `mise exec ubi:mono0926/LicensePlist -- license-plist` 從 SwiftPM dep graph 自動產 `App/Resources/Settings.bundle/`（iOS 標準位置，顯示於 Settings.app → Sudoku → Acknowledgements）。Source of truth: 倉庫根 `license_plist.yml`；產出檔 `.gitignore`'d，每次 build 重生。**本機 dev 環境不自動重生**（`Project.swift` 用 `.glob` 容忍空匹配，App 仍能本地 build；Acknowledgements 頁僅 release surface）；若需本機驗證，手動跑 `mise exec ubi:mono0926/LicensePlist -- license-plist`。

### 已知 race condition

兩個 PR 各自 pre-merge 通過、相繼 merge 時，**它們的合併結果**沒被測過。對個人專案幾乎不會踩；多人協作如需收斂，未來可以：
- 在 GitHub 啟用 「Require branches to be up to date before merging」
- 或在 Main CI 加回最低限度的 smoke test



## §5 Logger

**決策**：

1. **採用 Apple 內建 `os.Logger`**（`OSLog`），不引第三方 logging 套件。理由：與 Console.app / Instruments / unified logging system 原生整合；零相依；Swift 6 對 actor / Sendable 友善；privacy interpolation 原生支援。
2. **命名規則**：
   - `subsystem` = bundle ID（如 `com.wei18.sudoku`）
   - `category` = 模組名（`SudokuEngine`、`GameState`、`PuzzleStore`、`Persistence`、`GameCenterClient`、`SudokuUI`）
   - 在 Console.app 可依 category 分流檢視。
3. **Privacy 預設**：所有 string interpolation 預設視為 `.private`，需要 `.public` 必須顯式標註（如 `\(value, privacy: .public)`）。Private 內容在跨裝置 Console.app 讀取 / sysdiagnose 中會被遮罩；但**本機 Xcode debugger attach 到 running process 時 private 值仍可見**——意味測試者在 TestFlight 自家 Console 可能看到，正式發布後在他人 sysdiagnose 才完全遮罩。

### 在 Telemetry 架構中的位置

```
應用層程式碼
   │
   │ telemetry.observe(event)
   ▼
Telemetry (facade, in `Telemetry` target)
   │
   ├──► OSLogSink            (人類除錯訊息；對所有事件感興趣)
   ├──► TrackingSink         (產品分析；只挑商業事件 — §6)
   └──► [future sinks]
```

- `OSLogSink` 是 `TelemetrySink` 的具體實作之一，包在 `Telemetry` target 內。
- 應用層也可以直接呼叫 logger（例如純除錯訊息），但商業事件**一律**走 `telemetry.observe(...)` 由 facade fan-out。

### 留給 §6 的接口

`TrackingSink` 在 §6 確認 provider 後實作；本節不卡 §6 的選擇。



## §6 Tracking / Analytics

**決策**：v1 走 **Apple 三件套**，不引入第三方 tracking SDK。

### 三件套職責

| 來源 | 提供什麼 | 看哪裡 |
|---|---|---|
| **App Store Connect Analytics** | 下載、Session、活躍裝置、留存、來源、商店轉換 | App Store Connect 網頁 |
| **MetricKit** (`MXMetricPayload`) | 效能與診斷：crash、hang、launch time、jank、能耗、記憶體 | App 自己收 → 由 `MetricKitSink` 落地成 log / 將來可上傳 |
| **Game Center** | 玩家分數、單題排行、成就完成率 | Game Center API / Game Center App |

這組合覆蓋 v1 大半的問題（裝機 / 留存 / 效能 / crash / 玩家行為比較）。**不**涵蓋的事項：「點了哪個按鈕」、「在某畫面停留多久」這類微觀行為流 — 確認 v1 不需要回答這類問題。

### `TrackingSink` 處理

`Telemetry` target 內仍**保留** `TrackingSink` protocol，預設提供 **NoOp 實作**：

```swift
public struct NoOpTrackingSink: TelemetrySink {
    public init() {}
    public func receive(_ event: TelemetryEvent) { /* intentionally empty */ }
}
```

理由：呼叫端用 `telemetry.observe(event)` 不會因為「v1 沒有外部 tracking」而需要拿掉。將來若引入 TelemetryDeck / 自家 CloudKit 事件管線時，**只換 sink 實作**，呼叫端零修改。

### `MetricKitSink`

`Telemetry` target 內附 `MetricKitSink`：
- 訂閱 `MXMetricManager.shared.add(self)`
- 在 `didReceive(_ payloads:)` 把 `MXMetricPayload` 轉成 log（透過 `os.Logger`），並以 `TelemetryEvent.metricKitReport(...)` 廣播給其他 sink
- 不上傳到外部 — 純本機落地。將來如要上傳，再加 sink

### 隱私 / Manifest

- **`PrivacyInfo.xcprivacy`** 列入 v1 必交付項目（App Store 上架硬性要求）。
- 因為不引第三方 SDK、不收 IDFA、不收 PII，PrivacyInfo 內容會非常精簡。
- 不需要 ATT prompt（無 IDFA 用途）。
- CloudKit 與 Game Center 的 user-facing 隱私聲明由 Apple 系統層處理；App 端只需在 PrivacyInfo 標出資料用途即可。



## §7 Secrets 與 public repo 規範

本節定下「v1 的 App repo 將從 day 1 就是 public GitHub repo」的工程含意：從 secret 分類、儲存、攔截、洩露處置，到 Privacy 與 telemetry 的公開承諾。所有後續實作都假設**整份 repo（含歷史）對任何人可見**。

### §7.1 Repo 公開承諾

- 從 v1 開始即為 public — 不存在「先 private 再 public」過渡期，所以**沒有「以後再清歷史」的後路**。
- 隱私底線：repo 歷史任一 commit 都不得包含 secret 值、PII、可識別玩家資料；違規一旦發生即視為**已洩露**並 rotate。
- 這份公開性本身是「Claude agent 協作紀錄案例」的賣點之一 — 任何讀者可以追全部決策與實作。

### §7.2 Secret 分類

**v1 不需 CloudKit server-to-server key**（無 Public DB 寫入路徑、無 server-side puzzle 投放管線）。下表僅列 v1 實際會出現的 secret；server-to-server key 列為 v2 backlog（見 `docs/v1/design.md §不在 v1 範圍 → 題目來源 / 投放`），若未來 `PuzzleOverride` 機制落地，再回補到本表並對齊 [[apple-public-repo-security]] skill 規範。

| Secret | 用途 | 儲存位置 |
|---|---|---|
| App Store Connect API Key（`.p8` + 10-char Key ID + Issuer ID）| TestFlight / 上架自動化 | Xcode Cloud env vars (Secret) |
| **APNs Auth Key**（`.p8` + 10-char Key ID + Team ID）| **若**啟用推播（v2 評估）：CloudKit subscription 觸發 silent push、其它系統通知 | Xcode Cloud env vars (Secret)；v1 暫不需要、列此處供未來引入時對齊命名 |
| Apple Developer 簽章證書 + private key（`.p12`）| Code signing | Xcode Cloud automatic signing 由 Apple 託管 |
| Provisioning profiles | Code signing | Xcode Cloud Apple-managed |
| Game Center / iCloud 玩家識別資料 | Runtime debug | OSLog `.private` interpolation；**永不**進 git |
| `.gitleaks.toml` baseline（如有）| 已知非 secret 的 false positive 白名單 | Repo 內可公開；不含實際 secret 值 |

### §7.3 不可進 git 的東西

任何 commit / branch / stash / git note 都不得包含：

- 上述 Secret 的實際內容（包含 base64-encoded 形式）
- iCloud / Game Center 玩家真實 alias、displayName、gamePlayerID（除 hash 處理後）
- Apple Developer Team ID、DUNS、地址（如在 entitlement / profile metadata 中出現）
- Xcode Cloud build logs 含 secret 回顯（檢視前先 redact）
- 開發者本機 `.config/sudoku/` 任何實檔
- 個人筆記 / 草稿（`NOTES.md.private` 之類）

**若 commit 中發現 secret**（無論本機或 CI 偵測到）：
1. **先 rotate、再 force push**（rotate 才是真正止血；force push 後 GitHub reflog / fork 可能仍可達 secret 達 90 天，且**任何 fork 永久保留**該歷史）
   - CloudKit Dashboard rotate server-to-server key
   - App Store Connect rotate API key
   - APNs key（若啟用）rotate
   - 簽章證書若洩露：Apple Developer Center revoke + 重發
2. 用 [`git filter-repo`](https://github.com/newren/git-filter-repo) 清歷史 + force push（`git filter-branch` 已過時、勿用）
3. 通知 GitHub support 清 fork / cache；但**承認 fork 不可保證清除**——這正是「先 rotate」的根據
4. 在 `meetings/` 開一份 incident log 紀錄事件 + lessons learned
5. 完成上述四步前**不**繼續其他開發

**被動防線**：GitHub Settings → Code security → **Secret scanning alerts**（public repo 免費；Apple-issued 部分 secret pattern 由 GitHub partner program 自動偵測並關閉憑證）一律啟用。

### §7.4 `.gitignore` 黑名單

repo 根目錄 `.gitignore` 必須包含（v1 起手版）：

```
# Secrets / credentials
*.pem
*.p8
*.p12
*.mobileprovision
*.cer
.env
.env.*
!.env.example
secrets/
.config/sudoku/*.pem

# Xcode / build
DerivedData/
build/
xcuserdata/
*.xcuserstate
.swiftpm/

# macOS
.DS_Store

# 個人筆記
*.private.md
NOTES.md.private
```

新增任何 secret 形式時，同步更新此檔。`.gitignore` 本身進 git（這是規格、不是 secret）。

### §7.5 Pre-commit hook + gitleaks

採 [`gitleaks`](https://github.com/gitleaks/gitleaks)（v8+）。本機開發者 commit 前自動掃描 staged diff。

**`.mise.toml`（增列）**：
```toml
[tools]
swift = "system"
"aqua:gitleaks/gitleaks" = "8"             # 或 "ubi:gitleaks/gitleaks" 視 mise plugin 驗證結果
"aqua:evilmartians/lefthook" = "1"         # 同上：lefthook 非 mise core plugin，需 aqua / ubi backend
swiftlint = "0.54"
xcbeautify = "1"
# ...
```

實際 plugin 來源（`aqua:` vs `ubi:` vs 其它）於 plan.md 第一步驗證 mise 對 lefthook 的支援後鎖定（§7.11 open item）。

**安裝 pre-commit**：採用 [`lefthook`](https://github.com/evilmartians/lefthook) 管理 Git hooks（YAML 設定、進 repo）。`lefthook.yml`：
```yaml
pre-commit:
  parallel: true
  commands:
    gitleaks:
      run: mise exec gitleaks -- git --pre-commit --staged --redact --verbose
      # 註：gitleaks v8.18+ 已 deprecate `protect` subcommand；改用 `git --pre-commit`。
      # 若鎖較舊版仍可 `mise exec gitleaks -- protect --staged --redact`，但建議追隨 v8 最新。
    swiftlint:
      glob: "*.{swift}"
      run: mise exec swiftlint -- lint --quiet {staged_files}
```

`mise install` 同時把 `lefthook` 也裝起來；首次 clone 後執行 `lefthook install` 即啟用 hooks。

Repo 內附 `.gitleaks.toml` 自訂規則：CloudKit Key ID 與 App Store Connect / APNs Key ID（兩者皆為 10-char alphanumeric 格式、同一條 regex 可同時覆蓋）等。基本規則沿用 gitleaks 內建 `default.toml`，**僅增不減**。

#### §7.5.1 ~~SwiftFormat `.swiftformat` — option (b) baseline~~ (2026-05-26 obsoleted)

**SwiftFormat 整套移除（2026-05-26 user 決定）**：swiftlint 規則覆蓋面已足夠，再跑 swiftformat 是 redundant + double-tool 維護成本。移除範圍：`.swiftformat` 檔案、`.mise.toml` 的 swiftformat pin、`lefthook.yml` 的 swiftformat hook、`.github/workflows/lint.yml` 的 swiftformat step。歷史紀錄見 `meetings/2026-05-26_swiftformat-option-b.impl-notes.md`（保留作 archeology 用）。

### §7.6 PR CI 第二道防線

本機 hook 可被 `git commit --no-verify` 繞過；Xcode Cloud PR CI 加一條 **post-clone** step（Xcode Cloud 提供三個 hook：`ci_post_clone.sh` / `ci_pre_xcodebuild.sh` / `ci_post_xcodebuild.sh`；secret scan 選最早的 `ci_post_clone.sh`，clone 完即執行、build 資源尚未消耗）：

```
# ci_scripts/ci_post_clone.sh
mise install
mise exec gitleaks -- git --pre-commit --staged   # 新 subcommand；或舊版 `gitleaks protect --staged`
RESULT=$?
if [ $RESULT -ne 0 ]; then
  echo "gitleaks detected potential secrets — failing build"
  exit 1
fi
# 補充：GitHub 端啟用 Settings → Code security → Secret scanning alerts（public repo 免費）作為第三道防線
```

PR CI 一旦偵測到 → fail；開發者必須清掉並 force-push branch；該 secret 視為已洩露走 §7.3 處置流程。

### §7.7 設定範本

repo 內附以下檔案，作為「鍵名 + 用途」的 documentation，**值留空**：

- `.env.example`：列所有 env var 鍵名（CloudKit Key ID、ASC Key ID 等），值為 `<your-key-id-here>` placeholder
- `.config/sudoku/example/README.md`：本機 PEM 存放結構說明
  - **不放實際 `.pem.example` 檔**：gitleaks 內建 `private-key` rule 偵測到 `-----BEGIN PRIVATE KEY-----` header 即觸發、不檢查內容，會 false-positive
  - 用 fenced code block 在 README 內展示 PEM **形狀**（標明「以下為說明、非實檔」），讀者理解後自行於 `~/.config/sudoku/` 放真實 PEM
  - **若**將來確實需要 `.pem.example` 實檔，於 `.gitleaks.toml` 顯式 allowlist 該檔路徑（比繞過 regex 更乾淨）
- `docs/v1/setup.md`：新開發者第一次 clone 後的步驟導覽（指向上述範本 + Xcode Cloud secret 設定步驟 + `lefthook install` 啟用 hooks）

### §7.8 Privacy / telemetry 的公開承諾

App 對使用者的承諾（與 `PrivacyInfo.xcprivacy` 一致、且本 repo source 為 single source of truth）：

- **不收集 PII**
- **不引入第三方 tracking SDK**
- **App 端不向「我方」伺服器上傳任何事件**（事實：我方沒有後端，CloudKit / Game Center 由 Apple 提供）
- CloudKit Private DB 資料**僅存於使用者自己的 iCloud**（Apple 政策保證）

**透過 Apple 平台的合法上行通道**（用戶可在系統設定關閉）：

- **MetricKit `MXMetricPayload`**：系統聚合到 App Store Connect Analytics 的 Power & Performance 面板；由 Apple 控管，使用者透過 *Settings → Privacy → Analytics & Improvements* 控制
- **Game Center 分數 / 成就**：玩家明示登入後，分數提交給 Apple 並對 leaderboard 其他玩家可見（依 GC 預設可見性規則）；使用者透過 *Settings → Game Center* 控制可見度
- **App Store Connect crash report / TestFlight beta crash**：使用者啟用 Share Analytics 時上傳
- **sysdiagnose**：使用者主動分享給 Apple Feedback Assistant 時上傳；OSLog `.private` interpolation 在此會被遮罩（§5）

這些聲明可由讀者直接驗證（grep `import` 找有無第三方 SDK / 看 `Telemetry` target 的 sink 清單 / 看 `PrivacyInfo.xcprivacy`）。

### §7.9 Code reviewer 責任

任何 PR review 須額外確認：

- 沒漏網的新 secret pattern（gitleaks 規則可能未覆蓋）
- 沒在 doc / comment / commit message / PR description 中提到 secret 值
- 沒在 screenshot / asset 中含可識別資訊（玩家 alias、Team ID、Sandbox player record）
- Privacy 聲明若有改動 → `PrivacyInfo.xcprivacy` + App Store metadata 同步更新
- 任何「為了 debug 暫時 log 出 PII」的 helper 在合併前移除

Review 工具走 `superpowers:requesting-code-review` / `receiving-code-review`（見 `methodology.md`）。

### §7.10 與既有規則對齊

| 規則來源 | 在本節落地 |
|---|---|
| §4 Xcode Cloud secret | §7.2 / §7.5 / §7.6 一致；PR CI 加 gitleaks step |
| §4 Xcode Cloud + `mise`（含 Backlog 內 `mise` 條目）| §7.5 `.mise.toml` 增列 gitleaks + lefthook |
| §3 swift-testing | 測試不依賴任何 secret；test fakes 完全本機 |
| `docs/v1/design.md §How.4` 本機 generator | 無 server-side secret 需求；CloudKit server-to-server key 不在 v1 範圍 |
| `docs/v1/design.md §How.6.5` iCloud 帳號 hash | §7.3 確認玩家識別資料 hash 處理 + OSLog `.private` |
| `apple-public-repo-security` skill | 本節結晶化後即為該 skill；任一專案需 public-from-day-1 直接 invoke |

（節內子段為 §7.1 ~ §7.11）

### §7.11 Open items（落地 plan.md 時驗證）

- [x] ~~**Xcode Cloud hook 命名與執行階段**~~ — **Resolved**（Code Review round 3，2026-05-15）：Apple 提供 `ci_post_clone.sh` / `ci_pre_xcodebuild.sh` / `ci_post_xcodebuild.sh` 三 hook；本管線 secret scan 選 `ci_post_clone.sh`（最早、最省 CI 資源）。
- [x] ~~**lefthook vs 其他 hook 管理器**~~ — **Resolved**（Phase 1.2, 2026-05-18）：mise `aqua:evilmartians/lefthook` plugin 可用，lefthook major-version `1` pin 進 `.mise.toml`；pre-commit 並行跑 `gitleaks` / `hygiene` / `swiftlint`。Evidence: `meetings/2026-05-18_phase-1-2-execution.md`.
- [x] ~~**`.gitleaks.toml` 自訂規則**~~ — **Resolved**（Phase 1.2, 2026-05-18）：落實 Apple 10-char Key ID regex（涵蓋 ASC API / APNs Auth / CloudKit），gitleaks pin 8.30.1 via aqua plugin。實際規則見 repo root `.gitleaks.toml`。

## §8 Agent skills 選用

Skill 選用矩陣與觸發時機屬於**協作流程**範疇，已寫入 `methodology.md §Agent skills 使用矩陣` 一節，請從那裡查閱。

本節僅記錄一條結構性決策：

- **Plan 體系採用 `superpowers:writing-plans` + `superpowers:executing-plans`**，**不**使用 `claude-mem:make-plan` / `do`，避免兩套 plan 體系並存。

## §9 第三方 SDK 例外條款（v2 起）

v1 維持「Apple-only stack」（見 §6 不引入第三方 tracking）。v2 開始有受控例外：

### §9.1 AdMob — AppMonetizationKit/AdsAdMob target 內隔離

- **SDK**：Google Mobile Ads SDK，via SPM `https://github.com/googleads/swift-package-manager-google-mobile-ads`
- **理由**：ad-serving 必須接 SDK，Apple 沒有提供能 deliver ads 的原生替代（`AdServices` 只做 attribution，不能 serve ads）。詳細決策過程見 `docs/v2/design.md §How.9`。
- **隔離契約**：
  - 第三方依賴只在 `AppMonetizationKit/Sources/AdsAdMob` 這個 sub-target 內，**不能跨 target border**
  - `MonetizationCore` / `IAPStoreKit2` / Sudoku 主 App 程式碼 **一律不直接 `import GoogleMobileAds`**
  - protocol 中性面（`AdProvider`、`AdBannerStatus` 等）不暴露 `GADBannerView` 等具體型別
- **Privacy 連帶**：`PrivacyInfo.xcprivacy` `NSPrivacyTracking` 從 `false` 改 `true`，加上 AdMob domains + advertising identifier 等宣告；App Store nutrition labels 同步更新

### §9.2 新增第三方 SDK 的程序

任何 v2+ 想引入的新第三方 SDK 必須：

1. 在本節新增子小節（§9.X），包含：
   - SDK 名稱 + SPM URL
   - 為什麼沒有 Apple-only 替代方案的論證
   - 隔離契約（哪個 target 可以 import、哪個不行）
   - Privacy 連帶（如果觸發 tracking / data collection）
2. 在 `docs/v<N>/design.md` 寫詳細決策過程
3. PR review 由 Leader 把關「隔離」是否真的有效

---

## §Backlog

_討論過程中浮現、但本輪暫不處理的工具/套件/語言特性/CI/agent skill 想法。每條一行；需要上下文時附 meeting log 日期。_

- **Android module portability 工程預留**（2026-05-15）：§2 模組切法保留「純 Swift module（如 `SudokuEngine` / `GameState` / `PuzzleStore`）不引入 Apple framework」的限制，使其將來可透過 Swift SDK for Android cross-compile 輸出給 Android Studio 使用。**這是工程預留，產品 backlog 條目見 [`docs/v1/design.md §不在 v1 範圍 §平台與輸入 → Android App via Swift SDK for Android`](v1/design.md)（canonical）**。
- 未來考慮導入 [`mikeger/XcodeSelectiveTesting`](https://github.com/mikeger/XcodeSelectiveTesting) 來在 CI 上依模組相依關係只跑被影響的 test target，降低執行時間。前提是 §2 的模組切法已收斂穩定（2026-05-15）。
- 開發者可透過 [`nektos/act`](https://github.com/nektos/act) 在本機重現 GitHub Actions workflow，縮短「推 PR → 等 CI 紅」的迴圈。注意：act 對 macOS runner 與 Xcode 工具鏈支援有限，可能僅適用於非 build 類 job（如 lint、metadata 驗證）；§4 CI 設計時再衡量哪些 job 適合（2026-05-15）。
- **GitHub Actions（v1 暫不採用）**：v1 CI 全押 Xcode Cloud，repo 仍 host 在 GitHub 但不引入 GH Actions workflow。將來如需要以下任一項，可重新評估啟用：
  - PR 元資料規範（conventional commits、PR title lint、auto-label / required reviewer）
  - SwiftLint / SwiftFormat 等 binary tool 在 PR 上跑（透過 `mise` 管理版本）
  - `docs/` 文件鏈結檢查、`meetings/` 索引自動更新
  - 接 `XcodeSelectiveTesting`（見 backlog 第 3 條）以模組相依關係挑 test target 跑
  - 用 `nektos/act` 本機重現非 build 類 job（見 backlog 第 5 條）
  - 起手點：上面任一痛感真實出現時，先寫單一 workflow 試水（2026-05-15）。
- ~~**swiftformat 加入 `lefthook.yml` pre-commit**（2026-05-23）~~ — **CANCELLED 2026-05-26**: swiftformat 整套移除（user 決定 swiftlint 規則覆蓋已足夠；double-tool 維護成本不划算）。`.swiftformat` 檔、`.mise.toml` pin、`lefthook.yml` hook、`lint.yml` step 全 removed。
- **抽 Telemetry / GameCenterClient / Persistence target 到獨立 Swift Package**（2026-05-23）：目前三者住在 `Packages/SudokuKit/Sources/`，跟 SudokuUI / AppComposition / SudokuEngine / PuzzleStore 同 package。Telemetry 是純值類型 + 協議（無 UI 依賴）、GameCenterClient 包 GameKit（iOS only）、Persistence 包 CloudKit（跨平台）— 三者都是 capability-isolated leaf module，按 `AppMonetizationKit` 的成功經驗（外掛 third-party SDK 隔離）可以各自獨立成 package：(a) build-time clarity（誰 import 誰一目了然），(b) 平台 conditional dep 更乾淨（GameCenter iOS-only 可獨立 `.condition(.when(platforms: [.iOS]))`），(c) 將來給其他 app 重用。代價：每個 package 一份 Package.swift + tests 結構 + tuist generate 更慢一點。觸發點：第二個 app 想 reuse 任一 target / 或 SudokuKit 編譯時間明顯變慢。
- **XCC PR-CI 設為 required check + branch protection on `main`**（2026-05-23）：目前 Leader subagent 開 PR 後立刻 squash-merge，沒等 Xcode Cloud PR workflow 跑完。應改成：(a) PR open 觸發 XCC PR-CI（已有，見 §4 workflow 配置）；(b) GitHub branch protection rule on `main` 加 required status check = XCC `Sudoku | Default | Archive - iOS` 與 `Archive - macOS`；(c) Leader 流程改成 push → poll `gh pr checks <#>` → 全 green 才 merge。觸發點：(i) 第二人 collab 加入，或 (ii) 連續 3 次 XCC red 沒被本地 swift test 抓到。實作含：GH branch protection 設定（user-owned，ASC 帳號 needed）、Leader skill 更新「auto-merge」段加 wait-for-checks 步驟。
- **採用 [`mono0926/LicensePlist`](https://github.com/mono0926/LicensePlist) 自動產生 acknowledgments 頁**（2026-05-23）：隨 v2 引入 AdMob + UMP 第三方 SDK，App Store 需要列出 license。LicensePlist 從 Package.resolved 掃描所有 SPM deps 自動產 Settings.bundle Acknowledgments 頁（iOS 標準位置）或 SwiftUI 直顯。透過 `mise` 或 brew 加入工具鏈，CI step 跑 `license-plist --output-path App/Resources/Acknowledgements` 並 commit 結果。觸發點：v2 ship 前的 Settings UI polish；或當第三方 SDK 數量 > 3 個。代價：tooling overhead 低（單 binary）+ 需要決定 Settings.bundle vs SwiftUI 內嵌路徑。
- **GitHub Action agents 在 PR 上做 spec / design / code review + discussion thread**（2026-05-24）：今天的 v2 多輪 audit 都是 Leader 在 session 內 dispatch 一次性 subagent 跑，留下 meeting log；如果改成 GitHub Actions workflow，每次 PR open 自動觸發 3 個 review agent（spec / design / code），結果以 PR review comment 形式 inline 附在 diff 上；reviewers + Leader 在 PR thread 直接 discuss。優點：(a) audit 結果跟 PR 永久綁定（不會散在 meetings/），(b) async 不卡 session，(c) 多 reviewer 並行不會 race 同 working tree，(d) 將來 collab 加入後直接共用 review 機制。代價：需要 agent action runner（claude-code-action 或自建）+ GitHub PAT for auto-review-comment；MCP-style integration 需要 setup。觸發點：同 `XCC PR-CI 設為 required check` 條目（一起做更划算）。
- **補齊 repo skills/context 缺口**（2026-05-24 reflection；落地 2026-05-26）：parallel dispatch race + worktree-wipe-lost-commits + ASC ops handoff confusion 等 session 事故累積後，全部 5 條落地：(a) ✅ [`subagent-conflict-detection`](../.claude/skills/subagent-conflict-detection/SKILL.md) — 派發前 grep 目標 file set 跟 in-flight subagent 比對；(b) ✅ [`pr-diff-verification`](../.claude/skills/pr-diff-verification/SKILL.md) — push/PR 前 `git show --stat HEAD` 比對 commit message vs 實際 diff（PR #126 incident + 多次 worktree-wipe 教訓）；(c) ✅ [`asc-ops-handoff`](../.claude/skills/asc-ops-handoff/SKILL.md) — TestFlight / ASC API / Apple Developer 流程 step-by-step + user-owned vs Leader-orderable 分類；(d) ✅ [`monetization-sdk-integration`](../.claude/skills/monetization-sdk-integration/SKILL.md) — foundations §9 break-glass hands-on guide + isolation contract checklist；(e) ✅ memory 已分子目錄（`user/` `feedback/` `project/` `reference/`）— non-flat 結構自 2026-05-25 already in place。所有 skills 落在 `.claude/skills/` repo-level (per `[[feedback-project-derived-skills-location]]`).
- **擴大 ViewModel interaction tests（無新 dep）**（2026-05-26）：目前 snapshot tests 蓋「畫面長相 × 狀態」、ViewModel unit tests 蓋「state 計算」，但「button tap → navigate / mutate / call service」這段沒系統性覆蓋。利用既有 `RouteFactory` protocol（#71 落地）+ swift-testing protocol-injected fakes 模式，每個 View 應對應 `<View>InteractionTests`：`FakeRouteFactory.recordedRoutes` 比對 / `FakeService.callCount` 比對。不需新 dep。觸發點：(i) 任一畫面切換出現回歸；(ii) 任一新 View 沒帶 interaction test；(iii) 累積 3 個 navigation-related bug。實作含：`FakeRouteFactory` ~15 LOC + 每 ViewModel ~30-60 LOC tests。
- **評估 [`Kolos65/Mockable`](https://github.com/Kolos65/Mockable) 取代手寫 fakes（trigger-based）**（2026-05-26）：Swift macro 框架，`@Mockable` annotation 自動產 protocol mock + given/verify DSL，省手寫 boilerplate。對應 `swift-testing-baseline` skill 預設的 protocol-injected fakes，主要差異是「人工 fake class」→「macro 產生」。第三方 dep，須走 §9 break-glass。**評估 trigger**：(a) 手寫 fakes 累積 > 5 大型 protocol（含多 method、多 stub script 需求）、(b) 重複 fake boilerplate review feedback > 3 次、(c) 想統一 fake mode（preview / test / canary）。落地時須驗 Swift 6 strict concurrency 相容、`@Sendable` macro 展開正確、跟 swift-testing `@Suite` 不打架。**進階用途**（除了取代手寫 fake）：(i) SwiftUI `#Preview` 注入 mock 服務省 production stub 維護；(ii) capture mode 紀錄真實 API 呼叫做 record/replay 整合測試；(iii) runtime mode switch 讓 canary build 跟 sandbox build 共用 mock 層；(iv) `@MockableMacro` + service protocol 統一團隊多人 fake 命名 / 風格。
