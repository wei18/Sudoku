# DESIGN PROPOSAL — Anti-Capture Cheat-Guard (shared SwiftPM target)

- **Date:** 2026-06-03
- **State:** `PROPOSAL_DRAFT` (Developer → Leader)
- **Author:** Developer
- **Scope:** Design proposal only. NO production Swift. Implementation follows after approval (→ RFC → issues).
- **User goal (verbatim):** 「防止螢幕截圖或 video recording 的取巧方式破解遊戲」 — stop players using screenshots / screen recording to cheat: capture the board → external solver/OCR; record → replay; share Daily answers. Must be a **shared target consumed by BOTH apps** (Sudoku + Minesweeper).

---

## 0. Headline reality (read this first)

> **iOS has no public API to *block* a screenshot.** There is no Android `FLAG_SECURE` equivalent. You can only (a) **detect after-the-fact** that a screenshot was taken, (b) **detect** (and react to) live screen recording / mirroring, and (c) **hide** specific content from the capture buffer using the unofficial `isSecureTextEntry` secure-layer trick. On **macOS 15+ the window-exclusion path (`NSWindow.sharingType = .none`) no longer works against ScreenCaptureKit** — Apple now documents `.none` as "a legacy constant that macOS no longer uses."

This means the feature is **best-effort deterrence + leaderboard-integrity signalling**, not a hard lock. The proposal is honest about which threats are mitigable and which are not.

---

## 1. Threat model

| # | Vector | What the cheater does | Realistically mitigable? |
|---|--------|----------------------|--------------------------|
| T1 | **Screenshot → external solver / OCR** | Screenshots the board, feeds an image to an OCR + Sudoku/Minesweeper solver, transcribes the answer back. | **Partially.** Cannot block the screenshot. Can *detect* it (post-hoc) and optionally hide the board content from the captured image via the secure-layer trick. A determined user can still photograph the screen with a second device — unmitigable. |
| T2 | **Screen recording / mirroring → replay** | Records a solved run (or mirrors to a second screen for a helper) and replays inputs. | **Detectable** while active (`sceneCaptureState` / `isCaptured`). Can blur/pause and/or mark the run unranked. Cannot block. |
| T3 | **Daily-answer sharing** | Screenshots/records the completed Daily board and shares it so others copy the solution. | **Weakly.** Same as T1 for the capturer. The real defence is product-side (Daily already has a fixed seed per day; the leaderboard is the integrity surface, not the screenshot). |
| T4 | **Second-camera / external photo** | Photographs the screen with another phone. | **Not mitigable by software.** Out of scope. State this explicitly to the user. |
| T5 | **Jailbreak / instrumentation / memory editing** | Reads game state directly from memory or patches the binary. | **Out of scope** for a *capture* guard. Different threat class (anti-tamper). Mentioned only to bound scope. |

**Honest conclusion:** The only vectors this target can meaningfully touch are T1 (detect + optional content-hide), T2 (detect + react), and T3 (same primitives as T1). T4/T5 are out of scope and must be communicated as such — a "screenshot guard" that markets itself as unbreakable is a false promise and (see §5) a review/UX risk.

---

## 2. Capabilities & limits — what the OS actually allows (grounded in verified APIs)

| Goal | iOS | macOS | Notes |
|------|-----|-------|-------|
| **Block** a screenshot | ❌ No public API | ❌ No public API | Apple confirmed (Jul 2025 forum) "no public APIs for preventing screen capture." |
| **Detect** a screenshot (post-hoc) | ✅ `UIApplication.userDidTakeScreenshotNotification` | ❌ no equivalent | Fires *after* the shot; no pre-empt. |
| **Detect** live recording/mirroring | ✅ `UITraitCollection.sceneCaptureState` (iOS 17+) with `isCaptured` fallback | ⚠️ `NSScreen`/CG APIs exist but coarse | `isCaptured` is the legacy path; cannot distinguish recording vs AirPlay vs mirror. |
| **Hide content** from the capture buffer | ⚠️ Unofficial `isSecureTextEntry` secure-layer trick (renders black in screenshots *and* recordings) | ❌ no equivalent that survives ScreenCaptureKit | Unsupported/fragile; see §3.4 + prerequisite P4. |
| **Exclude window** from capture | n/a | ❌ `NSWindow.sharingType = .none` ignored by ScreenCaptureKit on macOS 15+ | Only blocks legacy `CGWindowListCreateImage`; modern recorders (QuickTime/Zoom/OBS/SCKit) capture the composited framebuffer. |

**Reading:** On **macOS the guard is essentially detect-only** (and even detection is weaker — no screenshot notification, no reliable window exclusion). The meaningful surface is **iOS**. The shared target must therefore degrade gracefully to a no-op on macOS rather than promise protection it can't deliver.

---

## 3. Proposed shared target

### 3.1 Name (candidates — Leader/user to pick)

1. **`CaptureGuardKit`** (package) → product `CaptureGuard` — *recommended.* Names the thing it does (guards against screen capture), parallels `GameCenterKit`/`TelemetryKit` naming, and the product name `CaptureGuard` reads cleanly as the injected protocol.
2. `ScreenIntegrityKit` → `ScreenIntegrity` — emphasises the leaderboard-integrity framing (good if reaction policy (c) is chosen).
3. `CaptureDetectKit` → `CaptureDetect` — most honest about the limit (detect, not block) but undersells the content-hide modifier.

**Recommendation: `CaptureGuardKit` / `CaptureGuard`.**

### 3.2 Location & shape (mirrors `TelemetryKit` / `GameShellKit`)

A new sibling local package at `Packages/CaptureGuardKit/`, single package, multi-target, `.iOS(.v26)` / `.macOS(.v26)`, Swift 6 language mode, the three standard `swiftSettings` upcoming features. Mirrors the existing kit layout:

```
Packages/CaptureGuardKit/
  Package.swift
  Sources/
    CaptureGuard/                 # protocol seam + values + Live/Noop + SwiftUI modifier
      CaptureGuard.swift          # protocol + CaptureState/CaptureEvent value types
      LiveCaptureGuard.swift      # @MainActor, sceneCaptureState + screenshot notification
      NoopCaptureGuard.swift      # macOS default + opt-out; always .notCaptured
      SecureContentHiding.swift   # .hiddenFromCapture() SwiftUI modifier (iOS secure-layer)
    CaptureGuardTesting/          # FakeCaptureGuard (drive states/events in tests)
      FakeCaptureGuard.swift
  Tests/
    CaptureGuardTests/
```

Products: `.library("CaptureGuard")` + `.library("CaptureGuardTesting")` — exactly the `Telemetry` / `TelemetryTesting` split.

**Dependency direction:** `CaptureGuard` depends on **nothing internal** (a leaf module, like `Telemetry` minus the `SudokuCoreKit` dep). Critically it must **NOT** depend on `TelemetryKit`, because `TelemetryEvent` imports `SudokuEngine` (Sudoku-specific) — a cross-app shared target cannot pull a Sudoku type. Telemetry is wired via an **injected callback seam** at composition time (see §3.5), exactly how `AdGate` receives `onPersistenceError` without depending on `Telemetry`.

### 3.3 Public API (the seam)

Sketch (illustrative, not final code):

```swift
public enum CaptureState: Sendable, Equatable {   // observable live state
    case notCaptured
    case captured            // recording / mirroring / AirPlay active
}

public enum CaptureEvent: Sendable, Equatable {    // discrete events
    case screenshotTaken                            // iOS only, post-hoc
    case captureStateChanged(CaptureState)
}

@MainActor
public protocol CaptureGuard: AnyObject {           // @MainActor: reads UIScreen/trait
    var captureState: CaptureState { get }          // current live state
    var events: AsyncStream<CaptureEvent> { get }   // screenshot + state-change stream
    func start()                                     // begin observing
    func stop()
}
```

Plus a SwiftUI content-hiding modifier (separate from the protocol, so it can be applied to the board view without injecting the guard):

```swift
public extension View {
    /// iOS: renders inside a secure-text-entry layer so the content is
    /// black in screenshots/recordings. macOS / unsupported: returns self.
    func hiddenFromCapture(_ active: Bool = true) -> some View
}
```

- `LiveCaptureGuard` (iOS): observes `sceneCaptureState` via `registerForTraitChanges` (iOS 17+; we're on iOS 26 so no fallback branch is strictly required, but `isCaptured` may still be used as a belt-and-suspenders initial read), plus `userDidTakeScreenshotNotification`. `@MainActor`-isolated; `events` is a `Sendable` `AsyncStream`.
- `NoopCaptureGuard`: always `.notCaptured`, empty event stream. **Default on macOS** (the OS can't deliver the signals) and the opt-out impl everywhere.
- `FakeCaptureGuard` (in `CaptureGuardTesting`): lets tests push arbitrary `CaptureEvent`s and assert reactions — per `swift-testing-baseline` protocol-injected fakes.

### 3.4 Content-hiding (`isSecureTextEntry` secure-layer trick) — viability

Verified still functional on real devices as of early 2026, used by banking/authenticator apps; enforced at the **render-server** level so it blanks both screenshots and recordings. **But:** unofficial, relies on traversing private `UITextField` subview/layer names (`UITextLayoutCanvasView`), name has shifted across iOS versions, **fails in Simulator and against a second-camera photo**, and Apple can break it any release. **Proposal: ship it behind the `.hiddenFromCapture()` modifier as an opt-in, defensively coded (graceful no-op if the secure layer can't be found), and never relied upon as the sole defence.** Flag as prerequisite **P4 (Unconfirmed)** — it is not a supported API.

### 3.5 How BOTH apps consume it

Each app wires a `CaptureGuard` in its composition root exactly like every other dependency:

- **Sudoku:** `Packages/SudokuKit/Sources/AppComposition/Live.swift` → construct `LiveCaptureGuard` (iOS) / `NoopCaptureGuard` (macOS via `#if os(iOS)`), inject into `AppComposition` + `LiveRouteFactory` so the active-game route can react. `Preview.swift` wires `FakeCaptureGuard`.
- **Minesweeper:** `Packages/MinesweeperKit/Sources/MinesweeperAppComposition/Live.swift` → identical pattern; `.preview()` wires `FakeCaptureGuard`.

**Telemetry emission (the seam, not a dependency):** `LiveCaptureGuard` takes an injected `onDetection: @Sendable (CaptureEvent) -> Void` closure (or the host subscribes to `events`). At composition each app maps the event into *its own* telemetry channel — e.g. Sudoku routes through the existing `Telemetry.observe(.errorOccurred(source: "CaptureGuard", code: "screenshot_taken", ...))` funnel (the same shape `AdGate`/IAP desync already use). This keeps `CaptureGuardKit` free of `SudokuEngine` and honours `telemetry-facade-pattern` (caller says "what happened", facade fans out) without coupling the shared target to either app's event enum. Logging inside `LiveCaptureGuard` itself uses `os.Logger` per `oslog-logger-defaults` (subsystem = bundle id, category = `CaptureGuard`).

> **Backlog note:** if a *cross-app* shared telemetry vocabulary is wanted later, the clean fix is to extract a game-agnostic `TelemetryEvent` base out of `TelemetryKit` (it currently imports `SudokuEngine`). Out of scope here; routes to `docs/foundations.md §Backlog` per `backlog-routing-by-topic`.

---

## 4. Reaction policy (FORK — Leader/user choose; recommendation below)

The detection primitives are fixed; the *reaction* is a product decision. Options (combinable):

| Opt | Reaction | Pros | Cons |
|-----|----------|------|------|
| **(a)** | **Detect-only + telemetry.** Log screenshot / capture-start events; change nothing visible. | Zero UX harm; gives data on how real the problem is before investing; trivially shippable; no false-positive blast radius. | Doesn't deter anyone; purely observational. |
| **(b)** | **Blur/pause overlay while `captured`.** When `sceneCaptureState == .active`, dim the board + show "Recording detected — paused". | Strong deterrent vs T2; reversible; honest UX. | **False positives**: AirPlay to a TV, assistive screen mirroring, legit recording for a bug report → punishes innocents. Annoying. |
| **(c)** | **Mark the run "unranked".** On a screenshot/capture during an *active ranked* run (Daily / leaderboard), flag the run so it doesn't post to Game Center / counts as practice. | Targets the actual integrity surface (leaderboard) without blocking play; proportionate; doesn't interrupt casual screenshots. | Needs a run-state hook in each app; must message clearly or feels like a silent penalty; can still be gamed by a second camera. |
| **(d)** | **Secure-layer content-hide on the board** (`.hiddenFromCapture()`). Board renders black in captures. | Directly defeats T1 OCR for screenshots *and* recordings; no interruption to the player. | Unofficial/fragile (§3.4); blanks the board in *legit* screenshots too (sharing a cool puzzle, support tickets); Simulator/second-camera bypass. |

**Recommendation: ship (a) now, design the seam so (c) can follow.**

- **(a) detect-only + telemetry** is the only option with zero false-positive/UX/review downside, and we currently have **no data** on whether cheating via capture is a real problem for these two casual puzzle games. Measure first.
- Build the protocol/event seam so **(c) unranked** can be layered on for Daily/leaderboard runs once data justifies it — it's the most *proportionate* deterrent (protects integrity, doesn't punish casual screenshots) and aligns with the `ScreenIntegrityKit` framing.
- Treat **(b)** and **(d)** as opt-in, behind-a-flag escalations only if abuse is observed. Both carry real false-positive / review risk for a puzzle game where there's little incentive to cheat (no money, casual leaderboards).

This staging matches the project's Karpathy "simplicity first / nothing speculative" posture: don't build blur overlays and private-layer hacks for a threat we haven't measured.

---

## 5. UX / privacy / App-Store-review considerations

- **Legitimate capture is common and protected.** Users record screens for accessibility (assistive tech, screen readers narrating), bug reports, tutorials, sharing achievements. A hostile guard (b/d) degrades these and reads as user-hostile.
- **False positives** for recording detection: `sceneCaptureState` / `isCaptured` cannot distinguish recording from **AirPlay**, **mirroring to a Mac/TV**, or **assistive mirroring**. Any reaction keyed on "captured" will fire for all of these. This alone argues against aggressive reactions (b).
- **App Review:** detection + telemetry (a) and unranked-marking (c) are benign. The `isSecureTextEntry` content-hide (d) uses **private view-hierarchy traversal** — not a documented API; low but non-zero rejection risk and breakage risk every iOS update. If shipped, isolate it so it can be disabled remotely/at build time without a UI rewrite.
- **Privacy manifest:** screenshot/capture *detection* reads no personal data and adds no `PrivacyInfo.xcprivacy` API-reason entries by itself; confirm during RFC (prerequisite-adjacent, low risk).
- **Proportionality:** these are casual puzzle games with non-monetised leaderboards. The incentive to cheat is low; the cost of annoying honest players is immediate. Bias toward the lightest-touch option.

---

## 6. Prerequisite checklist (collaboration-mode rule — every system-API dependency)

| ID | Dependency | Status | Evidence |
|----|-----------|--------|----------|
| P1 | `UIApplication.userDidTakeScreenshotNotification` (post-hoc screenshot detection, iOS) | **Verified ✓** | Apple UIKit docs; widely documented, available since iOS 7. Fires after the shot; no block. |
| P2 | `UITraitCollection.sceneCaptureState` + `registerForTraitChanges` (live capture detection, iOS 17+) | **Verified ✓** | Apple docs `uitraitcollection/scenecapturestate`; WWDC23 "Unleash the UIKit trait system." Project min is **iOS 26**, so well within range. |
| P3 | `UIScreen.isCaptured` / `capturedDidChangeNotification` (legacy fallback) | **Verified ✓ (legacy)** | Apple docs; legacy/soft-deprecated in favour of P2. Optional belt-and-suspenders only; **not required** given iOS 26 floor. |
| P4 | `UITextField.isSecureTextEntry` secure-layer content-hiding trick | **Unconfirmed ?** | Works on real devices as of early-2026 community reports (banking/authenticator apps), enforced at render-server level. **But it is NOT a public API** — relies on private subview/layer names (`UITextLayoutCanvasView`), Simulator-bypassable, breakable any iOS release. **This item blocks approval of reaction policy (d) only.** If (d) is deferred (recommended), P4 is not on the critical path. |
| P5 | `NSWindow.sharingType = .none` (macOS window exclusion) | **Verified ✓ — NEGATIVE** | Apple now documents `.none` as "a legacy constant that macOS no longer uses"; Apple forum (Jul 2025): "no public APIs for preventing screen capture." Ignored by ScreenCaptureKit on macOS 15+. **Conclusion: do not build on this; macOS path is detect-only/no-op.** |
| P6 | Min-OS availability vs project targets | **Verified ✓** | `TelemetryKit`/`GameShellKit` `Package.swift` declare `.iOS(.v26)` / `.macOS(.v26)`. All iOS APIs above are ≤ iOS 17, fully available. (Note: this *exceeds* the task brief's stated iOS 18/macOS 15 assumption — the repo floor is higher, so no back-deployment branches are needed.) |
| P7 | Swift 6 concurrency: `LiveCaptureGuard` reads `UIScreen`/traits → must be `@MainActor`; `CaptureEvent`/`CaptureState` `Sendable`; event delivery via `AsyncStream` | **Verified ✓** | Matches existing `swift6-concurrency` posture across all kits (StrictConcurrency upcoming feature, `.v6` language mode). UIKit capture APIs are main-actor; design already isolates them. |

**Approval gate:** All items required for the **recommended scope (a)+(c)** are **Verified ✓**. The only **Unconfirmed ?** item is **P4**, which gates **only reaction policy (d)** (secure-layer content-hide). If the user defers (d) — the recommendation — there is **no blocking prerequisite**. If the user wants (d) in v1, P4 must be resolved first (spike: confirm the secure-layer trick on the current iOS device toolchain + decide acceptable-fragility), which blocks approval of that sub-scope.

---

## 7. Open questions for Leader / user

1. **Is capture-cheating an observed problem, or anticipated?** Drives whether we ship (a) detect-only and measure, or jump to active reactions.
2. **Which reaction policy?** Recommendation: (a) now + seam for (c). Confirm, or request (b)/(d) escalation.
3. **Does "unranked" (c) have a home?** It needs a per-run ranked-state hook in each app's active-game flow + Game Center submit path. Is that acceptable scope, or leaderboard-integrity out of scope for v1?
4. **macOS expectation?** Given P5, the macOS build is detect-only (screenshot notification doesn't even exist on macOS) → effectively no-op. Acceptable to ship iOS-only protection and no-op macOS?
5. **Accept the P4 fragility for (d)?** Only relevant if (d) is wanted. Private-layer trick = ongoing maintenance + review risk.
6. **Target name:** `CaptureGuardKit` (recommended) vs `ScreenIntegrityKit` vs `CaptureDetectKit`.

---

## 8. Status note

This is a **proposal** (`PROPOSAL_DRAFT`). No production Swift written; no git run. On Leader approval of the proposal dimensions, next step is an **RFC** (finalised API + package manifest + per-app wiring diff plan + test plan), then decomposition into issues. Per project rule, no implementation code lands before the design is approved.
