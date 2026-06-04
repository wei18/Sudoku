# RFC — CaptureGuardKit (window-layer black-on-capture guard)

- **Date:** 2026-06-04
- **State:** `RFC_FINAL` (Developer → Leader) — supersedes the design portion of the #286 proposal/research for the **content-hide / blackout** path.
- **Issue:** #286 (`PROPOSAL_APPROVED, parked`).
- **Supersedes / builds on:**
  - `meetings/2026-06-03_anti-capture-cheat-guard-proposal.md` (original proposal; detect-only v1 + deferred reactions).
  - `meetings/2026-06-04_screen-capture-block-research.md` (P4 research; field-level secure-layer trick, all fragility caveats).
- **What changed (headline):** The user supplied a concrete banking/authenticator technique that **blacks out the *entire window***, not just a field. This RFC **upgrades the blackout mechanism from field-level to window-level** and promotes the secure-layer content-hide from a "deferred reaction (d)" to the **primary blackout mechanism** behind a kill-switch. **Implementation still gates on the #286 P4 real-device spike** (user-owned) — this RFC is build-ready design only; **no package source is written here.**
- **Scope:** Design only. No production Swift. Per project rule, no implementation lands before this RFC is approved AND the device spike passes for default-ON.

> Conflict-resolution rule honoured throughout: where the user's article and our prior research disagree, **prefer the research's caveats** — the article omits screen-recording detection, iOS-version fragility, and the private-API / App-Store risk. All three are carried forward here.

---

## 1. Goal / non-goals

**Goal.** Provide a shared, opt-in SwiftPM target that blacks out the **game surface** (Sudoku board / Minesweeper field) in:

- **Screenshots** (hardware screenshot of the live screen),
- **Screen recordings** (Control-Center recording),
- **AirPlay / wired mirroring** (QuickTime, Apple TV),
- **App-switcher snapshots** and incoming-call/snapshot captures,

while the surface stays **fully visible and interactive on-device**. Black-out is render-server-enforced (the OS excludes a secure layer from the capture buffer), so it survives main-thread hangs and backgrounding.

**Non-goals (state explicitly to the user — a guard that claims these is a false promise):**

- ❌ **Not** defeating a **second physical camera** photographing the screen (threat **T4**, out of scope — render-server blanking cannot touch external optics).
- ❌ **Not** anti-tamper / anti-jailbreak / memory-editing (threat **T5**, different class).
- ❌ **Not** a hard guarantee. It is **best-effort deterrence**, unofficial, and **re-verified each iOS major**.
- ❌ **Not** macOS content protection — on macOS 15+ the compositor merges all windows before ScreenCaptureKit captures; per-window exclusion (`NSWindow.sharingType = .none`) is documented dead (research §3, #286 P5). macOS path is **no-op**.
- ❌ **Not** on by default until the **P4 device spike** passes (§6/§7).

**Opt-in per app.** Each app chooses whether to attach the guard to its game surface; the default conformer everywhere except a verified iOS device is `NoopCaptureGuard`.

---

## 2. Architecture

A new **leaf** SwiftPM package `Packages/CaptureGuardKit/`, mirroring `RemindersKit`'s shape exactly: a public protocol seam + a `Live` conformer (UIKit/private-layer trick, confined to `Live/` + `#if os(iOS)`) + a `Noop` conformer (macOS / kill-switch-off / Simulator) + Fakes in a separate testing product.

### 2.1 Package manifest (mirrors `RemindersKit/Package.swift`)

```swift
// swift-tools-version: 6.2
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("StrictConcurrency"),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("InternalImportsByDefault"),
]

let package = Package(
    name: "CaptureGuardKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "CaptureGuard", targets: ["CaptureGuard"]),
        .library(name: "CaptureGuardTesting", targets: ["CaptureGuardTesting"]),
    ],
    targets: [
        .target(name: "CaptureGuard", swiftSettings: swiftSettings),
        .target(name: "CaptureGuardTesting", dependencies: ["CaptureGuard"], swiftSettings: swiftSettings),
        .testTarget(name: "CaptureGuardTests", dependencies: ["CaptureGuard", "CaptureGuardTesting"], swiftSettings: swiftSettings),
    ],
    swiftLanguageModes: [.v6]
)
```

### 2.2 Target layout (mirrors `Reminders` / `Live` / `RemindersTesting`)

```
Packages/CaptureGuardKit/
  Package.swift
  Sources/
    CaptureGuard/
      CaptureGuarding.swift          # protocol seam + CaptureState/CaptureEvent value types + CaptureGuardConfig (kill-switch)
      NoopCaptureGuard.swift         # macOS / kill-switch-off / Simulator default; always .notCaptured, no blackout
      CaptureGuardedModifier.swift   # SwiftUI `.captureGuarded()` attach point (delegates to the injected guard)
      Live/
        LiveCaptureGuard.swift       # @MainActor; isCaptured + sceneCaptureState + screenshot notification; owns the blackout host
        SecureWindowBlackout.swift   # the ONE swappable internal type wrapping the private-layer surface (see §3.4)
    CaptureGuardTesting/
      FakeCaptureGuard.swift         # scriptable state/event driver; records start/stop + blackout engage/disengage
  Tests/
    CaptureGuardTests/
      …
```

### 2.3 Dependency direction (leaf — like `RemindersKit`)

`CaptureGuard` depends on **nothing internal**. It must **NOT** import `TelemetryKit` (whose `TelemetryEvent` imports `SudokuEngine` — a Sudoku type can't leak into a cross-app shared target). Telemetry is delivered via an **injected callback seam** (`onEvent`), exactly how `RemindersKit` / `AdGate` receive a host callback without depending on `Telemetry`. Internal logging uses `os.Logger` (subsystem = bundle id, category = `CaptureGuard`) per `oslog-logger-defaults`.

Apple-framework imports are **restricted** (per `swiftpm-modularization`): `UIKit` appears **only** in `Live/` files. The seam, value types, Noop, and the SwiftUI modifier shell stay framework-light (SwiftUI only where the modifier needs it).

### 2.4 Public seam

```swift
public enum CaptureState: Sendable, Equatable {
    case notCaptured
    case captured                 // live recording / mirroring / AirPlay active
}

public enum CaptureEvent: Sendable, Equatable {
    case guardEngaged             // blackout host installed over the surface
    case guardDisengaged
    case screenshotTaken          // iOS only, post-hoc (userDidTakeScreenshotNotification)
    case recordingStarted         // captured → on (isCaptured / capturedDidChange)
    case recordingStopped
    case privateLayerNotFound     // secure canvas lookup failed → degraded to visible (telemetry signal)
}

/// Build/remote kill-switch + tuning. Host supplies at composition.
public struct CaptureGuardConfig: Sendable, Equatable {
    public var isEnabled: Bool                 // master kill-switch → false routes to Noop behaviour
    public var blackoutOnRecording: Bool       // engage window blackout while `captured`
    public var blurAppSwitcherSnapshot: Bool   // app-switcher blur overlay (secondary)
    public init(isEnabled: Bool = false,       // DEFAULT-OFF until the P4 spike passes
                blackoutOnRecording: Bool = true,
                blurAppSwitcherSnapshot: Bool = true) { … }
}

@MainActor
public protocol CaptureGuarding: AnyObject {   // @MainActor: touches UIScreen / traits / window
    var captureState: CaptureState { get }
    var events: AsyncStream<CaptureEvent> { get }
    func start()
    func stop()
}
```

SwiftUI attach point (separate from the protocol so the surface can opt in without injecting the guard object into every view):

```swift
public extension View {
    /// iOS device + kill-switch-on: hosts `self` so it is blanked (black) in
    /// screenshots / recordings / mirroring while staying visible on-device.
    /// macOS / Simulator / kill-switch-off / private-layer-not-found → renders
    /// `self` unchanged (never hides the surface from the actual user).
    func captureGuarded(_ guard: any CaptureGuarding, config: CaptureGuardConfig) -> some View
}
```

### 2.5 Consumers (both apps)

- **Sudoku:** `Packages/SudokuKit/Sources/AppComposition/Live.swift` constructs `LiveCaptureGuard` (iOS) / `NoopCaptureGuard` (macOS, via `#if os(iOS)`), injects it + `CaptureGuardConfig` into the active-game route. The board view applies `.captureGuarded(guard, config:)`. `Preview.swift` wires `FakeCaptureGuard`. The injected `onEvent` maps each `CaptureEvent` into Sudoku's existing `Telemetry.observe(.errorOccurred(source: "CaptureGuard", code: …))` funnel.
- **Minesweeper:** `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift` — identical pattern; `.preview()` wires `FakeCaptureGuard`. (Per `minesweeper-mirrors-sudoku`.)

---

## 3. The blackout mechanism

### 3.1 PRIMARY — whole-window blackout via a secure `UITextField`'s layer (user-supplied article)

Adopted verbatim as the primary technique. Create a `UITextField`, set `isSecureTextEntry = true`, then **nest the app's real window inside the secure field's hidden layer**:

```
field.isSecureTextEntry = true
window.layer.superlayer?.addSublayer(field.layer)
field.layer.sublayers?.last?.addSublayer(window.layer)
```

Because iOS excludes a secure field's layer from screenshots / recordings / AirPlay at the **render-server** level, the whole window renders **BLACK** in any capture while staying visible on-device. This is the **"protect the entire window"** variant of the field-level trick our research described — the upgrade this RFC introduces.

**Why window-level over field-level (the change):** the research's `.hiddenFromCapture()` sketch reparented *one board view's* layer into the secure canvas. The article's window-level form blacks out the **whole window** in one install, so app chrome around the board (number pad, timer) is covered too without per-view wrapping, and there is a single install/teardown site instead of N. We keep the ability to scope to the surface via the `.captureGuarded()` modifier, but the underlying install is the window-layer reparent.

> **Caveat carried from research (NOT in the article):** this reparenting touches the **private** render-server update-mask path. The `field.layer.sublayers?.last` access is implementation-coupled to UIKit's internal secure-field layer composition. It MUST be wrapped behind one swappable type (§3.4), guarded at every optional, and degrade to a visible no-op + telemetry if the layer shape shifts (§4).

### 3.2 RECORDING path — `isCaptured` + `capturedDidChangeNotification` (research add; article omits)

The article covers screenshots and app-switcher snapshots but **NOT live screen-recording detection**. Per the research, `LiveCaptureGuard` additionally observes:

- **`UIScreen.main.isCaptured`** (initial read) and **`UIScreen.capturedDidChangeNotification`** (live transitions) to drive `recordingStarted` / `recordingStopped` and, when `config.blackoutOnRecording`, engage the window blackout for the duration of capture.
- iOS-26 caveat (research §2.1, Apple Forums #817446): `isCaptured` / `sceneCaptureState` reflect whether the **scene** is on the capture surface, not true device-level recording, and can flip when a system surface is promoted. We therefore treat it as a **blackout trigger** (false-positive only blacks out the surface harmlessly), **never** as a punitive signal. `sceneCaptureState` (iOS 17+) may be used as the preferred live trait read; `isCaptured` is the belt-and-suspenders initial read. Both are public APIs.

### 3.3 SECONDARY — snapshot blanking + app-switcher blur + screenshot detection (article)

- **`snapshotView(afterScreenUpdates:)` override returning an empty `UIView()`** — blanks the app-switcher / system snapshot card.
- **App-switcher blur:** add a `UIBlurEffect(style:)` overlay on `sceneWillResignActive`, remove on `sceneDidBecomeActive` (gated by `config.blurAppSwitcherSnapshot`).
- **Screenshot detection (react, cannot prevent the shutter):** `UIApplication.userDidTakeScreenshotNotification` → emit `screenshotTaken` to the injected telemetry callback (optional masking is a host decision).

### 3.4 Private-surface isolation — ONE swappable internal type

All private-layer coupling is confined to **`SecureWindowBlackout.swift`** — the single swap point so a future iOS break is a **one-file fix**:

- It owns the secure `UITextField`, the window-layer reparent (§3.1), and the teardown that restores the window to its original superlayer.
- The private surface lineage to name in comments (research §1.2): the secure container class has been **`_UITextLayoutCanvasView` since iOS 15 (stable through iOS 26)**; older lineage `_UITextFieldCanvasView` (iOS 13–14), `_UITextFieldContentView` (iOS 12). We do **not** hard-code symbol literals for behaviour (see §5); the reparent resolves by **layer structure** (`superlayer` / `sublayers.last`), and any class-name string used for a sanity check is matched **defensively** (if absent → `privateLayerNotFound` → visible no-op).
- The reverse-engineering history (research §1.5): unstable in the **iOS 17 beta**, ~50% reliable on one **iOS 18** build with the raw `0x12` flag; the Telegram-derived `setLayerDisableScreenshots` layer-mask path proved more reliable. If the window-reparent form proves flaky on the spike device, `SecureWindowBlackout` is the place to switch to the layer-mask variant **without touching the seam, the modifier, or either app**.

---

## 4. Safety / kill-switch

**Kill-switch (build + remote) → instant `NoopCaptureGuard` behaviour.**

- `CaptureGuardConfig.isEnabled == false` (the **default**) makes `LiveCaptureGuard` behave as a no-op: no reparent, no observers installed, `captureState` always `.notCaptured`. The host can flip this from a build flag or a remote config without any UI rewrite (the modifier stays attached; it just passes content through). macOS always uses `NoopCaptureGuard`.

**Graceful degradation — never crash, degrade to visible.**

- Every step of the window-layer reparent is optional-guarded (`window.layer.superlayer?`, `field.layer.sublayers?.last?`). If any link is `nil` (version drift, layer shape changed), `SecureWindowBlackout` **does not install**, leaves the window untouched (surface **visible** to the user — never hidden from the user as a failure mode), emits **`privateLayerNotFound`**, and logs via `os.Logger`. This is the single most important production property carried from research §4.2.
- `#if targetEnvironment(simulator)` and `#if os(macOS)` short-circuit to no-op so Previews / UITests / Simulator runs behave normally (the render-server mask is device-only).

**Telemetry events (via injected `onEvent`):**

| Event | When |
|---|---|
| `guardEngaged` / `guardDisengaged` | Window blackout host installed / torn down. |
| `screenshotTaken` | `userDidTakeScreenshotNotification` (post-hoc). |
| `recordingStarted` / `recordingStopped` | `isCaptured` / `capturedDidChange` transitions. |
| `privateLayerNotFound` | Secure layer lookup failed → degraded to visible. **This is the canary** that tells us the day an iOS release breaks the trick. |

---

## 5. App Store risk

**Concern (restated from research §1.4, proposal §5):** the technique uses **private render-server behaviour**. `isSecureTextEntry` is a public API; the gray area is depending on the secure field's **internal layer composition** (reparenting the window into it). Apple has given **no definitive yes/no** (Apple Developer Forums #792624) — widely shipped by banking/authenticator/fintech apps and apparently tolerated, but **never officially blessed**.

**Mitigation:**

- **No private symbol literals as behaviour.** Resolve by layer structure, not by calling private methods or hard-coding selector/class strings as control flow. Any class-name string is a defensive sanity check only.
- **Kill-switch** (§4) — disable at build or remotely with zero UI rewrite if Apple objects or an iOS release breaks it.
- **Precedent** — the secure-layer family is widely shipped by banking apps; empirical pass rate is high, rejection risk **low but non-zero**. Breakage-per-iOS-release is the larger *practical* cost (research §1.5).
- **Privacy manifest:** capture *detection* + blackout read no personal data and add no `PrivacyInfo.xcprivacy` API-reason entries by themselves; confirm during impl (low risk).

**Decision:** ship behind the kill-switch; **default-OFF**, flipped to **default-ON only after the P4 device spike passes** (§6/§7). Re-verify each iOS major; treat `privateLayerNotFound` telemetry as the trigger to re-spike.

---

## 6. Test strategy

**Unit-testable (agent-doable, no device) — `swift-testing` + protocol fakes (`swift-testing-baseline`):**

- The **seam**: `CaptureGuarding` conformance, `events` `AsyncStream` delivery, `start()`/`stop()` lifecycle.
- **Kill-switch routing**: `config.isEnabled == false` ⇒ `LiveCaptureGuard` behaves as Noop (no observers, `captureState == .notCaptured`); the `.captureGuarded()` modifier passes content through.
- **`NoopCaptureGuard`**: always `.notCaptured`, empty stream, no blackout.
- **`FakeCaptureGuard`**: drives scripted `CaptureEvent`s so each app's telemetry mapping (`CaptureEvent → Telemetry.observe(...)`) is asserted without touching the system.
- **Modifier no-op fidelity**: on macOS / Simulator the modifier returns content unchanged (snapshot/unit).

**ONLY device-verifiable (user-owned — cannot be asserted in Simulator/UITests):**

The actual blackout is render-server-enforced and **does not work in Simulator or UI tests**. It is verified by the **P4 real-device spike checklist** (research §6, re-scoped to window-level here):

- Does a **screenshot** of the live screen render the surface **black** on a physical iPhone, current iOS?
- Does a **screen recording** render it black throughout? AirPlay/QuickTime mirror?
- Is the **window-layer reparent** structurally present (sanity-check the secure canvas lineage `_UITextLayoutCanvasView` on the shipping build)?
- **Second-camera bypass confirmed expected** (surface visible — by design, T4).
- **No crash on version drift**: mis-shape the layer lookup → app does NOT crash, surface stays **visible**, `privateLayerNotFound` fires.
- **Live UX sanity**: user sees the surface normally; taps/hit-testing unaffected by the mask.

Spike PASS criterion: screenshot + recording both blank, layer lineage confirmed, graceful no-op verified, second-camera/Simulator behave as expected → flip **P4 → Resolved-conditional**, record the tested iOS version as the "last verified" baseline, then flip `CaptureGuardConfig.isEnabled` default to ON.

---

## 7. Prerequisite checklist (collaboration framework)

| ID | Dependency | Status | Note / what the spike must resolve |
|----|-----------|--------|-----------------------------------|
| P1 | `UIApplication.userDidTakeScreenshotNotification` (post-hoc screenshot detection) | **Verified ✓** | Apple UIKit docs; since iOS 7. Fires after the shot. |
| P2 | `UITraitCollection.sceneCaptureState` + `registerForTraitChanges` (live capture detection, iOS 17+) | **Verified ✓** | Apple docs; repo floor iOS 26, well in range. |
| P3 | `UIScreen.isCaptured` + `capturedDidChangeNotification` (recording/AirPlay trigger) | **Verified ✓** | Apple docs; iOS 11+. Used as the recording-blackout trigger (§3.2). Scene-vs-device caveat (Forums #817446) → trigger only, never punitive. |
| P4 | **Window-layer secure-field blackout** (`isSecureTextEntry` + window-layer reparent, private render-server update-mask) | **Unconfirmed ?** | **Spike must resolve, on a current physical iPhone:** (1) does a screenshot of the live screen actually go **black**? (2) does a screen recording go black throughout (+ AirPlay)? (3) is the window-layer reparent structurally available and the secure canvas lineage `_UITextLayoutCanvasView` present on the shipping iOS build? (4) does the **mis-shape / version-drift** path no-op gracefully (no crash, surface visible, `privateLayerNotFound` fires)? (5) confirm second-camera + Simulator bypass behave as designed. **Blocks default-ON only**; the package + seam + Noop + kill-switch-OFF Live can be built without it. |
| P5 | `snapshotView(afterScreenUpdates:)` override + app-switcher blur (`sceneWillResignActive`/`sceneDidBecomeActive`) | **Unconfirmed ?** | Public APIs, but **device-verify** the snapshot card / app-switcher actually blanks/blurs on the shipping iOS (same spike session). |
| P6 | `NSWindow.sharingType = .none` (macOS window exclusion) | **Verified ✓ — NEGATIVE** | Documented dead on macOS 15+ (research §3). macOS = no-op. Do not build on this. |
| P7 | Swift 6 concurrency: `LiveCaptureGuard` `@MainActor` (UIScreen/traits/window); `CaptureState`/`CaptureEvent`/`CaptureGuardConfig` `Sendable`; events via `AsyncStream` | **Verified ✓** | Matches existing kit posture (`swift6-concurrency`). |
| P8 | Min-OS availability vs targets (`.iOS(.v26)` / `.macOS(.v26)`) | **Verified ✓** | All cited APIs ≤ iOS 17; floor is iOS 26. No back-deploy branches. |

**Approval gate:** the **package scaffold + seam + Noop + kill-switch-OFF Live** have all prerequisites **Verified ✓** and are build-ready now. **Default-ON** is blocked by **P4 + P5 (Unconfirmed ?)**, resolved only by the user-owned device spike.

---

## 8. Rollout

| Phase | Deliverable | Owner | Verifiable in Simulator/CI? |
|-------|-------------|-------|-----------------------------|
| **1** | Package scaffold + `CaptureGuarding` seam + value types + `CaptureGuardConfig` + `NoopCaptureGuard` + `FakeCaptureGuard` + `.captureGuarded()` modifier shell + unit tests (seam, kill-switch routing, Noop, modifier no-op) | **Agent** | ✅ Yes — pure no-device logic. |
| **2** | `LiveCaptureGuard` + `SecureWindowBlackout` (window-layer reparent, isolated) + `isCaptured`/screenshot/app-switcher wiring + kill-switch (default-OFF) + both apps' composition wiring + telemetry mapping | **Agent** | ⚠️ Builds + passes Simulator (everything no-ops on Sim); the **blackout itself is NOT verifiable** in Simulator. |
| **3** | **P4/P5 device spike** (§6 checklist) on a physical iPhone, current iOS → fill the result table, confirm graceful no-op + bypass boundaries → flip `CaptureGuardConfig.isEnabled` **default to ON** + record "last verified iOS" | **User** | ❌ No — device-only. |

**Agent-doable vs user-owned split:** phases 1 & 2 are fully agent-doable (build green in Simulator/CI, all blackout paths no-op there); phase 3 (the only proof the surface actually goes black, plus the flip to default-ON) is **user-owned** and gates on real hardware.

---

## 9. Status note

`RFC_FINAL`. No production Swift written; no package source created. On Leader/user approval, phases 1–2 decompose into agent issues (build-ready, Simulator-green); phase 3 is the user-owned #286 device spike that flips default-ON. Per project rule, no implementation lands before this RFC is approved.
