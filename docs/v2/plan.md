# Sudoku v2 — Implementation Plan

狀態：**DRAFT** — 等 v2.0 dispatch。
最後更新：2026-05-21
Total phases: **6**（v2.0–v2.5）；total steps: **24**。

This plan operationalizes [`docs/v2/design.md`](design.md) + [`docs/foundations.md §9`](../foundations.md#9-第三方-sdk-例外條款v2-起).

---

## How to use

- **TDD-ordered**. 每個 step 列紅燈測試先、再實作通過。
- **One step = one PR**。除非 review 反饋要拆。
- **Phase 內 sequential、phase 間有限度可平行**（v2.1 IAP 與 v2.2 AdMob 兩條完全獨立，protocol 都拿 v2.0 的；之後 v2.3 wiring 需等兩條都完成）。
- **Spec drift 自動 sweep**：每個 phase 收尾前依 methodology.md §7 跑 TODO sweep，每條 match 必須 Resolved / §Backlog / Intentionally left。

---

## §Phase v2.0 — AppMonetizationKit foundations

**Goal**：package skeleton + MonetizationCore protocols + Testing fakes + AdGate frequency logic（不接任何真實 SDK，純 protocol layer + 邏輯）。

### v2.0.1 — Package skeleton + 4 sub-targets

- NEW `Packages/AppMonetizationKit/Package.swift`：swift-tools 6.2, iOS 26 / macOS 26, 4 library products (MonetizationCore / AdsAdMob / IAPStoreKit2 / MonetizationTesting), 4 test targets
- 每個 sub-target 內各放 1 個 placeholder type 讓 `swift build` 通過
- 為什麼一次建 4 個：保留結構清晰；之後每個 phase 填內容比逐個新建乾淨

**Acceptance**：`cd Packages/AppMonetizationKit && swift build` 0 warnings。Tuist Project.swift 暫不更新（v2.3.2 wiring 時才加 dep）。

### v2.0.2 — MonetizationCore: protocols + value types

- 紅燈先：`MonetizationCoreTests/ProtocolShapeTests.swift` 用 protocol witness pattern 驗證 `AdProvider` / `IAPClient` 形狀（無實作，只驗 protocol 簽名）
- 落地：
  - `MonetizationCore/AdProvider.swift`：`AdProvider` protocol + `AdBannerStatus` enum + `AdBannerHandle` struct
  - `MonetizationCore/IAPClient.swift`：`IAPClient` protocol + `IAPProduct` / `IAPPurchaseResult` / `IAPPurchaseEvent`
  - `MonetizationCore/AdPresentationAnchor.swift`：cross-platform anchor（iOS `UIWindow` / macOS `NSWindow` wrapper）
- NoOp default 實作（Sendable + Equatable conformance 都要齊）

**Acceptance**：`swift test --filter MonetizationCoreTests` 全綠；0 warnings；strict concurrency clean。

### v2.0.3 — MonetizationTesting fakes

- 紅燈先：`MonetizationTestingTests/FakeShapesTests.swift` 驗 `FakeAdProvider.script(...)` API
- 落地：
  - `MonetizationTesting/FakeAdProvider.swift`：actor，可 script `bannerStatus` / `initialize`/`refreshBanner` 行為
  - `MonetizationTesting/FakeIAPClient.swift`：actor，可 script products / purchase result / restore result
- 用於後續 phase 跨模組單元測試 + Sudoku 整合 preview/test

**Acceptance**：`swift test --filter MonetizationTestingTests` 全綠；Fake 都是 Sendable + 可 cross-actor 注入。

### v2.0.4 — AdGate + AdGateStateStore protocol

- 紅燈先：`MonetizationCoreTests/AdGateLogicTests.swift`：
  - Day 0：`shouldShowBanner == false`（grace）
  - Day 7：`shouldShowBanner == true`
  - Day 7 + dismissed today：`shouldShowBanner == false`
  - Day 8（新一天）：`shouldShowBanner == true`
  - hasPurchasedRemoveAds == true：永久 false
  - Edge：UTC vs local calendar boundary（用注入 `Calendar(identifier: .gregorian, timeZone: utc)` 統一）
- 落地：
  - `MonetizationCore/AdGate.swift`：`@MainActor actor AdGate` + `AdGateState` Codable struct + `AdGateStateStore` protocol
  - 注入 `clock: any Clock<Duration>` 與 `calendar: Calendar` 讓測試確定性
- 約 10 個 unit test，覆蓋所有狀態轉移

**Acceptance**：10/10 AdGate tests 全綠；clock 注入讓所有 case 可在 1ms wall-clock 內驗完。

### v2.0.5 — 整合：MonetizationTesting 提供 `FakeAdGateStateStore`

- 紅燈先：MonetizationTestingTests 加 `FakeAdGateStateStore` round-trip 測試
- 落地：actor `FakeAdGateStateStore`；in-memory state + `script(...)` API

**Acceptance**：Phase v2.0 close — 整個 package build + 35-40 tests 全綠。

**Phase v2.0 收尾 TODO sweep**：grep `Packages/AppMonetizationKit/Sources/` 0 hits。

---

## §Phase v2.1 — IAP impl (LiveStoreKit2IAPClient)

**Goal**：StoreKit 2 live impl + Restore Purchases + transaction observer。

### v2.1.1 — LiveStoreKit2IAPClient skeleton + availableProducts

- 紅燈先：`IAPStoreKit2Tests/AvailableProductsTests.swift` — mock `StoreKit.Product.products(for:)` 並驗 `IAPClient.availableProducts()` 正確 mapping 到 `IAPProduct`
- 落地：
  - `IAPStoreKit2/LiveStoreKit2IAPClient.swift`：actor，內部 stored `Set<Product>`，公開 mapping 到 `IAPProduct`
  - `IAPStoreKit2/IAPProductMapper.swift`：`StoreKit.Product` → `MonetizationCore.IAPProduct` 純函數，可獨立測

**Acceptance**：4-6 unit tests 全綠；不需要連 ASC sandbox。

### v2.1.2 — Purchase flow + Restore Purchases + transaction observer

- 紅燈先：tests 覆蓋
  - `purchase(.removeAds)` 成功路徑（mock returns success）
  - userCancelled、pending、failed
  - `restorePurchases` 拿到 previously-purchased 的 product
  - `purchaseUpdates()` AsyncStream 收到外部 transaction（家長同意 / 退款 revoke）
- 落地：
  - `LiveStoreKit2IAPClient.purchase(_:)` 呼叫 `Product.purchase()`
  - `restorePurchases()` 呼叫 `AppStore.sync()` + iterate `Transaction.currentEntitlements`
  - 啟動時 spawn `Task.detached` 觀察 `Transaction.updates`，pipe 到 `purchaseUpdates` AsyncStream
  - **StoreKit 2 testing tip**：用 `.storekit` configuration file（Xcode 內建 StoreKit Configuration）注入測試 product；單元測試層用 mock `Product`
- ATT 不需要在這 phase 觸發（StoreKit 不需 ATT，只有 ad tracking 才需）

**Acceptance**：12-15 unit tests 全綠；strict concurrency clean。

**Phase v2.1 收尾 TODO sweep**。

---

## §Phase v2.2 — AdMob impl (LiveAdMobAdProvider)

**Goal**：接 Google Mobile Ads SDK，banner load + present + dismiss；ATT + UMP 整合。

⚠️ 本 phase 是 v2 第一次引入第三方 SPM dep，根據 foundations §9.1 隔離契約嚴格控制。

### v2.2.1 — 加 SPM dep + LiveAdMobAdProvider skeleton

- `Packages/AppMonetizationKit/Package.swift`：`AdsAdMob` target 加 dep `.package(url: "https://github.com/googleads/swift-package-manager-google-mobile-ads", from: "<latest-stable>")`
- 紅燈先：`AdsAdMobTests/AdProviderInitTests.swift` — 用 `FakeAdMobBridge` protocol 替代真實 SDK 呼叫；驗 `initialize()` 順序與 idempotency
- 落地：
  - `AdsAdMob/LiveAdMobAdProvider.swift`：actor，注入 `AdMobBridge` protocol（內部 default 是真實 `GADMobileAds.sharedInstance().start(completionHandler:)` wrapper）
  - `AdsAdMob/AdMobBridge.swift`：protocol，包住所有 `GoogleMobileAds` 接觸面 — 唯一允許 `import GoogleMobileAds` 的檔
  - 隔離 audit：`grep -r "import GoogleMobileAds" Packages/AppMonetizationKit/Sources/` 必須只有 `AdsAdMob/AdMobBridge.swift` + 內部具體 wrapper 一個檔

**Acceptance**：build 0 warnings；隔離 audit 通過；4-6 unit tests 全綠。

### v2.2.2 — Banner load / refresh / handle status

- 紅燈先：driven by `FakeAdMobBridge`，驗
  - load 成功 → `bannerStatus == .loaded`
  - load 失敗 → `.failed(reason)`
  - refresh 後 status 重設
- 落地：
  - `LiveAdMobAdProvider.refreshBanner()` 呼叫 bridge 載入新 banner
  - `bannerStatus` 由內部 `@MainActor` state machine 維護
  - **不渲染 UI**：本 phase 只負責後端 load；UI 整合在 v2.3.4

**Acceptance**：8-10 unit tests 全綠。

### v2.2.3 — ATTPresenter + UMP consent

- 紅燈先：`AdsAdMobTests/ATTPresenterTests.swift` — mock `AppTrackingTransparency.ATTrackingManager` 驗 request flow
- 落地：
  - `AdsAdMob/ATTPresenter.swift`：`requestIfNeeded()` 包住 `ATTrackingManager.requestTrackingAuthorization`
  - `AdsAdMob/UMPConsentPresenter.swift`：包 UMP SDK（內建在 GoogleMobileAds），呼叫 `UMPConsentInformation.sharedInstance.requestConsentInfoUpdate`
  - **觸發順序**（在 Sudoku App boot 處整合，v2.3.7）：UMP → ATT → AdMob init

**Acceptance**：5-7 unit tests 全綠；隔離 audit 仍只有 1 個檔 `import GoogleMobileAds`（ATTPresenter 走 `import AppTrackingTransparency` 是 Apple 框架 OK）。

**Phase v2.2 收尾 TODO sweep**。

---

## §Phase v2.3 — Sudoku v2 整合

**Goal**：把 AppMonetizationKit 接進 Sudoku App，banner 顯示 / IAP 入口 / Settings restore / boot order。同時 promote Wave 3 audit 的 RouteFactory refactor（因為 RootView.init 已要長到 8+ deps）。

### v2.3.1 — Persistence: MonetizationStateStore (CloudKit Private)

- 紅燈先：`PersistenceTests/MonetizationStateStoreTests.swift` — round-trip save/load 用 FakeCKGateway
- 落地：
  - `Packages/SudokuKit/Sources/Persistence/MonetizationStateStore.swift`：protocol
  - `Persistence/Live/LiveMonetizationStateStore.swift`：actor，落 CloudKit Private 的新 record type `MonetizationState`（在 `com.wei18.sudoku.userZone`）
  - record schema：`firstLaunchAt: Date`、`lastShownDate: Date?`、`dismissedDate: Date?`、`hasPurchasedRemoveAds: Bool`
  - CloudKit Dashboard 不用手動建 record type（first write auto-creates）

**Acceptance**：4-6 unit tests 全綠；persistence schema doc 更新 `design.md §How.2.X`。

### v2.3.2 — AppComposition +3 deps（暫態，準備 RouteFactory）

- 紅燈先：`AppCompositionTests/CompositionTests.swift` 加新 deps 驗證
- 落地：
  - `AppComposition` 加 `adProvider / iapClient / adGate` 三個 stored property
  - `Live.swift` 構造 `LiveAdMobAdProvider` + `LiveStoreKit2IAPClient` + `AdGate(store: LiveMonetizationStateStore(...))`
  - `Preview.swift` 用 `MonetizationTesting` fakes
  - `Project.swift` Tuist manifest 加 `.package(product: "MonetizationCore")` + `"AdsAdMob"` + `"IAPStoreKit2"` to App target
  - `Packages/SudokuKit/Package.swift` 加上 `AppComposition` target 對 `AppMonetizationKit` 的依賴

**Acceptance**：build clean；tests 全綠。短期 RootView.init 會長到 8 個 deps，下一 step 修。

### v2.3.3 — RouteFactory refactor（promoted from Wave 3 audit）

- 紅燈先：`SudokuUITests/RouteFactoryTests.swift` 驗每個 AppRoute → matching View+VM 構造
- 落地：
  - `SudokuUI/Navigation/RouteFactory.swift`：protocol `RouteFactory { func view(for: AppRoute) -> AnyView }` 與 `LiveRouteFactory` 落地實作（內部把 5 個 protocol deps 包進來，提供 5 個 destination View 構造）
  - `AppComposition` 從 stored 5+ deps 改為 stored 1 `routeFactory: any RouteFactory`
  - `RootView.init` 簽名收縮：`(viewModel: RootViewModel, routeFactory: any RouteFactory, adProvider: any AdProvider, iapClient: any IAPClient, adGate: AdGate)` — 從 8 收 到 5
  - destination 改 `destination: { route in routeFactory.view(for: route) }`

**Acceptance**：RootView.init 簽名 5 deps（不再爆增）；測試 all green；audit Wave 3 RouteFactory item 完成關閉。

### v2.3.4 — HomeView 加 BannerSlotView

- 紅燈先：`SudokuUITests/HomeViewBannerTests.swift` 驗 `BannerSlotView` 在 `adGate.shouldShowBanner == false` 時 `EmptyView()`，true 時顯示 `AdMobBannerView` wrapper
- 落地：
  - `SudokuUI/Components/BannerSlotView.swift`：SwiftUI view，注入 `adProvider` + `adGate`；右上 12pt 灰色 ✕ close button
  - `HomeView.swift`：4 mode cards 下方加 `BannerSlotView()`
  - close button 觸發 `adGate.recordBannerDismissed(now:)` 然後 self-hide

**Acceptance**：4-6 unit tests 全綠；快照測試重做 HomeView baseline（with banner / without banner 兩個變體）。

### v2.3.5 — BoardView 加 BannerSlotView（懸停期間隱藏）

- 紅燈先：`SudokuUITests/BoardViewBannerTests.swift` 驗 `pause / running` 兩態下 banner visibility
- 落地：
  - `BoardView.swift`：grid 與 digit pad 之間加 `BannerSlotView`，加條件 `if !viewModel.isPaused` 才顯示
  - GeometryReader 重新計算 grid size 吸收 banner 高度
- 快照：board with banner（new variant）；pause state with no banner（existing variant）

**Acceptance**：4-5 unit tests 全綠；snapshot baseline +2 PNGs。

### v2.3.6 — Settings: Remove Ads CTA + Restore Purchases

- 紅燈先：`SudokuUITests/SettingsIAPRowTests.swift` 驗 unpurchased / purchased 兩態 UI
- 落地：
  - `Settings/SettingsView.swift`：加新 Section
    - Row 1: `Remove Ads — $2.99` button（unpurchased 才顯示；tap → `iapClient.purchase(.removeAds)`）
    - Row 2: `Restore Purchases` button（tap → `iapClient.restorePurchases()`）
  - 兩個 row 都帶 spinner state + result toast
- HomeView 第 5 個 mode card 「Remove Ads」（unpurchased 才出現）— 與 Settings row 同行為，更顯眼

**Acceptance**：6-8 unit tests 全綠；snapshot baseline 重做 SettingsView。

### v2.3.7 — App boot order: UMP → ATT → AdMob init

- 紅燈先：`AppCompositionTests/BootOrderTests.swift` 用 fake bridges 驗 3 步驟順序
- 落地：
  - `AppComposition.live()` 內 `bootMonetization()` 函式：
    1. `await UMPConsentPresenter.requestIfNeeded()`
    2. `await ATTPresenter.requestIfNeeded()`
    3. `await adProvider.initialize()`
  - 從 `SudokuApp.swift` 啟動點呼叫；在 HomeView appear 之前完成
  - 失敗 → log + 繼續（不阻擋 App 進入）

**Acceptance**：3-5 unit tests 全綠；real device 試 cold launch UMP prompt（v2.5）。

**Phase v2.3 收尾 TODO sweep**。

---

## §Phase v2.4 — Privacy 改動 + ASC ops（user-owned）

**Goal**：PrivacyInfo / privacy-policy.md / App Store nutrition labels / ASC IAP product 註冊。多數步驟是 spec + 後台操作，code 部分小。

### v2.4.1 — PrivacyInfo.xcprivacy 更新

- 紅燈先：`PrivacyManifestTests.swift` 驗 plist 內容
- 落地：
  - `NSPrivacyTracking`: `false` → `true`
  - `NSPrivacyTrackingDomains`: 加 AdMob domains（per [Google docs](https://developers.google.com/admob/ios/privacy/manifest)）
  - `NSPrivacyCollectedDataTypes`: 加 `NSPrivacyCollectedDataTypeOtherUsageData` + purpose `Third-party advertising`
  - `NSPrivacyAccessedAPITypes`: 加 `NSPrivacyAccessedAPICategoryUserDefaults`（AdMob 內部用）

**Acceptance**：plist 解析 test 通過；real device build 時不會被 Apple privacy 連帶 reject（v2.5 驗）。

### v2.4.2 — privacy-policy.md 加廣告與 IAP 章節

- 落地：
  - `docs/privacy-policy.md` 新增 §「廣告與 IAP」section
    - AdMob 收集 advertising identifier、可在 iOS Settings 關閉
    - IAP 由 Apple 處理，不經過 Sudoku 後端
  - 雙語（en + zh-Hant 為 source），其他 5 locale 用 ai-translated-localization skill flow 補

**Acceptance**：spec 改動入 git；可從 GitHub Pages 等地對外公開。

### v2.4.3 — App Store nutrition labels 更新（user-owned）

- ASC App Privacy 頁更新：
  - "Data Used to Track You": Yes（advertising / measurement）
  - "Data Linked to You": No
  - "Data Not Linked to You": Identifiers（advertising ID）, usage data

**Acceptance**：ASC 後台改完，與 PrivacyInfo.xcprivacy 對齊。

### v2.4.4 — ASC 手動建立 IAP product（user-owned）

- ASC → My Apps → Sudoku → In-App Purchases → Create
- Type: Non-Consumable
- Reference Name: `Remove Ads`
- Product ID: `com.wei18.sudoku.iap.remove_ads`
- Price: $2.99 USD（Tier 3）
- Localized name 7 locales（從 ai-translated-localization skill 流程）

**Acceptance**：ASC 後台 product 為 `Ready to Submit`；StoreKit Configuration file 也同步本機 dev sandbox。

**Phase v2.4 收尾**：spec + ops 對齊。

---

## §Phase v2.5 — TestFlight + ship

**Goal**：真機驗證 + ship to App Store。多數 user-owned ops，subagent 只能在前期幫 build。

### v2.5.1 — Real device sandbox IAP test（user-owned）

- TestFlight 安裝
- Sandbox Apple ID 試購 `Remove Ads`
- 驗證購買後 banner 消失、Restore 也能在新裝置拿回購買狀態
- 驗證 CloudKit `MonetizationState` 跨機 sync

**Acceptance**：3 條場景通過。

### v2.5.2 — Real device AdMob test ad（user-owned）

- 在 AdMob console 用 [test ad unit IDs](https://developers.google.com/admob/ios/test-ads)（**NOT production unit IDs**）
- 跑 7 天 grace 邏輯：first install → banner 沒出現
- 跑 dismissed-skip：手動跳過 grace（注入 fake clock 或修改 CloudKit record），點 ✕ 確認當天不再出現
- 跑 1/day max：跨日後 banner 重新出現

**Acceptance**：3 條 banner 行為驗證通過；隔離 audit `grep import GoogleMobileAds` 仍只有 1 檔。

### v2.5.3 — Submit to ASC review（user-owned）

- TestFlight build 升 production
- App Privacy questionnaire 確認與 PrivacyInfo 對齊
- Review notes 內附 demo Apple ID（含 sandbox 環境說明）
- Submit

**Acceptance**：Apple Review 通過、上架 production。

---

## §Decisions（自 design.md v2 §Decisions 同步）

詳見 [`docs/v2/design.md §Decisions`](design.md#decisions自-2026-05-20-brainstorm)。

---

## §Backlog（v2 不做）

詳見 [`docs/v2/design.md §Backlog`](design.md#backlogv2-不做未來-candidate)。

---

## 起跑

派 Senior Developer subagent 從 **v2.0.1 Package skeleton** 起手，PROPOSAL → IMPL → review → merge → 下一 step。phase 間平行性：v2.1 IAP 與 v2.2 AdMob 互不阻擋，v2.3 Sudoku 整合需 v2.1 + v2.2 都完成。
