# Sudoku v2 — Monetization Design

狀態：**DRAFT** — brainstorm 2026-05-20 收線，待 plan.md v2 起跑。
最後更新：2026-05-21

本文件是 Sudoku v2 第一個 deliverable：`AppMonetizationKit` Swift package（廣告 + IAP），跨未來 Wei18 App reuse。

---

## §What — 產品決策

### 6 個鎖定的核心決策（2026-05-20 brainstorm）

| # | 決策 | 理由 |
|---|---|---|
| 1 | **真接 SDK route**（不是純抽象）| 今年內 Sudoku v2 要能實際賣錢 / 顯廣告 |
| 2 | **AdMob (Google)** | 主流、生態穩、fill rate 最高、文件最齊 |
| 3 | **IAP = Remove Ads only**（one-time non-consumable，$2.99 USD） | 與 AdMob 配套；不引入 subscription / pro features 複雜度 |
| 4 | **Package = `AppMonetizationKit`** | App-prefix 表示可裝任何 App target；非個人品牌 |
| 5 | **Apple-only impl，protocol 中性** | iOS / macOS first；Android via Swift SDK 是 design.md §不在 v1 範圍 backlog，未來再說 |
| 6 | **廣告頻率：7-day grace + 1/day max + dismissed-that-day skip** | calm brand 不打擾、初體驗保護期、用戶 close 後當天不再煩 |
| 7 | **Frequency state = CloudKit Private `MonetizationState` record** | 跨 iCloud 帳號 sync；換新 iPhone 不重置 7-day grace |
| 8 | **廣告插入點 = Home / Board view 內 banner** | 非 interstitial；持續存在但不全螢幕打斷；與 calm brand 相容 |

### v2 不做的

- ❌ Subscription / Pro features（沒 pro 內容可賣）
- ❌ Tip Jar consumable
- ❌ Premium puzzle pack
- ❌ 動態頻率（基於 CloudKit cost 反推）— defer v2.1+
- ❌ Android impl
- ❌ Interstitial / 全螢幕廣告
- ❌ Rewarded ad（為 hints / 跳關等獎勵看廣告）

---

## §How — 架構

### §How.1 Package 結構

```
Packages/AppMonetizationKit/
├── Package.swift                  swift-tools 6.2, iOS 26 / macOS 26
└── Sources/
    ├── MonetizationCore/          # protocols + value types + NoOp impls
    ├── AdsAdMob/                  # LiveAdMobAdProvider; depends on GoogleMobileAds via SPM
    ├── IAPStoreKit2/              # LiveStoreKit2IAPClient; pure Apple
    └── MonetizationTesting/       # Fake providers for unit tests
└── Tests/
    ├── MonetizationCoreTests/
    ├── AdsAdMobTests/             # protocol tests; live SDK behavior 不測（網路依賴）
    ├── IAPStoreKit2Tests/         # mock StoreKit.Product
    └── MonetizationTestingTests/  # fake fixture sanity
```

**Dep direction**：
- `MonetizationCore` ← zero external dep
- `AdsAdMob` → MonetizationCore + GoogleMobileAds (SPM URL: `https://github.com/googleads/swift-package-manager-google-mobile-ads`)
- `IAPStoreKit2` → MonetizationCore + StoreKit (Apple framework)
- `MonetizationTesting` → MonetizationCore
- Sudoku 主 App → MonetizationCore + AdsAdMob + IAPStoreKit2（透過 `AppMonetizationKit` umbrella product）

### §How.2 Protocol 中性面

```swift
// MonetizationCore/AdProvider.swift
public protocol AdProvider: Sendable {
    /// Start SDK + load first banner. Idempotent.
    func initialize() async throws
    /// Current banner ready-to-display state.
    var bannerStatus: AdBannerStatus { get async }
    /// Force a fresh load. Used after dismiss-then-show-next.
    func refreshBanner() async throws
}

public enum AdBannerStatus: Sendable, Equatable {
    case notInitialized
    case loading
    case loaded(AdBannerHandle)
    case failed(reason: String)
    case suppressed  // user purchased Remove Ads OR within 7-day grace OR dismissed today
}

public struct AdBannerHandle: Sendable, Equatable {
    public let id: UUID  // opaque
}

// MonetizationCore/IAPClient.swift
public protocol IAPClient: Sendable {
    func availableProducts() async throws -> [IAPProduct]
    func purchase(_ productId: String) async throws -> IAPPurchaseResult
    func restorePurchases() async throws -> [IAPProduct]
    func purchaseUpdates() -> AsyncStream<IAPPurchaseEvent>
}

public struct IAPProduct: Sendable, Equatable {
    public let id: String
    public let displayName: String
    public let displayPrice: String  // 已含 locale formatting
    public let isPurchased: Bool
}

public enum IAPPurchaseResult: Sendable {
    case success(IAPProduct)
    case userCancelled
    case pending
    case failed(reason: String)
}

public enum IAPPurchaseEvent: Sendable {
    case purchased(productId: String)
    case revoked(productId: String)  // refund / family share lost
}
```

**不暴露**：`GoogleMobileAds.GADBannerView`、`StoreKit.Product`、`StoreKit.Transaction`。所有具體型別在 Live impl 內部用。

### §How.3 廣告頻率閘門

```swift
// MonetizationCore/AdGate.swift
@MainActor
public actor AdGate {
    private let store: any AdGateStateStore
    private let clock: any Clock<Duration>  // 注入測試
    
    public func shouldShowBanner(now: Date = .now) async -> Bool {
        // Suppressed if:
        // 1. User purchased Remove Ads (check IAPClient state)
        // 2. firstLaunchAt + 7 days > now (grace period)
        // 3. dismissedDate == today (calendar-local)
        // 4. lastShownDate == today AND not yet dismissed
        //    → 銜接「1/day max」：當天已 shown 一次後，dismissed 前 keep showing
        //    （banner persistent; 我們不重複「shown次數」，only count days）
    }
    
    public func recordBannerShown(now: Date = .now) async  // updates lastShownDate
    public func recordBannerDismissed(now: Date = .now) async  // updates dismissedDate
    public func recordPurchase() async  // flips purchased = true; permanently suppresses
}

public protocol AdGateStateStore: Sendable {
    func loadState() async throws -> AdGateState
    func saveState(_ state: AdGateState) async throws
}

public struct AdGateState: Sendable, Codable, Equatable {
    public var firstLaunchAt: Date  // set once on first ever launch
    public var lastShownDate: Date?  // calendar-day at start
    public var dismissedDate: Date?  // calendar-day at start
    public var hasPurchasedRemoveAds: Bool
}
```

**State 儲存**：實作 `AdGateStateStore` 由 Sudoku App 端決定。**v2 採用 CloudKit Private**：新增一個 `MonetizationState` record type 在 `com.wei18.sudoku.userZone`，含上面 4 個欄位。`SudokuKit/Persistence` 模組擴充 `MonetizationStateStore` 實作。

理由：跨 iCloud 帳號 sync — 玩家換新 iPhone 不需要再經歷 7 天 grace；買過 Remove Ads 也跨機。

### §How.4 ATT + UMP（GDPR）整合

```swift
// AdsAdMob/ATTPresenter.swift
@MainActor
public enum ATTPresenter {
    /// Trigger Apple's ATT prompt before first ad load.
    public static func requestIfNeeded() async -> ATTOutcome
}

public enum ATTOutcome: Sendable {
    case authorized
    case denied
    case restricted
    case notDetermined  // shouldn't happen post-requestIfNeeded
}
```

- ATT prompt 必須在 App 啟動完成、且使用者已經至少看過 Home view（不要 cold-launch prompt）
- 拒絕 ATT → 廣告仍會顯示但 non-personalized（AdMob 自動處理 fallback）
- UMP（Google User Messaging Platform）— SDK 自帶；EEA / UK / 加州 用戶第一次啟動 App 會看到 GDPR / CCPA consent dialog；passed 之後才會 trigger ATT

整合順序：App 啟動 → UMP consent → ATT prompt → AdMob initialize → 進入 v1 流程。

### §How.5 IAP 落地 — Remove Ads

#### ASC 註冊
- Product ID: `com.wei18.sudoku.iap.remove_ads`
- Type: Non-Consumable
- Reference name: `Remove Ads`
- Price tier: $2.99 USD（Apple Tier 3，其他 currency 自動換算）
- Localized display name 7 locales 由 ai-translated-localization skill 補
- **ASCRegister 未來擴充**：目前 ASCRegister 只處理 GameCenter；IAP register 是另一條 API。v2 初版手動建 IAP product，後續 ASCRegister 可加 `--iap` mode（backlog）

#### Restore Purchases
- Settings view 加新 row「Restore Purchases」
- 呼叫 `IAPClient.restorePurchases()` → 對應的 `IAPProduct.isPurchased = true` 同步到 `AdGateState.hasPurchasedRemoveAds = true`
- Spinner + 結果 toast（"Restored" / "Nothing to restore" / "Failed: <reason>"）

#### Purchase Flow
- HomeView 加「Remove Ads」CTA card（只在 `!hasPurchasedRemoveAds` 顯示）
- 點 → 呼叫 `IAPClient.purchase(.removeAds)` → 顯示 Apple 原生付費 sheet
- `.success` → 立刻 `AdGate.recordPurchase()` → banner 全域消失
- `.userCancelled` → no-op
- `.pending` → "Pending approval"（家長控制下的孩童帳號）
- `.failed` → error toast 帶 reason

### §How.6 廣告 UI 整合

#### Home view
- 在 4 個 mode cards **下方** 加一個 `BannerSlotView`，固定 320×50 pt（AdMob 標準）
- `BannerSlotView` 內部呼叫 `AdGate.shouldShowBanner()`：
  - `false` → 隱藏（用 `EmptyView()`；不佔空間）
  - `true` → 顯示 AdMob banner；右上角 12pt 灰色「✕」close button
- Close button tap → `AdGate.recordBannerDismissed()` → banner 隱藏，當天不再出現

#### Board view  
- 在 9×9 grid 與 digit pad 之間 加 BannerSlotView（同 Home 規格）
- 注意：iPhone compact 高度緊張；banner 高度（50pt）+ padding（8pt × 2）= 66pt vertical cost
- 解法：board 的 `aspectRatio(1, contentMode: .fit)` 自然壓縮；timer + digit pad 已是 fixed-size；squeeze 在 9×9 grid 與 controls 之間的 spacing 上吸收
- **不 in pause mode 顯示**：玩家 pause 後是 dim screen，不適合廣告

#### 廣告 reflow / loading
- 第一次 `loadBanner` 中：顯示空 container（保留 50pt 空間，防 layout jump）
- 載入失敗：保留空 container，下次 view appear 時 retry
- 載入成功：fade in

### §How.7 Sudoku 整合 — AppComposition 改動

```swift
// AppComposition.swift（v2 擴充）
@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let puzzleProvider: any PuzzleProviderProtocol
    public let persistence: any PersistenceProtocol
    public let gameCenter: any GameCenterClient
    public let telemetry: Telemetry
    
    // v2 additions
    public let adProvider: any AdProvider          // NEW
    public let iapClient: any IAPClient            // NEW
    public let adGate: AdGate                      // NEW
}

// AppComposition.live() 內部
public static func live() async throws -> AppComposition {
    // ... existing v1 wiring ...
    let monetizationStateStore = LiveMonetizationStateStore(gateway: persistenceGateway)
    let adGate = AdGate(store: monetizationStateStore, clock: .continuous)
    let adProvider = LiveAdMobAdProvider(gate: adGate)
    let iapClient = LiveStoreKit2IAPClient()
    
    return AppComposition(
        rootViewModel: ...,
        puzzleProvider: ...,
        persistence: ...,
        gameCenter: ...,
        telemetry: ...,
        adProvider: adProvider,
        iapClient: iapClient,
        adGate: adGate
    )
}
```

`AppComposition.preview()` / `.tests()` 注入 fakes from `MonetizationTesting`。

`RootView.init` 再多 3 個 deps（adProvider / iapClient / adGate）— PR #48 RouteFactory pattern 沒做，這次增加 3 個是壓垮的稻草，**v2 開頭應該 fold in RouteFactory refactor**（Wave 3 architecture backlog item 此時 promote）。

### §How.8 Privacy posture 更新

#### PrivacyInfo.xcprivacy
- `NSPrivacyTracking`: `true`（AdMob 載入後玩家可同意 tracking）
- `NSPrivacyTrackingDomains`: AdMob 的 domains（per Google docs）
- `NSPrivacyCollectedDataTypes`: 加 `NSPrivacyCollectedDataTypeOtherUsageData`（advertising data）+ purpose `Third-party advertising`
- `NSPrivacyAccessedAPITypes`: 加 `NSPrivacyAccessedAPICategoryUserDefaults`（AdMob 內部用）

#### App Store nutrition labels
- "Data Used to Track You" — Yes（advertising / measurement）
- "Data Linked to You" — No
- "Data Not Linked to You" — Identifiers（advertising ID），usage data

#### Privacy Policy (docs/privacy-policy.md)
- 新增 §「廣告與 IAP」section：說明 AdMob 收集 advertising identifier、可在 iOS Settings 關閉、IAP 由 Apple 處理不經過 Sudoku
- 雙語（en + zh-Hant 來源；其他 5 locale 翻譯 pass）

### §How.9 foundations.md §9 破例條款

`foundations.md §6` 目前說「v1 走 Apple 三件套，不引入第三方 tracking SDK」。v2 在 `foundations.md §9` 加 break-glass：

> **§3.1 第三方 SDK 例外（v2 起）**
> 
> AppMonetizationKit/AdsAdMob 是 v2 起的唯一第三方 SDK 例外。
> 
> - **理由**：ad-serving 必須接 SDK，無 Apple-only 替代方案（Apple `AdServices` 只做 attribution，不能 deliver ads）。
> - **隔離**：第三方依賴只在 `AppMonetizationKit/Sources/AdsAdMob` 這個 sub-target 內，不能跨 target border。`MonetizationCore` / `IAPStoreKit2` / Sudoku 主程式 一律不直接 `import GoogleMobileAds`。
> - **未來新增**：任何 v2+ 想引入的新第三方 SDK 必須在這裡列出，含「為什麼沒有 Apple-only 替代方案」的論證。

---

## §Decisions（自 2026-05-20 brainstorm）

| 決策 | 出處 |
|---|---|
| Sudoku v2 第一個 deliverable = AppMonetizationKit | brainstorm 鎖定 |
| 真接 SDK route（非純抽象） | brainstorm Q1 |
| AdMob over Unity Ads / Meta / 其他 | brainstorm Q2 |
| IAP = Remove Ads only（$2.99）| brainstorm Q3 |
| Package = AppMonetizationKit | brainstorm Q4 |
| Apple-only impl | brainstorm Q5 |
| 廣告頻率：7-day grace + 1/day + dismissed-skip | brainstorm Q6 |
| Frequency state = CloudKit Private MonetizationState | brainstorm Q7 |
| Banner（非 interstitial）| brainstorm Q8 |
| Sudoku v2 整合改動 += AppComposition 加 3 deps + Home/Board banner slot + Settings Restore + ATT/UMP 整合 + PrivacyInfo + Privacy Policy + App Store nutrition labels | 本文件 |
| foundations.md §3 加 break-glass for AdMob | 本文件 |
| RouteFactory pattern promote 自 Wave 3 audit backlog | 本文件（壓垮稻草）|

---

## §Backlog（v2 不做、未來 candidate）

- **動態廣告頻率**：v2.1+，基於 CloudKit cost / active users 反推
- **Interstitial / Rewarded ads**：v3+，需重新評估是否與 calm brand 相容
- **Subscription / Pro tier**：v3+，需要有 pro feature 可賣
- **Tip Jar**：考慮（calm brand-friendly），v2.1+
- **Premium puzzle pack**：與 PuzzleOverride backlog 接合，v2.1+
- **Android implementation**：與 design.md Android via Swift SDK backlog 接合
- **ASCRegister IAP mode**：自動化 IAP product 註冊到 ASC（目前手動）

---

## 下一步

1. PR 本文件
2. 更新 `docs/foundations.md §3` 加 break-glass 條款
3. 更新 `docs/design.md §不在 v1 範圍 §商業模式` 標記 「promoted to v2 design」+ 連結
4. 起 `docs/v2/plan.md` 拆解實作步驟（TDD-ordered）
5. 派 implementer subagent 走 plan.md v2 step by step
