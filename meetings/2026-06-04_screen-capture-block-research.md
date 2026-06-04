# RESEARCH — Black-on-Capture Content Hiding (firming up #286 prerequisite P4)

- **Date:** 2026-06-04
- **State:** Research note (Researcher → Leader). READ-ONLY on repo; web research only. No code, no git.
- **Feeds:** `meetings/2026-06-03_anti-capture-cheat-guard-proposal.md` (#286), reaction policy **(d)** + prerequisite **P4 (Unconfirmed)**.
- **Question:** Is the Netflix-style "board goes black in screenshots/recordings" trick viable enough in 2026 to ship behind a flag for the game board? If so, how do we verify it on a real device, and what does the eventual SwiftUI modifier look like?

---

## 0. Headline verdict (read first)

> **The trick still works on current iOS (confirmed through early–mid 2026 sources, including a library testing matrix that lists iOS 26.2 / Xcode 26.3).** It is the `UITextField.isSecureTextEntry` secure-layer trick: reparent the board's layer into a secure text field's internal render layer so the render-server blanks it (black) in screenshots **and** recordings, while the user still sees it live.
>
> **It remains unofficial, render-server-private, and fragile.** It is NOT a public API; it relies on the `disableUpdateMask` private layer attribute (located by matching the private container class name `_UITextLayoutCanvasView`). It **does not work in Simulator or UI tests**, is **defeated by a second-camera photo** (T4, already out of scope), and was observed **unreliable during the iOS 17 beta** and **~50% reliable on at least one iOS 18 build** by one reverse-engineer who then switched to the Telegram-derived layer-mask path.
>
> **Recommendation for P4:** Mark **P4 = Resolved-conditional / "viable behind a flag"** *after* the device spike below passes. The technique is good enough to ship as an **opt-in, defensively-coded, gracefully-no-op `.hiddenFromCapture()` modifier** that is never the sole defence — exactly the §3.4 framing. Do **not** promote it to a hard guarantee, and keep the build/remote kill-switch the proposal already calls for. **Netflix is NOT a precedent** for arbitrary UI (see §2.3 — Netflix uses FairPlay/HDCP protected media surfaces, not this trick).

---

## 1. The `isSecureTextEntry` secure-layer trick — current state (2026)

### 1.1 Mechanism (why it blanks both screenshots and recordings)

It is **not** event-based. When a `UITextField` has `isSecureTextEntry = true`, UIKit stamps the field's *internal content layer* with a private attribute (`disableUpdateMask`, observed flag value `0x12` by one reverse-engineer). That attribute is handed to the **render server (backboardd / the compositor)**, which decides per-frame whether to draw that layer into the **capture buffer**. The on-screen (live) display still draws it; the capture surface does not. Because enforcement is at the render-server / framebuffer level:

- It blanks **screenshots, screen recordings, AirPlay/QuickTime mirroring, and app-switcher snapshots** uniformly.
- It is **robust even if the app's main thread hangs or is backgrounded** — the render server already holds the mask.
- The mask **does not affect layout** — it behaves like the alpha modifier for layout purposes; it is purely a draw/no-draw decision on the capture path.

The community pattern: create a hidden secure `UITextField`, find its internal canvas subview by **string-matching the private class name**, then **reparent your real content's layer** into that secure subview's layer. ("Putting your view inside the password field.")

### 1.2 The private container name (and whether it has shifted)

The trick depends on locating one private subview by its class-name string. Per the widely-copied `HiddenContainerRecognizer`:

| iOS version | Private container class name |
|---|---|
| iOS 15 – 26 (current) | `_UITextLayoutCanvasView` |
| iOS 13 – 14 | `_UITextFieldCanvasView` |
| iOS 12 | `_UITextFieldContentView` |

**For this project the relevant name is `_UITextLayoutCanvasView`** (repo floor is iOS 26; the name has been stable since iOS 15 — no shift across 15→26). The defensive code must filter `textField.subviews` for the one whose `type(of:)` description matches that string; if no match, **no-op gracefully** (the spike must verify the name on the exact shipping iOS build).

### 1.3 Wrapper libraries that implement it

| Library | Shape / API | Notes |
|---|---|---|
| **Kyle-Ye/ScreenShieldKit** (open source) | `view.hiddenFromCapture(true/false)` (UIKit) and `.hiddenFromCapture()` (SwiftUI) | **Closest match to the proposal's chosen modifier name.** Targets **iOS 18+**, testing matrix lists **iOS 18.5 / Xcode 16.4 and iOS 26.2 / Xcode 26.3**. Describes itself as using "the same private layer update-mask path as UIKit." |
| **daangn/ScreenShieldKit** | secure-content API, iOS + macOS | **Explicitly warns it uses private APIs that may not be App-Store-approved** and may break on future OS. Honest about the risk. |
| **JayantBadlani/ScreenShield** | `.protectScreenshot()` + `protectFromScreenRecording()` | SwiftUI + UIKit, secure-layer-on-top approach. |
| **ckdash-git/ScreenShield** | drop-in SwiftUI/UIKit, toggle + optional blur | "Injects your views into this secure layer hierarchy… tricking the OS into treating your UI as a password field." Zero deps. |
| **ScreenShieldKit.com** (commercial, paid) | `SSKProtectedImageView` / `SSKProtectedLabel` components | Patent-pending, <1MB, also covers app-switcher snapshot. Requires using *their* components — poor fit for an arbitrary game board. |
| **Telegram** (reference impl) | `setLayerDisableScreenshots` in `UIKitUtils.m` | The canonical "buff any layer" implementation that several devs trust **over** the raw `0x12`-flag approach for reliability. |

**Takeaway:** the proposal's own `.hiddenFromCapture()` modifier name is already industry-aligned (Kyle-Ye uses the identical signature). We can implement our own ~40-line version rather than take a dependency, OR vendor/reference Kyle-Ye's (MIT-ish OSS) — decision for RFC. Avoid the paid SDK (board is arbitrary, not their components) and avoid daangn's by-its-own-admission-private-API package as a runtime dependency.

### 1.4 App Store review track record

- **No public API call is made** — `isSecureTextEntry` is public; the gray area is *string-matching a private view-hierarchy class name* to find the canvas subview. Multiple sources state the basic secure-overlay form "uses only public APIs and is common in approved banking/fintech apps," which is the empirical evidence that it generally passes review.
- An **Apple Developer Forums thread (#792624)** records a developer asking Apple point-blank whether this exact technique (embedding content in the secure container, matching class names via strings, *not* calling private APIs) is App-Store-safe. **Apple gave no definitive yes/no in-thread** — it remained an open question. So: **widely shipped and apparently tolerated, but never officially blessed.**
- **Mitigation already in the proposal:** isolate it behind `.hiddenFromCapture()` so it can be disabled at build-time / remotely without a UI rewrite (§3.4 / §5). Keep that. Rejection risk is **low but non-zero**; breakage risk per-iOS-release is the larger practical concern.

### 1.5 Failure modes (must be designed around)

| Failure mode | Status | Design response |
|---|---|---|
| **Simulator** | Does **not** work — render-server mask is device-only. | Spike + any verification must be on a **physical device**. `.hiddenFromCapture()` must no-op cleanly in Sim so previews/UITests don't crash. |
| **XCUITest / UI tests** | Do **not** work (same reason). | Don't assert black-out in UITests; unit-test only the no-op/graceful-fallback path. |
| **Second-camera / external photo (T4)** | **Not mitigable.** Already out of scope in #286. | State explicitly; do not market as unbreakable. |
| **iOS beta instability** | Observed broken in **iOS 17 beta**; one dev saw **~50% reliability on an iOS 18 build** using the raw `0x12` flag, switched to Telegram's `setLayerDisableScreenshots` path which was reliable. | Prefer the **Telegram/Kyle-Ye layer-mask path** over the raw flag. **Re-test every iOS major** — this is permanent maintenance cost. |
| **Private class-name shift** | Stable `_UITextLayoutCanvasView` since iOS 15, but could change any release. | Defensive lookup + graceful no-op (board stays visible in captures rather than crashing) + telemetry signal when the layer can't be found. |

---

## 2. Newer / official APIs since iOS 17/18/26

### 2.1 Detection, not blocking (unchanged conclusion)

Apple has added **no public *blocking* API**. The capture-related APIs are all **detection**:

- **`UITraitCollection.sceneCaptureState` + `registerForTraitChanges` / `observeSceneCaptureStateChange`** (iOS 17+) — preferred live-capture detection. (P2, already Verified ✓.)
- **`UIScreen.isCaptured` + `capturedDidChangeNotification`** (iOS 11+) — legacy; **deprecation-direction on iOS 18+** in favour of `sceneCaptureState`. (P3, Verified ✓ legacy.)
- **`UIApplication.userDidTakeScreenshotNotification`** — post-hoc only, fires *after* the shot. (P1, Verified ✓.)
- **iOS 26 caveat worth recording:** a developer testing on iPhone 16 Pro / **iOS 26.2** reported (Apple Forums #817446) that **both `isCaptured` and `sceneCaptureState` reflect whether the current *scene* is part of the capture surface, not whether device-level recording is active** — and can flip when a system surface (e.g. expanded Live Activity) is promoted above the app scene. **Open question with Apple; no supported way to read true device-level recording state.** This is a **false-positive source for reaction policy (b)**, reinforcing #286's "measure first / detect-only" stance. (Doesn't change (d); (d) is render-server blanking, independent of these detection APIs.)

### 2.2 `ScreenCaptureKit` exclusion on iOS

`ScreenCaptureKit` is a **capture *producer*** framework (you use it to *grab* the screen), and it is **macOS-centric**. It is **not** an iOS content-*exclusion* API. There is no iOS "exclude my view from SCKit" path. Confirmed: still no public iOS exclusion API.

### 2.3 DRM / `AVPlayer` protected surface (the actual "Netflix mechanism")

Confirmed **media-only, N/A to arbitrary UI.** Netflix-style black-on-capture comes from **FairPlay Streaming + a hardware-protected video surface (HDCP-style)** — the protection lives in the *media pipeline / protected `AVPlayerLayer` surface*, not a general view flag. You **cannot** wrap a SwiftUI game board in it. So the only game-applicable technique is the secure-text-field trick from §1. **The user's "Netflix-style" reference is achievable in *effect* (board goes black) but via a different, unofficial mechanism with the fragility caveats above — set expectations accordingly.**

### 2.4 SwiftUI `SecureField` level

`SecureField` is the SwiftUI wrapper over a secure `UITextField`, but it gives you a *password input*, not a way to host arbitrary content in its secure layer. There is **no SwiftUI-public modifier** to mark a view "secure / excluded from capture." Any SwiftUI solution must drop to `UIViewRepresentable` and reach into the secure `UITextField`'s private canvas layer (§4). No official SwiftUI route as of iOS 26.

---

## 3. macOS — confirm `NSWindow.sharingType = .none` is dead

**Confirmed dead vs ScreenCaptureKit on macOS 15+.** Apple's current documentation describes **`NSWindow.SharingType.none` as "a legacy constant that macOS no longer uses."** Mechanism: on modern macOS the Quartz compositor merges **all** windows into a single framebuffer *before* display, and ScreenCaptureKit (and QuickTime/Zoom/OBS) capture that composited framebuffer — so per-window `sharingType` is ignored. `.none` only ever affected **legacy** window-capture APIs (`CGWindowListCreateImage`), which modern recorders don't use.

Apple's official position (Developer Forums, 2025): *"At this time there are no public APIs for preventing screen capture. If you'd like us to consider adding APIs… file an enhancement request via Feedback Assistant."* Corroborated by `tauri-apps/tauri` issue #14200 (macOS 15+ ScreenCaptureKit ignores `setContentProtection` / `NSWindow.sharingType`) and Apple Forums #792152 (macOS 15.4+).

**Conclusion (matches #286 P5):** the macOS path is **detect-only / no-op**. Do not build content-hiding on macOS. `.hiddenFromCapture()` returns `self` unchanged on macOS. (And macOS has no `userDidTakeScreenshotNotification` either, so even detection is weaker.)

---

## 4. SwiftUI integration — wrapping the board in the secure layer

### 4.1 The known pattern

There is no pure-SwiftUI path. The established approach:

1. A `UIViewRepresentable` hosts a normal (hidden-secure) `UITextField` with `isSecureTextEntry = true`.
2. Find the field's private secure canvas subview by matching `type(of: subview)` description == `"_UITextLayoutCanvasView"`.
3. Host the SwiftUI board (via a `UIHostingController`'s view, or a `UIView` container) **inside that secure subview** (add as subview + pin constraints), so its layer is under the secure layer.
4. Because the mask doesn't affect layout, the hosted content lays out and receives touches normally; only the *capture draw* is suppressed.

This is exactly what Kyle-Ye/ScreenShieldKit's `.hiddenFromCapture()` and ckdash/ScreenShield do under the hood.

### 4.2 Defensive, graceful no-op design (required)

The single most important production property: **if the private canvas can't be found (name shifted, Simulator, future iOS break), the modifier must degrade to showing the content normally — never crash, never hide the board from the *user*.** Concretely:

- Guard every step (`subviews.first(where:)` returns optional → if nil, just render content plainly).
- No-op entirely under `#if targetEnvironment(simulator)` and on `#if os(macOS)`.
- Emit a telemetry/`os.Logger` signal (`secure_layer_unavailable`) when the lookup fails, so we learn the day an iOS release breaks it — feeding the same detect-only telemetry funnel #286 already defines.
- Keep an **`active` flag** so it can be toggled off at build-time / remotely without a UI rewrite (the §5 review-risk mitigation).

### 4.3 Recommended `.hiddenFromCapture()` sketch (illustrative — NOT production code)

```swift
import SwiftUI

public extension View {
    /// iOS device only: render `self` inside a secure UITextField layer so it
    /// is blanked (black) in screenshots / recordings while staying visible live.
    /// Simulator, macOS, or if the private secure layer can't be found → no-op
    /// (content renders normally; never hides the board from the actual user).
    func hiddenFromCapture(_ active: Bool = true) -> some View {
        #if os(iOS)
        modifier(SecureCaptureHide(active: active))
        #else
        self // macOS: ScreenCaptureKit captures composited framebuffer; nothing to do.
        #endif
    }
}

#if os(iOS)
import UIKit

private struct SecureCaptureHide<Hosted: View>: ViewModifier { /* see body below */ }

private struct SecureCaptureHide: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        // In Simulator the render-server mask is unavailable: skip the wrapper
        // entirely so previews/UITests behave normally.
        #if targetEnvironment(simulator)
        content
        #else
        if active {
            SecureContainer { content }   // UIViewRepresentable host (below)
        } else {
            content
        }
        #endif
    }
}

/// Hosts `Content` inside the secure canvas of an isSecureTextEntry UITextField.
private struct SecureContainer<Content: View>: UIViewRepresentable {
    @ViewBuilder let content: () -> Content

    func makeUIView(context: Context) -> UIView {
        let host = UIHostingController(rootView: content())
        host.view.backgroundColor = .clear

        let field = UITextField()
        field.isSecureTextEntry = true
        field.isUserInteractionEnabled = false   // we only want its secure layer

        // Private secure canvas; name stable as `_UITextLayoutCanvasView` (iOS 15–26).
        // Defensive: if not found, fall back to plain hosting (visible in captures,
        // but never hidden from the user) and signal telemetry.
        let secureCanvasName = "_UITextLayoutCanvasView"
        guard let canvas = field.subviews.first(where: {
            String(describing: type(of: $0)) == secureCanvasName
        }) else {
            Logger.captureGuard.error("secure_layer_unavailable: \(secureCanvasName, privacy: .public) not found")
            return host.view   // graceful no-op: content still visible to user
        }

        host.view.translatesAutoresizingMaskIntoConstraints = false
        canvas.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: canvas.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: canvas.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: canvas.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: canvas.bottomAnchor),
        ])
        return field   // the secure field is the returned root; render server blanks it on capture
    }

    func updateUIView(_ uiView: UIView, context: Context) { /* re-host on content change */ }
}
#endif
```

> Sketch only — names/lifecycle (`UIHostingController` retention, `updateUIView` re-hosting, dynamic-island/layout edge cases) must be hardened during RFC/impl. The load-bearing points are: **(1) device-only, (2) private name `_UITextLayoutCanvasView` looked up defensively, (3) graceful no-op + telemetry on failure, (4) macOS/Sim short-circuit.**

---

## 5. Updated verdict on P4

**P4: viable enough to ship behind a flag — conditional on the device spike passing.**

- ✅ Mechanism is real, render-server-enforced, blanks screenshots + recordings + mirroring, doesn't disturb layout/touch, and is confirmed working on **iOS 26.2** by an actively-maintained library's test matrix.
- ✅ The proposal's `.hiddenFromCapture()` name/shape matches industry (Kyle-Ye) — low design risk.
- ⚠️ **Fragility is the gating concern, not feasibility.** Private path, per-iOS-release breakage history (17 beta, one 18 build), Simulator-incapable, second-camera-bypassable, no Apple blessing. These are *acceptable* for an **opt-in, kill-switchable, never-sole-defence** modifier — **unacceptable** as a hard anti-cheat guarantee.
- 🚩 **Single biggest risk: silent breakage on a future iOS update** (private class-name shift or render-server behavior change) blanking nothing — or, worse without the defensive guard, hiding the board from the *user*. Mitigated by the graceful-no-op + telemetry-on-failure design and the build/remote kill-switch.

**Recommended status change:** `P4: Unconfirmed ?` → **`P4: Resolved-conditional ✓ (viable behind a flag; re-verify each iOS major)`** once the §6 spike checklist passes on a current physical device. This unblocks reaction policy **(d)** as an *opt-in escalation* only — it does **not** change the proposal's primary recommendation (ship **(a)** detect-only first, seam for **(c)**; **(d)** behind a flag if/when abuse is observed).

---

## 6. Device-spike test plan (checklist — run on a REAL device)

**Goal:** prove the secure-layer trick blanks the board in screenshots + recordings on the current shipping iOS, find the private layer reliably, and confirm the known bypass/no-op boundaries. ~30–45 min.

**Pre-reqs**
- [ ] A **physical iPhone** (NOT Simulator) on the current shipping iOS — record exact version (e.g. iOS 26.x) and device model in the result table.
- [ ] A throwaway Xcode project or a scratch target — single screen with a recognizable, OCR-able grid (mimic the Sudoku board: numbers in a 9×9 grid).
- [ ] Wrap that grid view in a minimal `.hiddenFromCapture()` per the §4.3 sketch.

**A. Private-layer presence**
- [ ] At runtime, log `field.subviews.map { String(describing: type(of: $0)) }`.
- [ ] Confirm one entry == `_UITextLayoutCanvasView`. **Record the actual string** (verify it hasn't shifted on this iOS build).
- [ ] Confirm the graceful path: temporarily mis-spell the name → app does NOT crash and the grid stays **visible to the user**.

**B. Screenshot blanking**
- [ ] Display the wrapped grid. Take a **hardware screenshot** (Side+VolUp).
- [ ] Open the screenshot in Photos → board area is **black/blank**; rest of UI (non-wrapped chrome) is visible. → PASS.
- [ ] Take a screenshot from the **app switcher** snapshot (background the app, screenshot the card if reachable) → note whether blanked.

**C. Screen-recording blanking**
- [ ] Start the **built-in Screen Recording** (Control Center). Display the wrapped grid ~10s. Stop.
- [ ] Scrub the recording → board area is **black** throughout; live on-device it was fully visible. → PASS.

**D. Mirroring (optional but informative)**
- [ ] **AirPlay / QuickTime (Mac, Lightning/USB-C) mirror** the device → confirm board blanks on the mirror too (render-server path should cover it).

**E. Known-bypass confirmation (expected to FAIL — documents the boundary)**
- [ ] **Second-camera:** photograph the device screen with another phone → board is **visible** (expected; T4 out of scope). Record as "bypass confirmed, by design."
- [ ] **Simulator:** run the same build in Simulator, screenshot → board is **visible** (expected; Sim no-op). Confirms the `#if targetEnvironment(simulator)` short-circuit is correct.

**F. Live UX sanity**
- [ ] On-device, the user **sees the board normally**; taps/interaction work (mask doesn't affect layout/hit-testing).
- [ ] No console errors; `secure_layer_unavailable` telemetry NOT emitted on the happy path.

**Result table to fill in**

| iOS version | Device | Screenshot blank? | Recording blank? | AirPlay blank? | Layer name found | 2nd-camera (expect visible) | Sim (expect visible) |
|---|---|---|---|---|---|---|---|
| | | | | | | | |

**Spike passes if:** B + C are PASS, A finds `_UITextLayoutCanvasView`, the mis-spell test no-ops gracefully, and E behaves as expected (bypasses confirmed by design). → flip **P4 to Resolved-conditional** and record the tested iOS version as the "last verified" baseline (re-run each iOS major).

---

## 7. Sources (with dates where available)

- Apple Developer Forums #792624 — *Clarification on Using Secure UITextField to Prevent Screenshots* (App-Store-safety question; no definitive Apple answer). https://developer.apple.com/forums/thread/792624
- Apple Developer Forums #817446 — *UIScreen.isCaptured and sceneCaptureState* (iOS 26.2 scene-vs-device-level capture finding). https://developer.apple.com/forums/thread/817446
- Apple Developer Forums #736112 — *prevent/disable screenshots on iOS 17 beta* (isSecureTextEntry unstable in iOS 17 beta). https://developer.apple.com/forums/thread/736112
- Apple Developer Forums #792152 — *macOS 15.4+ NSWindow content protection ignored by ScreenCaptureKit*. https://developer.apple.com/forums/thread/792152
- Apple docs — *NSWindow.SharingType.none* ("a legacy constant that macOS no longer uses"). https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum/none
- Apple docs — *ScreenCaptureKit* (capture producer; macOS-centric). https://developer.apple.com/documentation/screencapturekit/
- Kyle-Ye/ScreenShieldKit — `hiddenFromCapture(_:)` API; tested iOS 18.5/Xcode 16.4 + iOS 26.2/Xcode 26.3. https://github.com/Kyle-Ye/ScreenShieldKit
- daangn/ScreenShieldKit — secure-content API; self-declared "uses private APIs, may not be App-Store-approved." https://github.com/daangn/ScreenShieldKit
- JayantBadlani/ScreenShield — `.protectScreenshot()` secure-layer-on-top. https://github.com/JayantBadlani/ScreenShield
- ckdash-git/ScreenShield — "injects views into secure layer hierarchy"; SwiftUI+UIKit, zero deps. https://github.com/ckdash-git/ScreenShield
- kei_sidorov (sidorov.tech) — reverse-engineering `disableUpdateMask` → render server; Telegram `setLayerDisableScreenshots`; "only works on real device, not Simulator/UITests." https://sidorov.tech/en/all/mastering-screen-recording-detection-in-ios-apps/
- swiftandcurious.com (2026-03-01) — *Protecting Your UI — Prevent Screenshots in SwiftUI* (technique still valid; secure layer excludes from screenshots + recordings). https://swiftandcurious.com/2026/03/01/protecting-your-ui-prevent-screenshots-in-swiftui/
- Anubhav Sharma, Medium (Dec 2025) — *Preventing Screenshots in SwiftUI: The Practical Solution That Actually Worked* (undocumented but stable, widely used in enterprise). https://khush7068.medium.com/preventing-screenshots-in-swiftui-ios-the-practical-solution-that-actually-worked-1140c04e226d
- expo/expo PR #37874 — iOS secure-text-field screenshot prevention; black-result test on iPhone 16 Pro sim, Jul 2025. https://github.com/expo/expo/pull/37874
- tauri-apps/tauri #14200 — macOS 15+ ScreenCaptureKit ignores setContentProtection / NSWindow.sharingType. https://github.com/tauri-apps/tauri/issues/14200
- Daring Fireball (2018) — ScreenShield third-party SDK background (media/DRM vs UI distinction). https://daringfireball.net/2018/01/screenshield
