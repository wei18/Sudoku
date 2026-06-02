# Sudoku — Privacy Policy

Last updated: 2026-05-21
Applies to: Sudoku for iPhone and Mac, version 1.0 and later.

> **v2 update (2026-05-21, revised 2026-06-02)**: starting with v2.0, Sudoku App displays Google AdMob banner ads on Home / Board view (shown from first launch, capped at one displayed ad per day with dismissed-that-day skip), and offers a one-time "Remove Ads" In-App Purchase. The short version and §Data we collect sections below describe the v1 baseline; the new behaviour is documented in §廣告與 IAP (v2+) at the bottom of this document. Until v2 ships, the v1 baseline applies.

This is the public privacy policy for the Sudoku App developed by Wei (`@wei18` on GitHub). It mirrors the declarations in [`Sudoku/Resources/PrivacyInfo.xcprivacy`](../Sudoku/Resources/PrivacyInfo.xcprivacy). If the two ever disagree, the manifest is the source of truth and this document will be updated to match.

## Short version

- We do not collect personal information.
- We do not use any third-party analytics, advertising, or tracking SDKs.
- We do not operate our own servers. Your saves and statistics live in your own iCloud Private Database, accessible only by you and not by us.
- Game Center scores and achievements are handled by Apple under Apple's own privacy terms.
- No advertising identifier (IDFA) is requested; no App Tracking Transparency prompt appears.

## Data we collect

**None linked to you. None not linked to you. None tracked.**

In Apple's App Store privacy taxonomy:

- **Data Linked to You**: None.
- **Data Not Linked to You**: None.
- **Data Used to Track You**: None.

This is reflected in the App Store privacy label and in `PrivacyInfo.xcprivacy`:

- v1: `NSPrivacyTracking` = `false`, all of `NSPrivacyTrackingDomains` / `NSPrivacyCollectedDataTypes` / `NSPrivacyAccessedAPITypes` empty.
- v2+: see §廣告與 IAP below — `NSPrivacyTracking` = `true`, with AdMob tracking domains and one usage-data entry declared.

## Where your gameplay data lives

- **CloudKit Private Database (your iCloud account)**: in-progress board states, completed puzzle records, per-difficulty statistics, and preferences. Apple stores this in the iCloud account you are signed into on the device. We have no access to it. You can delete it at any time via *Settings → [Your Name] → iCloud → Manage Account Storage → Sudoku*.
- **Game Center (Apple)**: when you complete a Daily puzzle, your time is submitted to Apple's Game Center as a leaderboard score, and matching achievements may unlock. This is mediated entirely by Apple under Apple's Game Center privacy practices. You can disable Game Center for the App in *Settings → Game Center*.
- **On-device only**: undo/redo history, current session timer state.

## Diagnostics handled by Apple

The App relies on platform-level diagnostic channels that Apple operates. We do not run our own. You can opt out of each via the iOS / macOS Settings app.

- **MetricKit / Power & Performance**: aggregated crash, hang, launch time, and energy data. Visible to us only via App Store Connect's *Power & Performance* dashboard, in anonymized form. Controlled by *Settings → Privacy & Security → Analytics & Improvements → Share With App Developers*.
- **TestFlight beta crash reports** (TestFlight builds only): standard Apple beta diagnostics.
- **sysdiagnose**: only uploaded when you explicitly share one via Feedback Assistant. Private string interpolation in our logs is redacted by Apple before sharing.

## Third-party services

None embedded. We do not integrate Firebase, Mixpanel, Adjust, AppsFlyer, Sentry, Crashlytics, TelemetryDeck, or any analogous SDK. You can verify this in the open-source repository at <https://github.com/wei18/Sudoku> by searching for `import` statements.

## Children

The App does not knowingly collect any data, from children or from anyone. Age-appropriate; rating 4+.

## 廣告與 IAP (v2+) / Advertising and IAP (v2+)

This section applies only to v2.0 and later. In v1 the App ships with no ads and no IAP; if you are reading this for a v1 build, ignore this section.

### 廣告 / Advertising

從 v2 起，Sudoku App 在 Home 與 Board view 顯示由 Google AdMob 提供的橫幅廣告。從第一次啟動起即顯示，每天最多顯示一次；玩家在當天關閉廣告後，當天不再出現。購買「Remove Ads」一次性內購後，廣告永久關閉。

Starting with v2, Sudoku App shows banner ads supplied by Google AdMob on the Home and Board views. Ads appear from first launch, capped at one displayed ad per day; once you dismiss the day's ad, no further ads appear that day. Purchasing the one-time "Remove Ads" IAP turns ads off permanently.

AdMob 在執行廣告投放時：

When serving ads, AdMob:

- 讀取裝置的 **Advertising Identifier (IDFA)**。玩家可在 iOS 設定 → 隱私權與安全性 → Apple 廣告 / 追蹤功能 關閉或重設。
  Reads the device's **Advertising Identifier (IDFA)**. You can disable or reset it via iOS Settings → Privacy & Security → Apple Advertising / Tracking.
- 對歐盟 / 英國 / 加州等司法管轄區的使用者，於首次啟動時先透過 Google 的 **User Messaging Platform (UMP)** 顯示 GDPR / CCPA consent 對話框；UMP 完成後才會出現 ATT prompt。
  For users in the EU / UK / California and similar jurisdictions, presents a GDPR / CCPA consent dialog on first launch via Google's **User Messaging Platform (UMP)** *before* the ATT prompt is shown.
- 在 UMP 之後（或不適用 UMP 的地區，於首次啟動時）透過 Apple 的 **App Tracking Transparency (ATT)** 取得追蹤許可。若玩家拒絕，廣告仍會顯示，但為非個人化（non-personalized）廣告。
  After UMP (or on first launch in regions where UMP does not apply), requests tracking permission via Apple's **App Tracking Transparency (ATT)** prompt. If you decline, ads are still shown but are non-personalized.

對應的 PrivacyInfo.xcprivacy 宣告（v2 起）：

Corresponding PrivacyInfo.xcprivacy declarations (v2+):

- `NSPrivacyTracking` = `true`
- `NSPrivacyTrackingDomains` 包含 AdMob 廣告投放網域（`googleadservices.com`, `googlesyndication.com`, `doubleclick.net`, `google-analytics.com`, `googletagmanager.com`, `googletagservices.com`, `2mdn.net`, `app-measurement.com`）。
  `NSPrivacyTrackingDomains` lists AdMob's ad-serving domains (as above).
- `NSPrivacyCollectedDataTypes` 新增一筆 `OtherUsageData`，標記為「Not Linked to You」、「Used to Track You」，目的為「Third-party Advertising」。
  `NSPrivacyCollectedDataTypes` adds one entry — `OtherUsageData`, Not Linked to You, Used to Track You, purpose Third-party Advertising.
- `NSPrivacyAccessedAPITypes` 新增 `UserDefaults`，reason `CA92.1`（AdMob SDK 內部使用）。
  `NSPrivacyAccessedAPITypes` adds `UserDefaults` with reason `CA92.1` (used internally by the AdMob SDK).

詳細的 AdMob 隱私說明請見 Google 隱私權與條款：<https://policies.google.com/privacy>。

See Google's privacy policy at <https://policies.google.com/privacy> for AdMob details.

### 內購 / In-App Purchase

「Remove Ads」一次性非消耗型內購（建議售價 $2.99 USD，依各地區 App Store 匯率自動換算）由 Apple StoreKit 處理。付款與帳單資料完全不經過 Sudoku App 後端 — Sudoku App 透過 StoreKit 2 API 只收到「是否已購買」的布林狀態，以及 StoreKit 簽章驗證結果。

The "Remove Ads" one-time non-consumable IAP (suggested $2.99 USD, automatically converted by each region's App Store) is processed by Apple StoreKit. Payment and billing data never reach the Sudoku App backend — the App only receives a boolean entitlement and StoreKit's cryptographic verification result via the StoreKit 2 API.

購買紀錄由 Apple 在你的 Apple ID 下保管；同一 Apple ID 的其他裝置可透過 *Settings → [Your Name] → Media & Purchases → Restore Purchases* 還原購買。

Purchase records are stored by Apple under your Apple ID; you can restore the purchase on other devices signed into the same Apple ID via *Settings → [Your Name] → Media & Purchases → Restore Purchases*.

## Changes to this policy

If we change data practices in a future version, we will update this document and the `PrivacyInfo.xcprivacy` manifest together in the same release, and note the change in the App Store *What's New* text for that version.

## Contact

- Issues and questions: <https://github.com/wei18/Sudoku/issues>
- Source code (this policy and the privacy manifest both live in the repo): <https://github.com/wei18/Sudoku>
