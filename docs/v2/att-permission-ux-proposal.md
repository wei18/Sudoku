# ATT Permission UX — Design + Copy Proposal

**Issue:** #195 — Permission request UX (ATT tracking) — design + copy [rescoped: ATT-only]
**Status:** PROPOSAL (product decision required before any implementation)
**Date:** 2026-06-05
**Author:** Developer/Designer subagent → Leader review → User decision

> This is a **decision document**, not an implementation. No Info.plist, app code,
> or localization catalog is touched. The central question — *does Sudoku show an
> ATT prompt at all?* — is a product/legal call only the user can make. This doc
> frames that call, supplies the copy for whichever path is chosen, and lists the
> open questions.

---

## 1. TL;DR / Recommendation

**The app today is built to request ATT and to serve personalized ads on consent.**
This is **Path B** below, and it is wired end-to-end already: `ATTPresenter`, the
`UMP → ATT → AdMob` boot coordinator, the `NSUserTrackingUsageDescription` string,
and a `PrivacyInfo.xcprivacy` that declares `NSPrivacyTracking = true`. So "no ATT
needed" (Path A) is **not** the cheap default here — it would mean *removing*
shipped infrastructure and downgrading the privacy manifest, a deliberate
product/revenue choice, not a code-tidiness one.

**Recommended path: keep Path B (ATT request stays), but fix two real defects the
current implementation has:**

1. **Timing defect** — the prompt fires from the root scene's `.task` (cold launch),
   directly contradicting the project's own design.md §How.4: *"ATT prompt 必須在 App
   啟動完成、且使用者已經至少看過 Home view（不要 cold-launch prompt）."* Apple HIG and
   measured accept-rates both favor a deferred prompt with a priming pre-screen.
2. **Copy + localization defect** — the `NSUserTrackingUsageDescription` is an
   English-only literal in `Sudoku/Info.plist`; it is **not** in any string catalog
   (`InfoPlist.xcstrings` does not exist in the repo). Issue #195 requires 7-locale
   localization. There is also no priming pre-prompt screen at all today.

The single open question for the user is in §7. Everything else is implementation
follow-up once the path is confirmed.

---

## 2. What ATT actually gates (so the decision is grounded)

ATT (App Tracking Transparency) is required **only** if the app accesses the IDFA
or otherwise tracks the user across apps/websites owned by other companies. For an
AdMob-monetized app that reduces to one question:

- **Personalized ads** → AdMob wants the IDFA / cross-app signals → **ATT prompt required.**
- **Non-personalized ads only (NPA)** → no cross-app identifier used → **no ATT prompt, and the app must not declare tracking.**

ATT is **independent of GDPR/UMP**. Google's UMP (User Messaging Platform) consent
form is a *separate* legal requirement for EEA/UK/Swiss/California users and is
needed **even on Path A** (non-personalized). Dropping ATT does **not** drop UMP.

---

## 3. What the code does TODAY (evidence)

| Artifact | File | What it shows |
|---|---|---|
| ATT prompt wrapper exists | `Packages/AppMonetizationKit/Sources/AdsAdMob/ATTPresenter.swift` | Wraps `ATTrackingManager.requestTrackingAuthorization()`; outcome enum comment: *"User has denied tracking. AdMob will use non-personalized ads."* |
| Boot fires UMP→ATT→AdMob | `Packages/AppMonetizationKit/Sources/AdsAdMob/MonetizationBootCoordinator.swift` (lines 48–67, 114–123) | `.live` wiring calls `UMPConsentPresenter` then `ATTPresenter.requestIfNeeded()` then `adProvider.initialize()`, strictly in order. |
| Boot triggered at cold launch | `Packages/SudokuKit/Sources/AppComposition/AppComposition.swift` (lines 91–97, 139–178) | Root scene `.task { await bootMonetization() }` → `MonetizationBootCoordinator.boot()`. **No "user has seen Home" gate, no priming screen.** |
| ATT purpose string (Path B copy live) | `Sudoku/Info.plist` lines 68–69 | `"Sudoku uses this identifier to show ads relevant to your interests. You can decline and ads still work — just less tailored."` English-only literal. |
| Privacy manifest declares tracking | `Packages/SudokuKit/Tests/AppCompositionTests/Resources/PrivacyInfo.xcprivacy` | `NSPrivacyTracking = true`; AdMob tracking domains; `OtherUsageData` used **for tracking**, purpose **Third-party advertising**. |
| Marketing/policy already promises this flow | `docs/privacy-policy.md` lines 73–74; `docs/app-store/review/sudoku-v2.5.md` lines 56–61; `docs/v2/design.md` §How.4 lines 195–199 | *"After UMP … requests tracking permission via ATT. If you decline, ads are still shown but non-personalized."* |

### Does AdMob explicitly force NPA in the ad request?

**No explicit NPA flag is set in code.** `LiveAdMobBridge.loadBanner()`
(`Packages/AppMonetizationKit/Sources/AdsAdMob/LiveAdMobBridge.swift` lines 122–125)
loads with a bare `Request()` — no `extras["npa"] = "1"`, no
`requestConfiguration` tag for non-personalized. Personalization is therefore left
to **AdMob's own default behavior**, which keys off the ATT authorization status
plus the UMP/TCF consent string. Net: **on consent the app serves personalized
ads; on denial AdMob's SDK auto-falls-back to non-personalized.** This is exactly
the Path B model — the app is *not* configured as NPA-only.

> `[UNVERIFIED — Leader confirm]` The claim "AdMob auto-falls-back to
> non-personalized on ATT denial / no-consent" is Google's documented SDK
> behavior, but it is **not** enforced by an explicit flag in our code. If the
> user wants a *guaranteed* NPA fallback (belt-and-braces), that requires a code
> change (set `npa=1` extras when ATT ≠ authorized) — out of scope for this doc
> but worth an issue. Cited as design.md §How.4 line 196: *"AdMob 自動處理 fallback."*

---

## 4. Path A — Drop ATT, serve non-personalized ads only

### What it means
- **Remove** the ATT request from the boot sequence (UMP → AdMob only).
- **Force NPA** explicitly on every ad request (`npa=1` extras), since we can no
  longer rely on ATT status to gate personalization.
- **Downgrade the privacy manifest:** `NSPrivacyTracking = false`, drop the
  `NSPrivacyTrackingDomains` array, change the data-type entry's `Tracking` flag to
  `false` (it becomes "collected, not linked, not used for tracking"). Re-answer the
  App Store **App Privacy** questionnaire so "Used for Tracking" is **No** everywhere.
- **Remove** `NSUserTrackingUsageDescription` from Info.plist (an unused ATT purpose
  string with no ATT call is a review-flag risk).
- **Keep UMP** — EEA/UK/California users still get the GDPR/CCPA consent form.

### Revenue impact
- Non-personalized banner eCPM is materially lower than personalized (commonly
  cited 30–50% lower for display, region-dependent). For a single-banner,
  1-per-day-capped, free Sudoku app the absolute delta is small, but it is a real
  revenue haircut. `[UNVERIFIED — Leader confirm]` Exact eCPM delta is
  market/inventory-specific; no internal data exists pre-launch.

### Privacy-posture fit
- **Strongest fit with the BRIEF** (`docs/marketing/BRIEF.md` line 36: *"No
  third-party tracking SDK… PrivacyInfo.xcprivacy shipped"*; line 54 forbids any
  tracking claim). Path A lets the App Store privacy "nutrition label" show **"Data
  Not Used to Track You"**, which is the cleanest possible story and matches the
  listing copy already written (`docs/app-store/metadata/en/listing.yaml`: *"No
  tracking — just an optional banner you remove with one purchase"*).
- Caveat: AdMob is still a third-party ad SDK and still collects **device/usage**
  data for ad delivery — Path A removes *cross-app tracking*, not *all* data
  collection. The nutrition label still lists data collected, just **not** under
  "Used to Track You."

### Copy for Path A
- **No priming screen, no ATT prompt, no `NSUserTrackingUsageDescription`.** Nothing
  to write — the absence *is* the design. The only copy touched is the UMP consent
  form, which is Google-hosted and configured in the AdMob console (not in our
  bundle).

---

## 5. Path B — Keep ATT, serve personalized ads on consent (RECOMMENDED)

This matches what the code, the privacy manifest, the privacy policy, and the v2.5
review doc already say. The work is to **polish**, not to build from zero.

### 5.1 Flow (deferred, HIG-aligned)

```
Cold launch
   │
   ├─ UMP consent (EEA/UK/CA only; Google-hosted form)        ← already wired
   │
   ▼
Home view renders, user plays / browses        ← DEFER here (the fix)
   │
   ├─ Trigger point: first ad-eligible moment after Home is seen
   │   (e.g. just before the first banner would load, or on first
   │    return to Home after a game). NOT cold launch.
   │
   ▼
[ Priming pre-prompt screen ]  ← NEW (does not exist today)
   │   "Keep Sudoku free" framing; user taps Continue or Not Now
   │
   ├─ Continue  → system ATT prompt → authorized → personalized ads
   │            → denied → non-personalized ads (AdMob fallback)
   │
   └─ Not Now   → skip system prompt this session; ATT stays
                  .notDetermined; ads serve non-personalized;
                  may re-offer on a later eligible moment
```

Rationale for the priming screen: the system ATT alert can be shown **once**. A
priming screen lets us (a) explain value before spending that single shot, and (b)
suppress the system alert entirely when the user says "Not Now," preserving the
ability to ask again later. This is the standard HIG-aligned pattern and is what
design.md §How.4 line 195 already mandates ("must have seen Home view first").

> `[UNVERIFIED — Leader confirm]` Exact trigger moment (before-first-banner vs.
> first-return-to-Home vs. after-first-completed-game) is a UX tuning call. Design
> doc only says "after Home is seen." Recommend: first ad-eligible moment after the
> 7-day grace period AND after Home has rendered — but that interacts with the
> existing `AdGate` grace logic and needs the user's call.

### 5.2 Priming pre-prompt screen — copy (English source)

**Title:** Keep Sudoku free

**Body:**
> Sudoku is free, with a single banner you can remove anytime. With your
> permission, we can show ads that are more relevant to you — which helps keep the
> app free. You're always in control, and you can change this later in Settings.

**Primary button:** Continue
**Secondary button:** Not Now

> The priming screen must **never** look like the system dialog and must **not**
> promise that tapping Continue grants anything — the real system prompt is the
> next step and the user can still decline there. (App Store Review Guideline 5.1.1
> forbids priming UI that mimics or pre-empts the system ATT alert.)

### 5.3 System ATT prompt purpose string (`NSUserTrackingUsageDescription`)

The OS shows this one line inside its own alert. It must be honest, concrete, and
≤ ~150 chars for legibility. Current string is acceptable but slightly salesy.
Proposed refinement:

> **Sudoku uses this to show ads more relevant to you. Decline and ads still
> work — just less tailored.**

(Drops "this identifier," which reads oddly to users; keeps the honest
"decline-still-works" reassurance Apple favors.) If the user prefers zero change,
the existing string is fine — it is **not** a blocker, only a polish item.

### 5.4 Localization (the #195 requirement)

The string must move from an Info.plist literal into a **`InfoPlist.xcstrings`**
catalog (does not exist yet) and be translated to the project's 7 locales
(zh-TW, en, ja, zh-CN, es, th, ko per the `ai-translated-localization` skill).
The priming-screen title/body/buttons go into the normal **`Localizable.xcstrings`**
(`Sudoku/Resources/Localizable.xcstrings`, which exists). Both follow the standard
AI-translation pass. Source (en) strings to translate:

| Key (suggested) | Source string |
|---|---|
| `InfoPlist / NSUserTrackingUsageDescription` | Sudoku uses this to show ads more relevant to you. Decline and ads still work — just less tailored. |
| `att.priming.title` | Keep Sudoku free |
| `att.priming.body` | Sudoku is free, with a single banner you can remove anytime. With your permission, we can show ads that are more relevant to you — which helps keep the app free. You're always in control, and you can change this later in Settings. |
| `att.priming.continue` | Continue |
| `att.priming.notNow` | Not Now |

> `[UNVERIFIED — Leader confirm]` Whether `NSUserTrackingUsageDescription` is best
> localized via an `InfoPlist.xcstrings` catalog vs. legacy per-language
> `InfoPlist.strings` files. The xcstrings catalog is the current-Xcode default and
> matches the project's existing `Localizable.xcstrings` usage; confirm before
> implementation.

### 5.5 Privacy / nutrition-label implications (Path B)
- **No change** to `PrivacyInfo.xcprivacy` — it already declares `NSPrivacyTracking
  = true` with the AdMob domains and the tracking-purpose data type. This is the
  one self-consistent path with the shipped manifest.
- App Store **App Privacy** questionnaire: "Used to Track You" = **Yes** for the ad
  data type. Nutrition label shows a **"Data Used to Track You"** section.
- **Marketing-copy tension** `[UNVERIFIED — Leader confirm + LEGAL]`: the listing
  (`docs/app-store/metadata/en/listing.yaml` lines 5, 29, 54) and BRIEF (lines 36,
  54) say **"No tracking."** Under Path B the nutrition label will say the
  opposite. **This contradiction must be resolved before submission** regardless of
  path: either (a) Path A, which makes "No tracking" literally true, or (b) Path B
  with the marketing copy reworded to "no *first-party* tracking; the only
  third-party SDK is Google's ad library, removable via Remove Ads." This is the
  hidden cost of Path B and the strongest argument for Path A.

---

## 6. Side-by-side

| Dimension | Path A (drop ATT / NPA-only) | Path B (keep ATT / personalized) **[recommended]** |
|---|---|---|
| ATT system prompt | None | Yes, deferred + primed |
| `NSUserTrackingUsageDescription` | Remove | Keep (localize) |
| Priming screen | None | New screen, localized |
| `PrivacyInfo` tracking | `false` (downgrade, edit needed) | `true` (no change — matches shipped) |
| Nutrition label | "Data **Not** Used to Track You" | "Data **Used** to Track You" |
| UMP consent (EEA/CA) | Still required | Still required |
| Ad revenue | Lower (NPA only) | Higher (personalized on consent) |
| Fit with BRIEF "No tracking" | Clean ✓ | Requires copy rework ✗ |
| Work to ship | Remove code + edit manifest + re-answer App Privacy + force `npa=1` | Localize string + add priming screen + fix prompt timing |
| Matches current codebase | No — undoes shipped infra | **Yes — polishes shipped infra** |

---

## 7. The decision for the user

> **Does Sudoku request ATT and serve personalized ads (Path B), or drop ATT and
> serve non-personalized ads only (Path A)?**

The codebase, privacy manifest, privacy policy, and v2.5 review doc are **all
already on Path B**. Recommending we **stay on Path B** and fix the two real
defects (cold-launch timing → deferred+primed; English-only literal → 7-locale
catalog). The one thing Path B forces is a **marketing-copy rework** to stop saying
the unqualified "No tracking" — that contradiction exists *today* and must be fixed
either way.

Path A is a legitimate alternative if the user values the pristine "No tracking"
nutrition label over personalized-ad revenue — but it is a **deliberate removal of
shipped functionality**, not a simplification, and it still needs UMP.

### Open questions (Leader/User to resolve before any implementation)
1. **Path A or Path B?** (the core call)
2. If B: exact deferred trigger moment (§5.1) — interacts with `AdGate` grace logic.
3. If B: keep current purpose string or adopt the §5.3 refinement?
4. Either path: **rework the "No tracking" marketing copy** to be accurate
   (mandatory — `[UNVERIFIED — LEGAL]` confirm wording).
5. Out of scope but flagged: should we set an explicit `npa=1` fallback in
   `loadBanner()` rather than relying on AdMob's implicit behavior? (separate issue)

---

## 8. Scope note

Per issue #195's "[rescoped: ATT-only]" tag, **push notifications and the
denial→Settings deep-link are explicitly out of scope** for this doc. For Path B a
"change this later in Settings" line appears in the priming copy; wiring an actual
Settings deep-link (`UIApplication.openSettingsURLString`) is a follow-up, not part
of this decision.

---

### Appendix — `[UNVERIFIED]` flags collected
- §3: AdMob auto-NPA-fallback is Google-documented but **not** enforced by an
  explicit flag in our `Request()` — Leader confirm.
- §4: NPA eCPM delta is market-specific; no internal data pre-launch.
- §5.1: exact deferred trigger moment is a UX tuning call not pinned by design.md.
- §5.4: `InfoPlist.xcstrings` vs legacy `InfoPlist.strings` for localizing the
  purpose string — confirm catalog choice.
- §5.5: marketing "No tracking" vs Path B nutrition label is a real contradiction —
  Leader + LEGAL confirm reworded copy.
