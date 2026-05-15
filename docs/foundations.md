# Foundations — 工程底層與工具

狀態：**DRAFT** — 逐項討論中。
最後更新：2026-05-15

本文件記錄 Sudoku 專案的工程平台選擇：語言版本、模組化、測試、CI、Logger、Tracking、Agent skills。這些決策在產品規格（`design.md`）之前定下，是 `design.md §How` 與 `plan.md` 的依附基礎。

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
4. **Apple 框架 import 範圍受限**：`CloudKit` 只在 `PuzzleStore` + `Persistence` 直接 import；`GameKit` 只在 `GameCenterClient`。`SudokuUI` 與 `GameState` 透過 protocol 注入使用，不直接 import — 便於 UI/邏輯層的單元測試與 SwiftUI preview。
5. **測試 target 一對一**：每個 production target 對應一個 `<Module>Tests` target。

**目標模組形狀**（將來實作 repo `Sudoku/` 中）：

```
Sudoku/
├── App/                                # 薄殼
│   ├── SudokuApp.swift                 # @main + DI composition root
│   └── (Assets, Info.plist, entitlements)
└── Packages/
    └── SudokuKit/
        ├── Package.swift               # platforms: [.iOS(.v26), .macOS(.v26)]
        └── Sources/
            ├── SudokuEngine/           # 純 Swift 核心：board / rules / validator
            ├── GameState/              # 進行中局面：moves, undo/redo, notes
            ├── PuzzleStore/            # CloudKit public DB 題庫存取
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

### Workflow 配置

| Workflow | 觸發 | 動作 |
|---|---|---|
| **PR CI** | PR open / push（**啟用「Merge with base branch before building」**）| Build + Test（單元 / 整合 fakes / snapshot）|
| **Main CI** | merge 到 `main` | Build + Archive + **上傳 internal TestFlight**；**不重跑 test**（已由 PR CI 在 pre-merged 狀態驗證）|
| **Release** | git tag `v*` | Build + 上傳 App Store Connect（手動送審）|
| **Puzzle Delivery** | 每月 1 號 **UTC** 排程 + 手動可觸發 | 跑 `ci_scripts/upload_puzzles.sh`，預發佈**下個月 30 天份** Daily 題（每天 3 題）至 CloudKit Public DB；CI 故障緩衝至少一個月 |

### 環境鎖定

- **Xcode 26.5**，與本機 `.mise.toml` 鎖同版。
- 升 Xcode 時 → 開一張集中更新所有 snapshot 基準圖的 PR。
- Test 環境關閉 iCloud / Game Center 登入；所有 test 走 protocol fakes（§3）。
- `ci_scripts/` 內任何工具優先透過 `mise` 啟用，避免 Xcode Cloud 預裝版本飄移。

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

| Secret | 用途 | 儲存位置 |
|---|---|---|
| `CLOUDKIT_KEY_ID` + `CLOUDKIT_PRIVATE_KEY_PEM`（per environment）| Server-to-server CloudKit API（題目投放）| **Xcode Cloud Environment Variables → Secret**；本機 dev 環境 PEM 存 `~/.config/sudoku/`（chmod 600）或 macOS Keychain |
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
- `docs/setup.md`：新開發者第一次 clone 後的步驟導覽（指向上述範本 + Xcode Cloud secret 設定步驟 + `lefthook install` 啟用 hooks）

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
| `design.md §How.4.5` 開發 PEM | §7.2 表格 + §7.4 .gitignore 雙保險 |
| `design.md §How.6.5` iCloud 帳號 hash | §7.3 確認玩家識別資料 hash 處理 + OSLog `.private` |
| `apple-public-repo-security` skill | 本節結晶化後即為該 skill；任一專案需 public-from-day-1 直接 invoke |

（節內子段為 §7.1 ~ §7.11）

### §7.11 Open items（落地 plan.md 時驗證）

- [x] ~~**Xcode Cloud hook 命名與執行階段**~~ — **Resolved**（Code Review round 3，2026-05-15）：Apple 提供 `ci_post_clone.sh` / `ci_pre_xcodebuild.sh` / `ci_post_xcodebuild.sh` 三 hook；本管線 secret scan 選 `ci_post_clone.sh`（最早、最省 CI 資源）。
- [ ] **lefthook vs 其他 hook 管理器**（如 `pre-commit` Python、`husky` Node）— v1 採 lefthook（Go binary，與 mise 整合最簡）；plan.md 第一步驗證 mise plugin 是否提供 lefthook。
- [ ] **`.gitleaks.toml` 自訂規則** — CloudKit / ASC key ID 確切格式需查官方文件後落實到 regex。

## §8 Agent skills 選用

Skill 選用矩陣與觸發時機屬於**協作流程**範疇，已寫入 `methodology.md §Agent skills 使用矩陣` 一節，請從那裡查閱。

本節僅記錄一條結構性決策：

- **Plan 體系採用 `superpowers:writing-plans` + `superpowers:executing-plans`**，**不**使用 `claude-mem:make-plan` / `do`，避免兩套 plan 體系並存。



---

## §Backlog

_討論過程中浮現、但本輪暫不處理的工具/套件/語言特性/CI/agent skill 想法。每條一行；需要上下文時附 meeting log 日期。_

- 主要開發在 Swift Package 內以 targets 分模組，App target 僅作為 entry point 呼叫 Package 的 products 使用（2026-05-15；§2 會深入討論）。
- Swift 官方宣布支援 Android 後，純 Swift module（典型如 `SudokuEngine`）有機會以 Swift Package 形式輸出給 Android Studio 使用；§2 模組切法應預留這個可能（2026-05-15）。
- 未來考慮導入 [`mikeger/XcodeSelectiveTesting`](https://github.com/mikeger/XcodeSelectiveTesting) 來在 CI 上依模組相依關係只跑被影響的 test target，降低執行時間。前提是 §2 的模組切法已收斂穩定（2026-05-15）。
- 如需使用 GitHub 上開源 Swift package 提供的 **binary CLI / build tool**（如 swiftlint、swiftformat、xcbeautify 等），統一用 [`mise`](https://mise.jdx.dev/) 管理版本與安裝；開發機與 CI 共用同一份 `.mise.toml` 確保版本一致（2026-05-15）。
- 開發者可透過 [`nektos/act`](https://github.com/nektos/act) 在本機重現 GitHub Actions workflow，縮短「推 PR → 等 CI 紅」的迴圈。注意：act 對 macOS runner 與 Xcode 工具鏈支援有限，可能僅適用於非 build 類 job（如 lint、metadata 驗證）；§4 CI 設計時再衡量哪些 job 適合（2026-05-15）。
- **Telemetry 統一介面提案**：Logger 與 Tracking 走同一個 facade protocol，呼叫端只說「發生了什麼事件」，facade 同時派發給 Logger（人類除錯訊息）與 Tracking（產品分析事件）。例：`telemetry.observe(.viewWillAppear(...))` → 內部 fan-out 到 `logger.info(...)` 與 `tracker.send(event)`。待 §5/§6 展開（2026-05-15）。
- **GitHub Actions（v1 暫不採用）**：v1 CI 全押 Xcode Cloud，repo 仍 host 在 GitHub 但不引入 GH Actions workflow。將來如需要以下任一項，可重新評估啟用：
  - PR 元資料規範（conventional commits、PR title lint、auto-label / required reviewer）
  - SwiftLint / SwiftFormat 等 binary tool 在 PR 上跑（透過 `mise` 管理版本）
  - `docs/` 文件鏈結檢查、`meetings/` 索引自動更新
  - 接 `XcodeSelectiveTesting`（見 backlog 第 3 條）以模組相依關係挑 test target 跑
  - 用 `nektos/act` 本機重現非 build 類 job（見 backlog 第 5 條）
  - 起手點：上面任一痛感真實出現時，先寫單一 workflow 試水（2026-05-15）。
