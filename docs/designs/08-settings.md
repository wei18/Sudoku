# 08 — SettingsView

> **AS-BUILT NOTE (2026-07-05):** board presentation switched to modal
> fullScreenCover (SDD-003); pause+leave unified (#660); completion = in-board
> overlay (#664/#669); timer in board header (#677). Where this doc says
> "push to BoardView", read "present modally" on iOS. Canonical flow spec:
> `docs/navigation-flows.md`. **§f note:** since #516 Settings paints the
> app's warm-paper theme background behind the native Form — a deliberate
> tonal-continuity exception to the "unbranded Settings" rationale below
> (structure/rows remain native).

## a. View identity

- **Purpose**: Read-only status surface + minimal preferences. GC auth state, locale, app version, "clear cache" action.
- **Triggers** (per §How.5.1): `GameCenterClient.currentAuthState` (read), `Persistence.totalCompletedCount` (read).
- **States**: single state — `default`. All status values are read-only snapshots; no loading state needed (synchronous reads + memoized).

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌────────────────────────────────────┐
│ < Settings           │               │ Settings                           │
│                      │               │                                    │
│ ACCOUNT              │               │ ACCOUNT                            │
│ Game Center          │               │   Game Center  ✓ Signed in: Wei    │
│   ✓ Signed in: Wei   │               │                                    │
│                      │               │ STATISTICS                         │
│ STATISTICS           │               │   Puzzles solved      214          │
│ Puzzles solved   214 │               │                                    │
│                      │               │ APPEARANCE                         │
│ APPEARANCE           │               │   Language        System ›         │
│ Language    System › │               │                                    │
│                      │               │ STORAGE                            │
│ STORAGE              │               │   Clear cache                      │
│ Clear cache          │               │                                    │
│                      │               │ ABOUT                              │
│ ABOUT                │               │   Version         1.0.0 (42)       │
│ Version  1.0.0 (42)  │               │   Generator       v1                │
│ Generator     v1     │               │   Privacy policy ›                  │
│ Privacy policy     › │               │                                     │
└──────────────────────┘               └────────────────────────────────────┘
```

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/SettingsView_Designs.swift
import SwiftUI

private enum GCAuthPreview { case authenticated(displayName: String), unauthenticated, restricted }

struct SettingsView_Designs: View {
    let gc: GCAuthPreview = .authenticated(displayName: "Wei")
    let solvedCount: Int = 214
    let version: String = "1.0.0 (42)"

    var body: some View {
        Form {
            Section("Account") {
                HStack {
                    Label("Game Center", systemImage: gcIconName)
                    Spacer()
                    Text(gcStatusText).foregroundStyle(.secondary)
                }
            }

            Section("Statistics") {
                LabeledContent("Puzzles solved", value: "\(solvedCount)")
            }

            Section("Appearance") {
                // Read-only per designer decision: System locale only in v1; no in-app override.
                LabeledContent("Language", value: "System (English)")
            }

            Section("Storage") {
                Button("Clear cache", role: .destructive) { }
            }

            Section("About") {
                LabeledContent("Version", value: version)
                NavigationLink("Privacy policy") { Text("Privacy stub") }
            }
        }
        .navigationTitle("Settings")
    }

    private var gcIconName: String {
        switch gc {
        case .authenticated: "person.crop.circle.badge.checkmark"
        case .unauthenticated, .restricted: "person.crop.circle.badge.questionmark"
        }
    }
    private var gcStatusText: LocalizedStringKey {
        switch gc {
        case .authenticated(let n): "Signed in: \(n)"
        case .unauthenticated: "Not signed in"
        case .restricted: "Restricted"
        }
    }
}

#Preview("Settings — iPhone, light, en") {
    NavigationStack { SettingsView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Settings — Mac, dark, ja") {
    NavigationStack { SettingsView_Designs() }
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 600)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Form background | system grouped | — | native `Form` style |
| Section header | `text.tertiary` | — | system caps style |
| Row label | `text.primary` | — | `.body` |
| Row value | `text.secondary` | — | `.body` |
| GC icon — authenticated | `status.success` | auth | `person.crop.circle.badge.checkmark` |
| GC icon — unauth/restricted | `status.warning` | not-auth | `person.crop.circle.badge.questionmark` |
| Disclosure chevron | system | — | native `NavigationLink` |
| Clear cache row | `status.error` | destructive | `.destructive` role; system applies red |

Interaction:
- Language row: read-only display of the active system locale (no in-app override in v1; see DESIGNER-DECISION in §f)
- Clear cache → confirmation dialog `"Reset session cache. Generated puzzles will be re-derived on next play (same seed → same puzzle). Your saved games are not affected."` → action → toast "Cache cleared"
- Privacy policy → in-app `Text` (legal copy bundled, not fetched)

## e. A11y notes

- Native `Form` rows already VO-friendly; no overrides needed
- GC status row: combined element `"Game Center, Signed in as Wei"` — name read as PII-safe via standard VO (Apple privacy)
- Dynamic Type: native Form handles all sizes
- Color-blind: GC status uses icon shape difference (checkmark vs question) + text; never color-only
- Destructive action: VO trait `.isButton` + role announcement

## f. Design rationale

Native `Form` with `Section` is correct here. We resist the temptation to make Settings "branded" — players come here once to check version or sign in / out, then leave. HIG's iOS Settings app is the template, and the more our Settings looks like that, the less cognitive overhead.

Read-only by default: §How.5.1 says this View reads `currentAuthState` and `totalCompletedCount` and nothing else. We don't add toggle for "haptic feedback" or "sound" because those features don't exist in v1 (the toggle without a feature is debt).

Rejected: (1) glass card per section — clashes with native Form; native is already the right answer; (2) profile photo / avatar — we have no profile system in v1, GC handles identity; (3) "Sign out of Game Center" button — GC sign-out is system-level (Settings.app), not in-app per Apple guidelines.

Generator version row exposes the `GeneratorVersion` to power users / bug reports; bumping it = new leaderboard family (§How.4.5), so it's a user-meaningful identifier, not internal-only.

`<DESIGNER-DECISION: System locale only; no in-app override in v1. Settings shows the active locale as read-only informational ("Language: System (English)"). The 7-locale matrix (zh-TW, en, ja, zh-CN, es, th, ko) is wide enough per ai-translated-localization skill; an in-app override doubles the UX surface (picker UI + restart prompt + persistence + AX strings) for marginal benefit. Override deferred to §Backlog if user feedback requests it. Rationale: HIG and Apple platform convention treat language as a system preference; in-app overrides are an exception, not a default.>`
