# Sudoku v2 — Implementation Plan

狀態：**IN PROGRESS** — v2.0–v2.4 code 全部 shipped；v2.5 進入 user-owned ops（TestFlight + ASC review）。
最後更新：2026-05-25
Total phases: **6**（v2.0–v2.5）；total steps: **24 原訂 + 5 後續 audit / polish**。

This plan operationalizes [`docs/v2/design.md`](design.md) + [`docs/foundations.md §9`](../foundations.md#9-第三方-sdk-例外條款v2-起).

---

## §Status snapshot

| Phase | Scope | Status | PRs |
|---|---|---|---|
| v2.0 | Package + protocols + AdGate + Testing fakes | ✅ shipped | bootstrap series |
| v2.1 | IAP impl (StoreKit 2) | ✅ shipped | #59 |
| v2.2 | AdMob impl (banner + ATT + UMP) | ✅ shipped | #60, #73 |
| v2.3 | Sudoku 整合 (Persistence / Composition / RouteFactory / Views / boot) | ✅ shipped | #71, #83, #84 |
| v2.4 | Privacy + ASC ops | ✅ code shipped；ASC manual ops 轉 v2.5-readiness | #62, #107 |
| v2.4★ | Audit polish (anchor registry / wall-clock throttle / Fake fan-out) | ✅ shipped | #97, #108, #109 |
| v2.4★ | macOS conditional build (Noop fallback, ObjC v11 API) | ✅ shipped | #101, #102, #103, #106 |
| v2.5 | TestFlight + ASC review | 🟡 in flight — user-owned | see [`v2.5-readiness.md`](v2.5-readiness.md) |

Test count（AppMonetizationKit `@Test` macros）: **75** across 4 test targets / 13 files。

---

## How to use

- **TDD-ordered**。每個 step 紅燈測試先、再實作通過。
- **One step = one PR**（除非 review 要求拆）。
- **Phase 內 sequential、phase 間有限度可平行**：v2.1 IAP 與 v2.2 AdMob 走獨立 protocol；v2.3 wiring 需兩條都完成。
- **Spec drift sweep**：每 phase 收尾 grep TODO，每條 match 必須 Resolved / §Backlog / Intentionally left。
- **Step 標記**：`[x] (#PR)` = shipped；`[~]` = partial / 跨 PR；`[ ]` = todo / user-owned。

---

## §Phase v2.0 — AppMonetizationKit foundations  ✅

**Goal**：package skeleton + MonetizationCore protocols + Testing fakes + AdGate frequency logic（純 protocol layer + 邏輯，不接真實 SDK）。

### v2.0.1 — Package skeleton + 4 sub-targets  `[x]`

- `Packages/AppMonetizationKit/Package.swift`：swift-tools 6.2、iOS 26 / macOS 26、4 library products（MonetizationCore / AdsAdMob / IAPStoreKit2 / MonetizationTesting）+ 4 test targets
- 每 sub-target 1 個 placeholder 讓 `swift build` 通過
- Tuist Project.swift 暫不動

### v2.0.2 — MonetizationCore: protocols + value types  `[x]`

- `MonetizationCoreTests/ProtocolShapeTests.swift` — protocol witness 驗 `AdProvider` / `IAPClient`
- 落地：
  - `AdProvider.swift`（+ `AdBannerStatus` enum + `AdBannerHandle` struct）
  - `IAPClient.swift`（+ `IAPProduct` / `IAPPurchaseResult` / `IAPPurchaseEvent`）
  - `AdPresentationAnchor.swift`（iOS `UIWindow` / macOS `NSWindow` wrapper）
  - **`NoopAdProvider.swift`** — default no-op，後續 macOS build 直接拿用（PR #101 引入此用途）

### v2.0.3 — MonetizationTesting fakes  `[x]`

- 落地 `FakeAdProvider` / `FakeIAPClient` actors，可 script 行為；Sendable + cross-actor 注入

### v2.0.4 — AdGate + AdGateStateStore protocol  `[x]`

- `AdGate.swift`：`@MainActor` actor + `AdGateState` Codable struct + `AdGateStateStore` protocol
- 注入 `clock: any Clock<Duration>` 與 `calendar: Calendar` 讓測試確定性
- 覆蓋 grace / dismissed-today / next-day / purchased / UTC boundary

### v2.0.5 — MonetizationTesting 提供 `FakeAdGateStateStore`  `[x]`

- in-memory state + `script(...)` API

### v2.0.6 — Anchor registry/resolver split (PR #108)  `[x]`

- 把 `AdPresentationAnchor` 單一 struct 拆成 `AdPresentationAnchorRegistry` + `AdPresentationAnchor+Resolve`，讓多 window scene 與 fan-out 變乾淨
- 此 step 為 plan 起跑後新增（origin: §97/108 audit），補登於此

**Phase v2.0 收尾**：sweep done；test suite green。

---

## §Phase v2.1 — IAP impl (LiveStoreKit2IAPClient)  ✅

**Goal**：StoreKit 2 live impl + Restore Purchases + transaction observer。

### v2.1.1 — StoreKitBridge isolation + skeleton + availableProducts  `[x] (#59)`

- 紅燈先：`IAPStoreKit2Tests/AvailableProductsTests.swift`，用 `FakeStoreKitBridge` 驗 mapping
- 落地：
  - `StoreKitBridge.swift` protocol + `LiveStoreKitBridge.swift`（唯一 `import StoreKit` 面）— 與 AdMobBridge 對稱結構
  - `IAPProductIDs.swift` 集中 product ID 常數
  - `IAPProductMapper.swift` 純函數 mapping
  - `LiveStoreKit2IAPClient.swift` actor，內部 stored set，public 拿 `IAPProduct`

### v2.1.2 — Purchase flow + Restore + transaction observer  `[~] (#59 + #85)`

- 紅燈 cover：成功 / userCancelled / pending / failed / restore / `purchaseUpdates()` AsyncStream
- `purchaseUpdates()` 對 `Transaction.updates` 的真實訂閱在 PR #85 才接齊（plan 原訂一次完成，實際分兩次）
- StoreKit Configuration file 注入 dev sandbox 在 v2.4★/PR #107

**Phase v2.1 收尾**：sweep done。

---

## §Phase v2.2 — AdMob impl (LiveAdMobAdProvider)  ✅

**Goal**：Google Mobile Ads banner load + present + dismiss；ATT + UMP 整合。foundations §9.1 隔離契約。

### v2.2.1 — SPM dep + LiveAdMobAdProvider skeleton  `[x] (#60)`

- `Package.swift` `AdsAdMob` target 加 `swift-package-manager-google-mobile-ads` 與 `swift-package-manager-google-user-messaging-platform`，**兩者皆 `.condition(.when(platforms: [.iOS]))`**（Google 沒提供 macOS slice — 詳 §v2.4★ macOS fallback）
- 落地：
  - `AdMobBridge.swift` protocol（protocol-only，不 import SDK）
  - `LiveAdMobBridge.swift` 具體 wrapper — 唯一 import site = `LiveAdMobBridge.swift`
  - `LiveAdMobAdProvider.swift` actor，注入 bridge
- 隔離 audit：`rg '^(internal |private |public |@_implementationOnly |@preconcurrency )*import GoogleMobileAds' Packages/` 必須 = 1 檔（在 `AdsAdMob/LiveAdMobBridge.swift`）

### v2.2.2 — Banner load / refresh / handle status  `[x] (#60)`

- `FakeAdMobBridge` 驅動的 unit test
- `bannerStatus` 由內部 `@MainActor` state machine 維護；UI 整合在 v2.3.4

### v2.2.3 — ATTPresenter + UMPConsentPresenter  `[x] (#60)`

- `ATTPresenter.swift` 包 `ATTrackingManager.requestTrackingAuthorization`
- `UMPConsentPresenter.swift` 包 UMP SDK（**v3 API**, see §Decisions）
- 觸發順序與整合移到 v2.3.7 / `MonetizationBootCoordinator`

**Phase v2.2 收尾**：sweep done。

---

## §Phase v2.3 — Sudoku v2 整合  ✅

**Goal**：把 AppMonetizationKit 接進 Sudoku App，banner / IAP 入口 / Settings restore / boot order；同時 promote RouteFactory refactor（因 RootView.init deps 過載）。

### v2.3.1 — Persistence: MonetizationStateStore (CloudKit Private)  `[x] (#71)`

- `Persistence/MonetizationStateStore.swift` protocol
- `Persistence/Live/LiveMonetizationStateStore.swift` actor，落新 record type `MonetizationState`（`userZone`）
- Schema：`firstLaunchAt: Date`、`lastShownDate: Date?`、`dismissedDate: Date?`、`hasPurchasedRemoveAds: Bool`

### v2.3.2 — AppComposition + Tuist wiring  `[x] (#71)`

- `AppComposition` 加 stored `adProvider / iapClient / adGate` 等 dep
- `Live.swift` 構造 `LiveAdMobAdProvider` + `LiveStoreKit2IAPClient` + `AdGate(store: LiveMonetizationStateStore(...))`
- `Preview.swift` 用 `MonetizationTesting` fakes
- `Project.swift` 加 `.package(product: "MonetizationCore" | "AdsAdMob" | "IAPStoreKit2")`
- `Packages/SudokuKit/Package.swift` 加對 `AppMonetizationKit` 的 dep

### v2.3.3 — RouteFactory refactor  `[x] (#71)`

- `SudokuUI/Navigation/RouteFactory.swift`：`RouteFactory` protocol + `LiveRouteFactory`
- `RootView.init` 實際簽名：`(viewModel, routeFactory, adProvider?, adGate?, monetizationController?, toastController?)` — 6 params（4 optional 供 preview / test 注入），非原 plan 預估的 5 params 全 required
- destination 改 `routeFactory.view(for: route)`

### v2.3.4 — HomeView 加 BannerSlotView  `[x] (#83)`

- `SudokuUI/Components/BannerSlotView.swift`，注入 `adProvider` + `adGate`
- HomeView 4 mode cards 下方加 slot；close button → `adGate.recordBannerDismissed(now:)` 後 self-hide

### v2.3.5 — BoardView 加 BannerSlotView（pause 隱藏）  `[x] (#83)`

- Grid 與 digit pad 之間加 slot；`if !viewModel.isPaused` 才顯示
- GeometryReader 吸收 banner 高度

### v2.3.6 — Settings: Remove Ads CTA + Restore Purchases  `[x] (#84)`

- `Settings/SettingsView.swift` 加 IAP section（Remove Ads / Restore）
- HomeView 5th mode card「Remove Ads」（unpurchased 才出現）

### v2.3.6.1 — MonetizationStateController + ToastController  `[x] (#84, #85)`

- 新增 `SudokuUI/Components/MonetizationStateController.swift`（@Observable）集中 purchase / restore / revoke 狀態
- 新增 `Components/ToastView.swift` + ToastController 作為跨 phase 共用 surface
- **此 step plan 原本未列**，補登：把 IAP 結果 / banner 反饋的 UI 分散邏輯收斂到單一 controller

### v2.3.7 — App boot order: UMP → ATT → AdMob init  `[x] (#84, #106)`

- 實作改用 `AdsAdMob/MonetizationBootCoordinator.swift` + `MonetizationBootBridges`（由 `AppComposition.live()` 在 `bootMonetization()` 內呼叫）
- 非 iOS 平台直接 early-return（PR #106）
- 失敗 → log + 繼續，不阻擋 App 進入

**Phase v2.3 收尾**：sweep done。

---

## §Phase v2.4 — Privacy 改動 + ASC ops  ✅ (code) / 🟡 (ASC manual)

**Goal**：PrivacyInfo / privacy-policy / App Store nutrition labels / ASC IAP product。多數 ASC 後台操作已轉 [`v2.5-readiness.md`](v2.5-readiness.md)。

### v2.4.1 — PrivacyInfo.xcprivacy 更新  `[x] (#62)`

- `NSPrivacyTracking = true`
- `NSPrivacyTrackingDomains` 列出 AdMob domains
- `NSPrivacyCollectedDataTypes` 加 `OtherUsageData` purpose `Third-party advertising`
- `NSPrivacyAccessedAPITypes` 加 `CategoryUserDefaults`

### v2.4.2 — privacy-policy.md 加廣告與 IAP 章節  `[x] (#62)`

- `docs/privacy-policy.md` §「廣告與 IAP」新增；雙語 source（en + zh-Hant），其他 5 locale 走 ai-translated-localization flow

### v2.4.3 — App Store nutrition labels  `[ ]` **(user-owned — see v2.5-readiness.md)**

### v2.4.4 — ASC 手動建立 IAP product  `[ ]` **(user-owned — see v2.5-readiness.md)**

### v2.4.5 — StoreKit Configuration scheme wiring + ASC App Privacy handoff  `[x] (#107)`

- `Project.swift` 加 `RunActionOptions.storeKitConfigurationPath → App/Resources/Sudoku.storekit`，Scheme 經 `tuist generate` persist，免手動 Xcode 編輯
- 同時把 ASC App Privacy 問卷對齊資料整理進 `v2.5-readiness.md`（無 ASC REST API，純 manual）

**Phase v2.4 收尾**：code spec 對齊；ASC ops 由 user 在 v2.5 完成。

---

## §Phase v2.4★ — Audit polish & cross-platform build  ✅

Plan 原訂未列、實際 ship 的後續工作整理於此，供 trace。

### v2.4★.1 — Conditional iOS-only deps + NoopAdProvider for macOS  `[x] (#101)`

- AdMob/UMP dep 加 platform condition；macOS build 走 `NoopAdProvider`

### v2.4★.2 — iOS xcodebuild compile via v11 ObjC AdMob/UMP API  `[x] (#102, #103)`

- 為相容當下 Xcode toolchain，AdMob/UMP wrapper 走 v11 ObjC API surface

### v2.4★.3 — `bootMonetization()` non-iOS early-return  `[x] (#106)`

### v2.4★.4 — Audit M+N polish  `[x] (#97)`

- wall-clock throttle、Fake fan-out、anchor registry 等 audit item 收斂

### v2.4★.5 — AdMob v13 + UMP v3 upgrade  `[x] (#109)`

- SDK 版本升級 + API 對齊

---

## §Phase v2.5 — TestFlight + ship  🟡 (user-owned)

**Goal**：真機驗證 + ship to App Store。

詳細 checklist 全部在 [`v2.5-readiness.md`](v2.5-readiness.md)；此處只列 phase 概要，避免雙處維護。

- **v2.5.1** Sandbox IAP on real device — 購買 / 跨機 restore / CloudKit sync
- **v2.5.2** Real-device AdMob test ads — 1/day max + dismissed-skip（7-day grace 於 2026-06-02 廢除，gracePeriodDays = 0）；isolation audit `rg '^(internal |private |public |@_implementationOnly |@preconcurrency )*import GoogleMobileAds' Packages/` = 1 檔
- **v2.5.3** Submit to ASC review — Privacy questionnaire 對齊 PrivacyInfo / demo Apple ID / submit

CI prerequisite：`ci_post_clone.sh` 從 Xcode Cloud `$CI_TEAM_ID` 寫 `Tuist/Signing.xcconfig`，user 不需手動配 env var。

---

## §Decisions（v2 開工後新增）

承襲 [`docs/v2/design.md §Decisions`](design.md#decisions自-2026-05-20-brainstorm)，下列為 plan 執行期間新增決定：

- **D-v2-01** AdMob SDK v13 / UMP v3（升級於 2026-05，PR #109）
- **D-v2-02** AdMob/UMP wrapper 採 v11 ObjC API surface（toolchain 相容權衡，PR #102/#103）
- **D-v2-03** macOS build 不引入 AdMob／改用 `NoopAdProvider`（Google 無 macOS slice，PR #101）
- **D-v2-04** Anchor 模型由單一 struct 改為 registry + resolver（多 scene 支援，PR #108）
- **D-v2-05** `purchaseUpdates()` 真實訂閱拆到 PR #85 與 toast surface 一起 ship（與 plan 原訂 v2.1.2 一次完成不同）
- **D-v2-06** RootView.init 保留 4 個 optional dep slot 供 preview/test 注入，非「全 required 5 deps」（plan 原預估與 SwiftUI preview 體驗衝突）

---

## §Backlog（v2 不做）

詳見 [`docs/v2/design.md §Backlog`](design.md#backlogv2-不做未來-candidate)。

---

## §下一動作

1. User 依 [`v2.5-readiness.md`](v2.5-readiness.md) pre-flight checklist 跑完 ASC IAP / AdMob console / sandbox tester 設定
2. User 完成 v2.5.1（sandbox IAP）與 v2.5.2（real-device AdMob test ads）
3. User 跑 v2.5.3 submit；submit 前由 subagent 跑最後一次 `rg '^(internal |private |public |@_implementationOnly |@preconcurrency )*import GoogleMobileAds' Packages/` isolation audit
