# Tuist scheme — StoreKit configuration wiring

- Branch: `feat/tuist-storekit-scheme` (from `main`)
- Touched: `Project.swift`, `docs/v2/v2.5-readiness.md`
- Tuist: aqua:tuist/tuist 4.194.4

## Why

PR #85 added `App/Resources/Sudoku.storekit`, but Tuist's existing
`runAction: .runAction(configuration: "Debug", executable: "Sudoku")`
omitted the `options:` parameter, so the generated scheme had no
`<StoreKitConfigurationFileReference>` and every fresh clone had to wire
it via the Xcode Scheme editor by hand.

## API used

Verified against the installed ProjectDescription swiftinterface
(`.../aqua-tuist-tuist/4.194.4/ProjectDescription.framework/Versions/A/Modules/ProjectDescription.swiftmodule/arm64-apple-macos.swiftinterface`):

```
public static func options(
    language: SchemeLanguage? = nil,
    region: String? = nil,
    storeKitConfigurationPath: Path? = nil,
    simulatedLocation: SimulatedLocation? = nil,
    enableGPUFrameCaptureMode: RunActionOptions.GPUFrameCaptureMode = .default
) -> RunActionOptions
```

and `Path.relativeToManifest(_ pathString: String) -> Path`.

## Patch

```swift
runAction: .runAction(
    configuration: "Debug",
    executable: "Sudoku",
    options: .options(
        storeKitConfigurationPath: .relativeToManifest("App/Resources/Sudoku.storekit")
    )
)
```

## Verification

```
$ mise exec aqua:tuist/tuist -- tuist generate --no-open
…
✔ Success Project generated.

$ grep -n -i storekit Sudoku.xcodeproj/xcshareddata/xcschemes/Sudoku.xcscheme
54:      <StoreKitConfigurationFileReference
55:         identifier = "../App/Resources/Sudoku.storekit">
56:      </StoreKitConfigurationFileReference>
```

The `identifier` is generated relative to the `.xcodeproj`
(`../App/Resources/...`) — that is Xcode's normal serialization for a
file at the workspace root and matches what the manual Scheme editor
produces.

## Doc edit

`docs/v2/v2.5-readiness.md` §"Local sandbox dry-run": removed the
`<<TODO(user)>>` block instructing the user to wire StoreKit via the
Xcode Scheme editor; replaced with a `[x]` line documenting that
`Project.swift` now owns the wiring. (Leader: this doc edit is on the
same branch — fold into the same commit or split as preferred.)

## §未決

None. Tuist 4.194.4 supports the wiring as a first-class parameter; no
workaround needed.
