# B-7 spike — `GlassEffectContainer` × button style (#1029, U-9)

**Throwaway sample. Never merge this branch.** Verdict lives as a comment on #1029.

## Question

Does `GlassEffectContainer` merge child shapes when the children use the *system*
button style (`.buttonStyle(.glass)`), the way design.md §4.6 describes for
explicit `.glassEffect()` children? (design.md §12 error #8 documents the earlier
misreading — "an empty container with independently-floating buttons".)

## Verdict: PASS (2026-09-01, iPhone 17 Pro sim, iOS 26.5, Xcode 26.5)

- Both `.buttonStyle(.glass)` and `.glassEffect()` children contribute shapes to
  the container merge — behavior is identical column-to-column at every gap.
- With `GlassEffectContainer(spacing: 40)`: gap 40 = fully separate; gap 24 =
  shapes deform toward neighbors; gap ≤ 12 = one continuous glass shape
  (gap 12 still shows lobes; gap 6/2 read as a single capsule).
- Control (same buttons, gap 2, **no** container): three fully separate
  capsules — the merge is genuinely the container's contribution.

## Build & run

```bash
cd spikes/b7-glass-container
mkdir -p B7.app
xcrun -sdk iphonesimulator swiftc -target arm64-apple-ios26.0-simulator \
  -parse-as-library main.swift -o B7.app/B7
cp Info.plist B7.app/
xcrun simctl install <ios26-sim-udid> B7.app
xcrun simctl launch <ios26-sim-udid> com.spike.b7glass
```
