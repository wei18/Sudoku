# LicensePlist Integration — Status & Follow-up Plan (2026-05-26)

Status: TOOLING LANDED — SwiftUI INTEGRATION DEFERRED to follow-up
Backlog source: `docs/foundations.md §Backlog` entry 2026-05-23
Dispatch reference: 3-item foundations §Backlog sweep (2026-05-26)

## What landed this dispatch

1. `.mise.toml` — added `"ubi:mono0926/LicensePlist" = "latest"` (pin tighter once Leader runs `mise install` and notes the resolved version).
2. `scripts/generate-acknowledgements.sh` — Bash script that resolves the binary (mise-managed or PATH fallback) and runs LicensePlist against both `Packages/AppMonetizationKit` and `Packages/SudokuKit`. Output → `App/Resources/Acknowledgements/`.

## What was NOT done and why

| Deliverable | Status | Blocker |
|---|---|---|
| Actually run `scripts/generate-acknowledgements.sh` | DEFERRED | `mise install` denied in subagent sandbox; license-plist binary not on PATH |
| `chmod +x scripts/generate-acknowledgements.sh` | DEFERRED | `chmod` denied in subagent sandbox — Leader to run once or commit mode 0755 via fresh `git add --chmod=+x` |
| `App/Resources/Acknowledgements/Acknowledgements.md` | DEFERRED | Real content depends on running the script; would rather not commit a hand-written placeholder that diverges from generator output |
| `Project.swift` resource bundle entry | DEFERRED | Avoid bundling a not-yet-existing resource path |
| `SettingsView.swift` Acknowledgements row | DEFERRED | Cohesive change — should land together with the resource so snapshot test regen happens once |
| `AcknowledgementsView.swift` (markdown viewer) | DEFERRED | Same as above |
| Snapshot baseline regen for `SettingsViewTests` | DEFERRED | Requires the row to exist |

## Follow-up PR plan (recommended single PR after Leader pre-flight)

### Pre-flight (Leader)
1. `mise install ubi:mono0926/LicensePlist` — verify it resolves; pin the exact version back in `.mise.toml`.
2. `chmod +x scripts/generate-acknowledgements.sh`
3. `./scripts/generate-acknowledgements.sh` — confirm it emits `App/Resources/Acknowledgements/Acknowledgements.md` listing Apache 2.0 entries for `swift-package-manager-google-mobile-ads`, `swift-package-manager-google-user-messaging-platform`, and Apache 2.0 (or MIT) for `swift-snapshot-testing`.
4. Skim the generated file for any unexpected entries (transitive deps under GoogleMobileAds occasionally surface).

### Code changes (subagent dispatch)

#### 1. Bundle the resource

`Project.swift` — add to App target's `resources:` array:

```swift
resources: [
    "App/Assets.xcassets",
    "App/Resources/PrivacyInfo.xcprivacy",
    "App/Resources/Localizable.xcstrings",
    "App/Resources/Acknowledgements/Acknowledgements.md",   // <-- new
],
```

#### 2. New view: `AcknowledgementsView.swift`

Location: `Packages/SudokuKit/Sources/SudokuUI/Settings/AcknowledgementsView.swift`

Surface:
```swift
public import SwiftUI

public struct AcknowledgementsView: View {
    public init() {}

    public var body: some View {
        ScrollView {
            Text(loadMarkdown())
                .textSelection(.enabled)
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Acknowledgements")
    }

    private func loadMarkdown() -> AttributedString {
        guard
            let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "md"),
            let data = try? Data(contentsOf: url),
            let raw = String(data: data, encoding: .utf8),
            let attributed = try? AttributedString(
                markdown: raw,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
        else {
            return AttributedString("Acknowledgements unavailable.")
        }
        return attributed
    }
}
```

Notes:
- Uses `Bundle.main` — works because the resource is bundled at App target level (not SudokuUI package level).
- Falls back to a soft message on missing file (e.g., during SwiftUI previews where `Bundle.main` is the Xcode preview host).
- `.inlineOnlyPreservingWhitespace` keeps newlines while still rendering inline markdown (links, bold). LicensePlist output is mostly preformatted license bodies — this preserves layout.

#### 3. `SettingsView.swift` — add a row to the About section

```swift
Section("About") {
    LabeledContent { ... Version ... }
    LabeledContent { ... Generator ... }
    NavigationLink {
        AcknowledgementsView()
    } label: {
        Label("Acknowledgements", systemImage: "doc.text")
            .foregroundStyle(.secondary)
    }
}
```

The existing `SettingsView` is presented inside a `NavigationStack` (per RouteFactory wiring) so `NavigationLink` is the natural primitive.

#### 4. Snapshot regen

`Tests/SudokuUITests/SettingsViewTests.swift` — snapshot baselines under `Tests/SudokuUITests/__Snapshots__/SettingsViewTests/` will need refresh:
- `record: true` once, then back to `record: false`
- Affects ~3 baselines (light/dark/sysprefs themes — confirm via `ls __Snapshots__/SettingsViewTests/`)

#### 5. L10n

`App/Resources/Localizable.xcstrings` — add a new key `"Acknowledgements"` with translations for all 7 locales (zh-Hant / en / ja / zh-Hans / es / th / ko). Per `ai-translated-localization` skill, this is a 1-line key easy enough to add manually or via the L10n agent flow.

Suggested translations (manual, to be reviewed by L10n agent):
| Locale | String |
|---|---|
| en | Acknowledgements |
| zh-Hant | 致謝 |
| zh-Hans | 致谢 |
| ja | 謝辞 |
| es | Reconocimientos |
| th | ขอขอบคุณ |
| ko | 감사의 글 |

### Tests
- `swift test --filter Settings` — verify Settings snapshot regen passes and `SettingsViewTests.snapshotsSettingsView_*` baselines updated.
- `swift build` from `Packages/SudokuKit/` — verify SudokuUI builds with the new view.
- Smoke: launch app → Settings tab → "Acknowledgements" row → verify the markdown renders and is scrollable.

### CI
- Skip — `scripts/generate-acknowledgements.sh` is manual. CI should NOT regen during a build because it would require committing back to the repo (cycle).

### App Store legal requirement
- Apache 2.0 + MIT both require the license text to be reproduced verbatim somewhere the end-user can access. The bundled markdown in Settings satisfies this contract.
- v2 review note: confirm Acknowledgements row visible during a TestFlight build before submitting to App Store Review.

## Open questions for Leader

1. **Pin LicensePlist to which version?** Default in `.mise.toml` is `latest` — should be pinned to a major (e.g. `3`) or exact version after pre-flight install.
2. **Include `swift-snapshot-testing` in the listing?** It's a test-only dep and not in the shipping binary; some apps omit test deps from Acknowledgements. Default in the script is to include it (LicensePlist scans all Package.resolved entries from the scanned paths). To omit, pass `--exclude swift-snapshot-testing` or only point LicensePlist at `Packages/AppMonetizationKit`.
3. **Settings.bundle vs SwiftUI** — Reaffirmed SwiftUI per spec. Skip Settings.bundle entirely (the app already owns its Settings via SwiftUI Form; Settings.bundle would split L10n and theming).
