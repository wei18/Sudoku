# B-6 spike — AdMob banner × `tabViewBottomAccessory` (#1029, U-10)

**Throwaway sample. Never merge this branch.** Verdict lives as a comment on #1029.

Identifiers in this sample are Google's PUBLIC demo/test IDs
(developers.google.com/admob/ios/test-ads) — no production identifiers anywhere.

## Question

Does a real AdMob `BannerView` (a `UIViewRepresentable`, mirroring the shape of
`AdsAdMob/LiveAdMobBridge.swift`'s `BannerViewRepresentable`) render at non-zero
size inside `tabViewBottomAccessory`, and does the SDK's own impression callback
fire? (design.md §2.4 / U-10 — degradation fallback is "banner at tab-content
bottom" if this fails.)

## Verdict: PASS (2026-09-01, iPhone 17 Pro sim, iOS 26.5, Xcode 26.5, GMA SDK 13.4.0)

- Test creative renders inside the `.expanded` accessory capsule above the tab
  bar; `bannerViewDidReceiveAd` reports bounds **{360, 48}** (non-zero; the
  accessory stretches the view from `AdSizeBanner`'s 320×50 to fill itself).
- `bannerViewDidRecordImpression` fired in every run (twice across two
  launches), with the view window-attached.
- Scrolling with `.tabBarMinimizeBehavior(.onScrollDown)` transitions placement
  `.expanded → .inline` (logged via `@Environment(\.tabViewBottomAccessoryPlacement)`);
  the banner keeps rendering inside the inline pill, and the placement change
  does **not** re-create the representable (no double ad load).
- Feature-work notes for #1024: the 320×50 creative doesn't cover the capsule's
  rounded ends (black side slivers in `.expanded`) — the real feature should
  letterbox/background-fill or use adaptive banner sizing; in `.inline` the
  banner is horizontally compressed next to the minimized tab button but stays
  legible.

## Build & run

Links the GoogleMobileAds 13.4.0 / UMP 3.1.0 static xcframeworks straight out of
an existing SPM artifact checkout (any `DerivedData/*/SourcePackages/artifacts`
that has resolved the repo's pinned versions):

```bash
cd spikes/b6-admob-accessory
ART=<DerivedData>/SourcePackages/artifacts
GMA=$ART/swift-package-manager-google-mobile-ads/GoogleMobileAds/GoogleMobileAds.xcframework/ios-arm64_x86_64-simulator
UMP=$ART/swift-package-manager-google-user-messaging-platform/UserMessagingPlatform/UserMessagingPlatform.xcframework/ios-arm64_x86_64-simulator
mkdir -p B6.app
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator \
  -parse-as-library main.swift -F "$GMA" -F "$UMP" \
  -framework GoogleMobileAds -framework UserMessagingPlatform \
  -Xlinker -ObjC -o B6.app/B6
cp Info.plist B6.app/
xcrun simctl install <ios26-sim-udid> B6.app
xcrun simctl launch <ios26-sim-udid> com.spike.b6banner
# impression log:
xcrun simctl spawn <ios26-sim-udid> log stream --level info \
  --predicate 'eventMessage CONTAINS "B6SPIKE"'
```
