# Settings toast migration — impl notes

Branch: `feat/settings-toast-migration` off `main`
Scope: PR-B of `2026-05-23_settings-view-design-review.impl-notes.md` §F1.2 + §F1.3
Predecessor: PR #117 (PR-A: section rename + leading SF Symbols)

## §What changed

Migrate Settings' inline result `Label` rows to the existing
`ToastController` infra (PR #85, mounted on `RootView`). Two flagged sites:

- **F1.2** purchase / restore success/failure (`MonetizationStateController.latestMessage`)
- **F1.3** clear-cache confirmation (`SettingsViewModel.clearCacheConfirmation`)

In both cases `latestMessage` / `clearCacheConfirmation` stay on the
view-model as the VoiceOver / test source of truth (the visual surface is
the bottom-center capsule — VoiceOver does not reliably announce a
transient overlay, per `ToastView.swift` header doc).

## §Wiring decision

**Init injection**, same shape MonetizationStateController already uses
(PR #85 precedent). Rejected alternatives:

- `@Environment(\.toastController)` — would require an EnvironmentKey +
  thread through Preview/Live anyway; init injection is simpler given the
  view-model is already constructed by RouteFactory.
- New facade — overkill for one push site per controller.

Both `MonetizationStateController.toastController` (existing, untouched)
and `SettingsViewModel.toastController` (new, optional) accept a `ToastController?`
parameter, default `nil` so existing tests don't need updates. RouteFactory
gains a `toastController` parameter and forwards it to `SettingsViewModel`
on `.settings` route construction. `AppComposition.Live` + `Preview` pass
the same toast instance they already pass to RootView.

## §Files modified

| File | Lines | Change |
|------|-------|--------|
| `SudokuUI/Settings/SettingsView.swift` | -36 net | Removed two orphan `Section { Label … }` blocks; removed `MonetizationLabel` helper + `monetizationMessage(for:)` (dead per design review §F2.4); removed unused `@Environment(\.theme)`. |
| `SudokuUI/Settings/SettingsViewModel.swift` | +14 | Added optional `toastController` init param; `clearCache()` pushes `Toast(style: .success, message: "Cache cleared")` after writing `clearCacheConfirmation`. Marked stored deps `@ObservationIgnored`. |
| `SudokuUI/Navigation/RouteFactory.swift` | +6 | Added optional `toastController` param; forwarded to `SettingsViewModel`. |
| `AppComposition/Live.swift` | +1 | Pass `toastController:` to `LiveRouteFactory(...)`. |
| `AppComposition/Preview.swift` | +1 | Same. |

Untouched per scope: `MonetizationStateController.swift` (already wired in
PR #85 — leader's task description was based on the pre-PR-#85 state), `RootView.swift` (overlay
already mounted), `ToastView.swift` / `ToastController.swift`.

## §Snapshots re-recorded

Deleted + regenerated 2 baselines (smaller Form after removing orphan rows):

- `__Snapshots__/SettingsIAPRowTests/snapshotIPhoneLightUnpurchased.SettingsView-iPhone-light-unpurchased.png`
- `__Snapshots__/SettingsIAPRowTests/snapshotIPhoneLightPurchased.SettingsView-iPhone-light-purchased.png`

Visual: Purchases section (Remove Ads + Restore) → About → Storage. No
post-Storage orphan section. (F1.4's `Form` chrome issue — labels rendering
inline, no grouped-list inset — is unchanged because that is a snapshot-host
issue, not in scope here.)

## §Tests

`swift build`: clean (5.22s).

`swift test --filter "Settings|Toast|MonetizationStateController"`:
**26 tests pass** across 6 suites.

One pre-existing async-timing flake (`purchasedEvent_flipsFlagTrue_andPushesSuccessToast`)
observed on first re-record run; passed on isolated re-run and on full
filter re-run. Not in scope; unrelated to these changes.

## §未決

1. **`clearCacheConfirmation` still public on view-model.** Kept as
   VoiceOver / test source of truth (test `clearCache_deletesResumeCandidateAndSetsConfirmation`
   asserts on it). Could be reduced to a private `var` if VoiceOver
   announcement coverage moved to a test that observes
   `accessibilityAnnouncement` instead; out of scope for this PR.

2. **Toast message strings duplicated.** `"Cache cleared"` lives in
   `SettingsViewModel`; `"Ads removed"` / `"Purchase revoked"` /
   `"Purchases restored"` live in `MonetizationStateController`. Lowest-friction
   for now; a central `ToastCopy` table is worth considering once a third
   source pushes toasts.

3. **`SettingsViewModel.toastController` default `nil`.** Same shape as
   `MonetizationStateController` for symmetry. RouteFactory's production
   path always passes a non-nil one; tests opt out by default. Could be
   made non-optional if the test fixtures grow a shared `ToastController`
   constant; out of scope.

4. **F1.4 (Form chrome render in snapshot host) untouched.** Design review
   noted snapshots render with no grouped-list inset / headers inline. The
   visible improvement here (orphan rows gone) is what was in scope for
   PR-B. F1.4 is a separate test-host investigation.
