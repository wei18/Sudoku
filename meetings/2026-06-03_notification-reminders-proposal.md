# Notification Reminder Mechanism — Design Proposal

**Date**: 2026-06-03
**State**: PROPOSAL_DRAFT (Developer → Leader review)
**Author role**: Developer
**Topic**: Local-notification reminder system + permission-request flow, shared across Sudoku and Minesweeper
**User goal (verbatim)**: 「notification 提醒機制, 包含權限詢問」 — a reminder-notification system plus the permission-asking flow (e.g. "your Daily puzzle is ready", streak / comeback nudges). Solo indie apps, **no backend server**.

> Scope note: This is a **design proposal only**. No production Swift here. On approval it advances PROPOSAL_APPROVED → RFC_FINAL → USER_APPROVED → issues. Code snippets below are illustrative signatures, not deliverables.

---

## 0. Prerequisite checklist (collaboration-mode rule — Unconfirmed blocks approval)

Every system-API dependency, marked **Verified ✓** (with Apple doc URL) or **Unconfirmed ?**.

| # | Capability / API | Status | Evidence |
|---|---|---|---|
| P1 | `UNUserNotificationCenter` is the framework for **local** notifications with **no APNs / server** | **Verified ✓** | [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) — local notifications are configured and scheduled entirely on-device. |
| P2 | `requestAuthorization(options:)` async API + `UNAuthorizationStatus` (incl. `.notDetermined / .denied / .authorized / .provisional`) | **Verified ✓** | [requestAuthorization(options:completionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:)) (async variant available); [UNAuthorizationStatus.provisional](https://developer.apple.com/documentation/usernotifications/unauthorizationstatus/provisional) |
| P3 | **Provisional authorization** (`.provisional`) — quiet delivery, **no upfront prompt**, user confirms after a few deliveries | **Verified ✓** | [UNAuthorizationStatus.provisional](https://developer.apple.com/documentation/usernotifications/unauthorizationstatus/provisional). Quiet-delivered to Notification Center; the on-notification prompt lets users keep/turn-off. |
| P4 | `UNCalendarNotificationTrigger` (dateMatching, `repeats:`) + `UNTimeIntervalNotificationTrigger` | **Verified ✓** | [UNNotificationRequest](https://developer.apple.com/documentation/usernotifications/unnotificationrequest) flow: create trigger → `UNNotificationRequest` → `add(_:)`. |
| P5 | **64 pending-request limit**; only the 64 soonest-to-fire are kept; a *repeating* trigger counts as **1** slot | **Verified ✓** | Apple Dev Forums + [getPendingNotificationRequests](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:)). System unschedules non-repeating after delivery. |
| P6 | Foreground presentation via `UNUserNotificationCenterDelegate.userNotificationCenter(_:willPresent:)` returning `UNNotificationPresentationOptions` (`.banner/.list/.badge/.sound`) | **Verified ✓** | [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate); [willPresent](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:)). Not called when backgrounded. |
| P7 | `getNotificationSettings()` to re-check status at any time (user can change in Settings) | **Verified ✓** | [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter) §getNotificationSettings. |
| P8 | Settings deep-link via `UIApplication.openNotificationSettingsURLString` (iOS 16+) | **Verified ✓** | [openNotificationSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring). App-Store-safe replacement for `prefs:` hacks. |
| P9 | Min-OS availability vs **iOS 18 / macOS 15** target | **Verified ✓** | UserNotifications shipped iOS 10 / macOS 10.14; provisional iOS 12; `openNotificationSettingsURLString` iOS 16 / no macOS equivalent. All comfortably ≤ our floor. (See P12 for macOS deep-link gap.) |
| P10 | Local notifications on **macOS** via the modern `UserNotifications` framework | **Verified ✓** | Modern `UserNotifications` supports local notifications on macOS 10.14+. (The "macOS doesn't support local notifications" line surfaced in web search is from the **archived** Local/Remote Notification *Programming Guide*, which predates UserNotifications — does **not** apply at our macOS 15 target. Flagging to avoid a stale-doc trap.) |
| P11 | **PrivacyInfo.xcprivacy**: does scheduling local notifications add a required-reason entry? | **Verified ✓ (no entry needed)** | UserNotifications is **not** on the [Required Reason API](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest) list, and we collect/transmit nothing → no `NSPrivacyTrackingDomains`, no new data-collection key. Existing `Sudoku/Resources/PrivacyInfo.xcprivacy` + `Minesweeper/Resources/PrivacyInfo.xcprivacy` stay as-is. |
| P12 | macOS Settings deep-link | **Unconfirmed ?** | `openNotificationSettingsURLString` is **UIKit-only** (no AppKit equivalent confirmed). macOS denial-recovery copy must instead instruct "System Settings → Notifications → [App]" (or attempt `x-apple.systempreferences:` URL — unverified, App-Review-risky). **Does NOT block approval** — it only narrows the macOS denial-path UX; resolve during RFC. |

**Approval gate**: P1–P11 Verified. P12 is the sole Unconfirmed item and is non-blocking (a UX detail on one platform's denial path, not a feasibility risk). **No blocking Unconfirmed prerequisite.**

---

## 1. Relation to issue #195 (reconciliation — required)

Issue #195 *"Permission request UX (ATT tracking + push notifications) — design + copy"* (labels: backlog, monetization) bundles **two unrelated permission prompts**:

1. **ATT** (`NSUserTrackingUsageDescription`) — for AdMob personalized ads. Monetization concern. Already has a functional Info.plist string from PR #194.
2. **Push / notification permission** — listed as a *product question* (daily-puzzle reminder, leaderboard, streak), explicitly tagged "v3 push-notifications feature work".

**Recommended reconciliation:**

- **This proposal SUBSUMES the notification slice of #195** (deliverables: "Push notification permission design — when/why/fallback" and the notification portion of "Permission denial → Settings deep-link UX"). The reminder mechanism *is* the why/when/fallback, designed in full here rather than as a one-line bullet.
- **#195 is rescoped to ATT-only**: localized ATT copy for 7 locales, the defer-ATT-prompt decision, and the ATT-specific denial path. ATT is a monetization/tracking concern with a different prompt, different copy, and a different trigger (first ad load) — keeping them separate respects SRP and avoids a permission-prompt pile-up at launch.
- **Cross-reference, do not duplicate**: when this proposal becomes an RFC + issues, the notification-permission issue should `Closes`/links the notification checkboxes of #195, and #195's title/body should be edited to drop "push notifications" from scope (Leader/user action).
- **Terminology correction for #195**: #195 says "push notifications". This proposal uses **local** notifications (no APNs, no server) — matching the solo-indie / no-backend constraint. "Push" in #195 is a misnomer for our actual use case.

Open item for Leader: confirm we may edit #195's scope, or whether to file a fresh notification-permission issue and leave #195 untouched.

---

## 2. Use cases / reminder types (per app — which are worth it)

| # | Reminder | Sudoku | Minesweeper | Trigger kind | Worth it? |
|---|---|---|---|---|---|
| U1 | **Daily-puzzle ready** ("Today's Sudoku is ready") | ✅ has Daily mode | ❌ **no Daily yet** (MS Standard tier explicitly excludes date-seeded Daily — see `MinesweeperUI/NewGameView.swift`, `MinesweeperRoot.swift`) | `UNCalendarNotificationTrigger`, repeats daily at a fixed local hour | **Yes (Sudoku)**. **N/A for MS** until/unless MS gains Daily (note the mirror-Sudoku target plan: if MS adds Daily later, this reminder type drops in for free via the shared target). |
| U2 | **Streak-keeper** ("Keep your N-day streak alive — play before midnight") | ✅ | ✅ (generic "played today" streak, even without Daily) | Calendar trigger near end-of-day, rescheduled when the user plays | **Yes, but** depends on a streak concept existing. Sudoku Daily implies streak; MS streak = "opened a game today". Flag as dependent on a streak model (open question Q3). |
| U3 | **Comeback / win-back** ("Haven't played in a while — a quick puzzle?") | ✅ | ✅ | `UNTimeIntervalNotificationTrigger` (e.g. 3 / 7 days after last session), rescheduled on every launch | **Maybe** — borderline dark-pattern if aggressive. Recommend: single, gentle, opt-out-respecting, max once per inactivity window. Defer to v2 of the feature; ship U1 first. |
| U4 | Leaderboard / "a friend passed you" | — | — | needs Game Center push or server | **No** — requires APNs/server; out of scope for a serverless design. Explicitly excluded. |

**Recommendation**: Ship **U1 (Sudoku Daily-ready)** as the anchor use case — it has the clearest user value, maps to a single repeating trigger (1 of 64 slots), and needs no streak model. Treat **U2** as a fast-follow once a streak model is agreed; **U3** as opt-in, gentle, later. **U4 excluded** (server-dependent). The shared target (§4) makes all of U1–U3 the same code path differing only in content + trigger.

---

## 3. Local-notification design

### 3.1 Triggers & scheduling

- **U1 Daily-ready**: one `UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: H, minute: M), repeats: true)`. Single slot, fires daily, survives reboots. Default hour configurable (Q4) — propose a sensible local-morning default (e.g. 09:00) with a Settings control later.
- **U2 Streak / U3 comeback**: non-repeating `UNCalendarNotificationTrigger` / `UNTimeIntervalNotificationTrigger`, **rescheduled on each app foreground** (and on relevant game events) using a stable per-type **identifier** so the new one replaces the old.

### 3.2 The 64-limit strategy

Our footprint is tiny (≤ ~3 pending at once), so we are nowhere near 64 — **but** we adopt the safe discipline regardless:

- **Identifier-scoped replacement, never `removeAllPendingNotificationRequests()`**. Each reminder type owns a constant identifier (`"daily-ready"`, `"streak-keeper"`, `"comeback"`). Reschedule = `removePendingNotificationRequests(withIdentifiers:)` for that one id, then `add(_:)`. This avoids the documented async race where `removeAll…` runs on a background thread and can delete just-added requests (Apple Dev Forums, verified in P5 search).
- Prefer **repeating** triggers where the cadence is fixed (U1) — 1 slot, no per-day churn.

### 3.3 Content / copy

- `UNMutableNotificationContent`: `title`, `body`, `sound = .default` (only if `.alert/.sound` granted), no badge by default (badge nudging reads as a dark pattern; opt-in only).
- Copy localized via `Localizable.xcstrings` (per `ai-translated-localization`, 7 locales: zh-TW, en, ja, zh-CN, es, th, ko; min zh-TW + en). Copy authoring is an RFC deliverable; placeholders here:
  - U1: title "Today's puzzle is ready" / body "Your daily Sudoku is waiting."
  - U2: "Keep your streak alive" / "Play today to keep your N-day streak."
- Per-app branding: copy strings live in each app's catalog; the shared target takes content as a value type, never hard-codes app-specific text.

### 3.4 Cancellation

- On opt-out (in-app toggle) or detected `.denied`: `removeAllPendingNotificationRequests()` is acceptable **here** (teardown, nothing being added concurrently) OR scoped removal of our known ids. Prefer scoped for consistency.
- When a reminder's premise lapses (e.g. user already played today's Daily) → remove that id.

### 3.5 Foreground handling

- A single `UNUserNotificationCenterDelegate` set **once** at launch (composition root). `willPresent` returns `[]` for our reminder category when the relevant screen is already open (a "Daily ready" banner is noise if you're mid-Daily), else `[.banner, .sound]`. Decision table is per-reminder-category metadata, not scattered logic.
- macOS forces banner style regardless of requested `.alert` (verified) — acceptable; our reminders are non-critical.

---

## 4. Shared-target design

### 4.1 Shared vs per-app — **Recommendation: SHARED target**

Strong recommendation: **one shared SwiftPM target**, consumed by both apps — same rationale as `GameShellKit` and the proposed `CaptureGuard`, and directly endorsed by the *reusable-targets-over-duplication* and *minesweeper-mirrors-sudoku* memory notes. The scheduling/permission machinery is 100% game-agnostic; only **content** (copy) and **which reminder types are enabled** differ, and both are injected as data.

### 4.2 Name — **Recommendation: `RemindersKit` package, target `Reminders`**

Candidates considered: `RemindersKit` / `NotificationScheduler` / `NotificationsKit`.
- `NotificationScheduler` over-narrows (it's also auth + delegate + Settings deep-link, not just scheduling).
- `NotificationsKit` collides conceptually with Apple's `UserNotifications`.
- **`RemindersKit`** (product) with target **`Reminders`** reads at the product/domain level ("reminders"), matches the `…Kit` package + bare-domain-target convention (`SudokuKit`/`SudokuUI`, `GameShellKit`/`GameShellUI`), and is app-neutral.

> Naming nuance: Apple ships a consumer app literally called *Reminders*. The **target** name `Reminders` is internal (module name) and fine; if Leader prefers extra distance, fallback `AppRemindersKit` / target `AppReminders`. Recommend `RemindersKit`/`Reminders`; defer final call to Leader (Q1).

### 4.3 Location

New package `Packages/RemindersKit/` mirroring the existing one-package-per-Kit layout (sibling of `TelemetryKit`, `GameShellKit`). Single production target `Reminders` + `RemindersTesting` (shared fakes) + `RemindersTests` (one test target per production target, per `swiftpm-modularization`).

### 4.4 Public API (protocol seam + async surface)

Two protocol seams so the awkward-to-fake `UNUserNotificationCenter` is wrapped (per `swift-testing-baseline` protocol-injected fakes):

```swift
// Sendable value types
public struct ReminderContent: Sendable { /* title, body, sound: Bool, categoryId */ }
public enum ReminderSchedule: Sendable {
    case dailyAt(hour: Int, minute: Int)          // → repeating UNCalendarNotificationTrigger
    case after(seconds: TimeInterval)             // → UNTimeIntervalNotificationTrigger
    case onDate(DateComponents)                   // → one-shot UNCalendarNotificationTrigger
}
public enum ReminderKind: String, Sendable { case dailyReady, streakKeeper, comeback }  // == identifier

public enum ReminderAuthStatus: Sendable { case notDetermined, denied, authorized, provisional }

// Seam 1 — permission
public protocol NotificationAuthorizing: Sendable {
    func currentStatus() async -> ReminderAuthStatus
    @discardableResult func requestAuthorization(provisional: Bool) async -> ReminderAuthStatus
}

// Seam 2 — scheduling
public protocol ReminderScheduler: Sendable {
    func schedule(kind: ReminderKind, content: ReminderContent, on: ReminderSchedule) async
    func cancel(kind: ReminderKind) async
    func cancelAll() async
}
```

- **Concurrency** (`swift6-concurrency`): all `Sendable`; `UNUserNotificationCenter` async APIs are awaited; the delegate adapter is `@MainActor`-isolated (UIKit/AppKit delegate contract). Package builds in Swift 6 language mode like every sibling.
- **SwiftUI surface**: a small `@MainActor @Observable ReminderPermissionModel` (lives in `Reminders` or in `GameShellUI` if it needs shell chrome — Q2) drives the **soft pre-ask sheet** and exposes `status` + `requestFromPrimer()` + `openSettings()`. The primer **view** itself is generic and can live in `GameShellUI` (shared chrome) so both apps render an identical sheet with injected copy — consistent with GameShellKit owning cross-game chrome.

### 4.5 Live / Noop / Fake

| Impl | Target | Imports `UserNotifications`? | Use |
|---|---|---|---|
| `LiveNotificationAuthorizer` + `LiveReminderScheduler` (wrap `UNUserNotificationCenter.current()`) | `Reminders` | **Yes — the only place** | Production |
| `NoopReminderScheduler` / `NoopNotificationAuthorizing` (status `.notDetermined`, no-ops) | `Reminders` | No | macOS-if-deferred, previews, or apps not yet wiring reminders |
| `FakeReminderScheduler` / `FakeNotificationAuthorizing` (records calls, scriptable status) | `RemindersTesting` | No | unit tests assert "scheduled kind=.dailyReady with dailyAt(9,0)" without touching the system center |

`UserNotifications` import is **restricted to the `Reminders` target's Live files only** — same discipline as `CloudKit`→Persistence, `GameKit`→GameCenterClient, `GoogleMobileAds`→AdsAdMob (`swiftpm-modularization` restricted-imports rule). UI/logic layers see only the protocols.

### 4.6 Relation to the Telemetry facade

No new logging stack. `Reminders` **does not import** `Telemetry`; instead, like `AdGate`, the host injects callbacks / the composition root observes outcomes and calls `telemetry.observe(...)`. New `TelemetryEvent` cases to add (RFC):

```
case notificationPermissionRequested(provisional: Bool)
case notificationPermissionResolved(status: String)   // granted / denied / provisional
case reminderScheduled(kind: String)
case reminderFired(kind: String)                       // from didReceive delegate
case reminderOpenedApp(kind: String)
```

These flow through the existing `OSLogSink` + `NoOpTrackingSink` fan-out — zero call-site change elsewhere, matching `telemetry-facade-pattern`. `os.Logger` usage inside Live impls follows `oslog-logger-defaults` (subsystem = bundle id, category = "Reminders", interpolation `.private` by default).

### 4.7 Composition wiring

Each app's `Live.swift` constructs the Live impls and the delegate, exactly where AdMob/Persistence are wired today:
- `Packages/SudokuKit/Sources/AppComposition/Live.swift` → build `LiveReminderScheduler`, `LiveNotificationAuthorizer`, set the `UNUserNotificationCenterDelegate`, schedule U1 on Daily availability.
- `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift` → same wiring; U1 omitted (no Daily) until MS gains Daily. `Noop` impls where a reminder type isn't enabled.
- `AppComposition.swift` (struct) gains `reminderScheduler` / `notificationAuthorizing` fields; `Preview.swift` wires the Noop/Fake variants.

---

## 5. Permission flow

### 5.1 The flow (recommended)

```
1. App does NOT ask on cold first launch.                    → verify: no prompt at launch
2. User experiences value (finishes 1 Daily, or taps a
   "Remind me when tomorrow's puzzle is ready" affordance).  → verify: prompt only after value moment
3. Soft pre-ask sheet (our UI, generic, injected copy):
   explains exactly what we'll send + benefit + "Not now".   → verify: declining here = NO system prompt
4. If user accepts primer → fire the ONE-SHOT system prompt
   requestAuthorization([.alert, .sound]).                   → verify: status transitions notDetermined→authorized/denied
5. On .denied later: in-app explainer + deep-link to Settings
   (iOS openNotificationSettingsURLString; macOS = textual
   guidance per P12).                                        → verify: button opens Settings on iOS
6. Re-check getNotificationSettings() on each foreground;
   reconcile UI + reschedule/cancel accordingly.
```

The soft pre-ask is the **filter** that preserves the one-and-only system prompt (verified: the iOS system prompt can appear only once; declining the *primer* is repeatable). Timing = contextual moment-of-value, not launch (HIG-aligned; Cluster case study: ~89% opt-in when user-triggered vs 30–40% cold).

### 5.2 Provisional vs explicit — **fork + recommendation**

| | **Explicit** `[.alert, .sound]` (after primer) | **Provisional** `[.provisional, .alert, .sound]` |
|---|---|---|
| Upfront prompt | Yes (one shot) | **No prompt** — quiet delivery to Notification Center |
| Visibility | Banner + sound from day 1 | Quiet (NC only) until user taps "Keep" on a delivered notification |
| Risk | A hard "Don't Allow" is permanent (→ Settings only) | No hard denial possible up front; lower friction |
| Downside | Lower opt-in if mistimed | Reminders are *quiet* → "Daily ready" may go unseen; user must promote them; cannot combine with an already-accepted/denied explicit grant |
| Best for | High-value, clearly-wanted reminders | Low-stakes, "let the notification sell itself" |

**Recommendation: explicit, primer-gated** for U1 (Daily-ready). The whole point of a Daily reminder is a *visible* nudge; provisional's quiet delivery defeats it, and the primer already de-risks the one-shot prompt. **Keep `provisional: Bool` in the `NotificationAuthorizing` API** so we can A/B or use provisional for the lower-stakes U3 comeback nudge later without an API change. (Leader decision Q5.)

### 5.3 Denial path

- iOS: explainer + button → `UIApplication.shared.open(URL(string: UIApplication.openNotificationSettingsURLString)!)`.
- macOS: textual "System Settings → Notifications → [App]" guidance (P12 Unconfirmed — resolve in RFC).
- Never re-fire the system prompt (it won't show); re-ask only via our primer at the next genuine value moment, gently (Headspace pattern). No nagging.

---

## 6. Privacy / App-Store review

- **PrivacyInfo.xcprivacy**: **no change needed** (P11). UserNotifications is not a required-reason API; we collect/transmit nothing; no tracking domain. The "no third-party tracking" claim in `apple-three-piece-analytics` holds. Existing `Sudoku/Resources/PrivacyInfo.xcprivacy` and `Minesweeper/Resources/PrivacyInfo.xcprivacy` unchanged.
- **No dark patterns**: no badge-spam, no guilt copy, no asking on launch, no re-prompt loops. Comeback nudge (U3) capped and deferred.
- **Opt-out**: a Settings toggle per reminder type (or one master toggle in v1). Opt-out → `cancel(kind:)` / `cancelAll()`. Honor system `.denied` as opt-out.
- **No `UIBackgroundModes`/APNs entitlement** — local-only, so no push entitlement, no server, no APNs key (avoids `apple-public-repo-security` secret surface entirely).

---

## 7. Open questions (Leader / user)

- **Q1 (Leader)**: Final target name — `RemindersKit`/`Reminders` (recommended) vs `AppRemindersKit`/`AppReminders` (extra distance from Apple's Reminders app)?
- **Q2 (Leader)**: Does the primer **view** live in `GameShellUI` (shared chrome, my lean) or in `Reminders`? Affects whether `RemindersKit` depends on SwiftUI/shell.
- **Q3 (user)**: Is there a **streak model** today, or does U2 require designing one first? (Affects whether U2 ships with U1 or later.)
- **Q4 (user)**: Default Daily-reminder fire time — fixed 09:00 local for v1, or user-configurable from the start?
- **Q5 (Leader/user)**: Confirm **explicit-primer-gated** over provisional for U1 (recommended), keeping provisional reserved for U3.
- **Q6 (Leader)**: #195 reconciliation — OK to **edit #195 to ATT-only** and file a new notification issue that subsumes its push bullets, or keep #195 intact and just cross-link?
- **Q7 (Leader)**: `GameShellKit` targets **iOS 26 / macOS 26** (a recorded deviation), while the app floor is iOS 18 / macOS 15. Should `RemindersKit` follow the app floor (iOS 18 / macOS 15 — all APIs available) or match GameShellKit's 26 floor for consistency? My lean: **iOS 18 / macOS 15** (no API needs 26; widest reach), recorded in `foundations.md`.
- **Q8 (Leader)**: macOS scope for v1 — wire Live on macOS too, or `Noop` on macOS first (P12 deep-link gap) and iOS-only reminders for v1?

---

## 8. Next steps (post-approval)

This is a **proposal only**. On PROPOSAL_APPROVED → produce an **RFC** (`RemindersKit` Package.swift, full public API, copy strings for 7 locales, delegate lifecycle, per-app wiring diffs, test plan with `FakeReminderScheduler`). RFC → USER_APPROVED → dependency-ordered issues (likely: P1 package scaffold + protocols + fakes; P2 Live impls + delegate; P3 primer UI + Settings deep-link; P4 Sudoku U1 wiring + telemetry events; P5 #195 ATT rescope). **No implementation code before RFC + plan approval.**

---

### Sources (Apple docs verified during this proposal)

- [UNUserNotificationCenter](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter)
- [requestAuthorization(options:completionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/requestauthorization(options:completionhandler:))
- [UNAuthorizationStatus.provisional](https://developer.apple.com/documentation/usernotifications/unauthorizationstatus/provisional)
- [UNNotificationRequest](https://developer.apple.com/documentation/usernotifications/unnotificationrequest)
- [getPendingNotificationRequests(completionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenter/getpendingnotificationrequests(completionhandler:))
- [UNUserNotificationCenterDelegate](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate)
- [userNotificationCenter(_:willPresent:withCompletionHandler:)](https://developer.apple.com/documentation/usernotifications/unusernotificationcenterdelegate/usernotificationcenter(_:willpresent:withcompletionhandler:))
- [openNotificationSettingsURLString](https://developer.apple.com/documentation/uikit/uiapplication/opennotificationsettingsurlstring)
- [TN3183: Required reason API entries](https://developer.apple.com/documentation/technotes/tn3183-adding-required-reason-api-entries-to-your-privacy-manifest)
