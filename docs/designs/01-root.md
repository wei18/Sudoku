# 01 — RootView

## a. View identity

- **Purpose**: App entry. Bootstraps GC auth, surfaces a "resume last game" affordance if one exists, and routes to HomeView.
- **Triggers** (per §How.5.1): `GameCenterClient.authenticate()` in `.task`; `Persistence.latestInProgress()` to find resume candidate.
- **States**:
  - `bootstrapping` — auth + resume fetch in flight
  - `ready(noResume)` — show HomeView directly
  - `ready(resume: candidate)` — show HomeView with a "Resume" pill at top
  - `gcDegraded` — auth failed / restricted; HomeView visible, GC-gated features show CTA in their own Views (CompletionView / LeaderboardView)

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular, NavigationSplitView)
┌──────────────────────┐               ┌───────────┬──────────────────────┐
│ ↻ resume?            │               │ Sidebar   │  Home (detail)       │
│ ┌──────────────────┐ │               │           │                      │
│ │ Resume Easy 3:21 │ │               │ • Daily   │  Resume Easy 3:21 →  │
│ └──────────────────┘ │               │ • Practice│                      │
│                      │               │ • Leader  │  ┌────┐ ┌────┐       │
│   (HomeView body)    │               │ • Settings│  │Daily│ │Prac │ ...  │
│                      │               │           │  └────┘ └────┘       │
└──────────────────────┘               └───────────┴──────────────────────┘
```

Note: Root itself paints no UI on Mac — it becomes the `NavigationSplitView` container; resume pill lives in detail column header.

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/RootView_Designs.swift
import SwiftUI

struct ResumeCandidatePreview: Equatable {
    let difficultyLabel: String
    let elapsed: String
}

private enum SidebarMode: String, Hashable, CaseIterable, Identifiable {
    case daily, practice, leaderboard, settings
    var id: String { rawValue }
    var titleKey: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .practice: "Practice"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .daily: "calendar"
        case .practice: "dice"
        case .leaderboard: "trophy.fill"
        case .settings: "gear"
        }
    }
}

@MainActor
@Observable
final class RootViewModel_DesignStub {
    var resume: ResumeCandidatePreview? = .init(difficultyLabel: "Easy", elapsed: "3:21")
    var isBootstrapping = false
}

struct RootView_Designs: View {
    @State private var vm = RootViewModel_DesignStub()
    @State private var selected: SidebarMode? = .daily
    @Environment(\.horizontalSizeClass) private var hSize

    var body: some View {
        if hSize == .regular {
            NavigationSplitView {
                List(SidebarMode.allCases, selection: $selected) { mode in
                    Label(mode.titleKey, systemImage: mode.symbol).tag(mode)
                }
                .navigationTitle("Sudoku")
            } detail: {
                VStack {
                    resumePill
                    switch selected {
                    case .daily: DailyHubStub()
                    case .practice: PracticeHubStub()
                    case .leaderboard: LeaderboardStub()
                    case .settings: SettingsStub()
                    case .none: HomeStub()
                    }
                }
            }
        } else {
            NavigationStack { VStack { resumePill; HomeStub() } }
        }
    }

    @ViewBuilder private var resumePill: some View {
        if let r = vm.resume {
            HStack {
                Image(systemName: "arrow.clockwise")
                Text("Resume \(r.difficultyLabel) · \(r.elapsed)")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 14))
            .padding(.horizontal, 16)
        }
    }
}

private struct HomeStub: View {
    var body: some View { Text("HomeView →").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
}
private struct DailyHubStub: View {
    var body: some View { Text("DailyHubView →").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
}
private struct PracticeHubStub: View {
    var body: some View { Text("PracticeHubView →").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
}
private struct LeaderboardStub: View {
    var body: some View { Text("LeaderboardView →").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
}
private struct SettingsStub: View {
    var body: some View { Text("SettingsView →").foregroundStyle(.secondary).frame(maxHeight: .infinity) }
}

#Preview("Root — iPhone, light, en") {
    RootView_Designs()
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Root — Mac, dark, ja") {
    RootView_Designs()
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 600)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Resume pill background | `surface.glass` | default | `.glassEffect(.regular, in: rect(14))`; padding 12 |
| Resume pill text | `text.primary` | default | `.body` `.medium` |
| Resume pill icon | `accent.primary` | default | SF Symbol `arrow.clockwise`, 18 pt |
| Chevron | `text.tertiary` | default | SF `chevron.right`, 14 pt |
| Sidebar row (Mac) | system list | selected | `.tint(accent.primary)` |
| Bootstrapping placeholder | `text.secondary` | only when `isBootstrapping && resume == nil` | small `ProgressView()` top-center, never blocks Home |

Interaction:
- Tap resume pill → push `BoardView` for resume candidate's puzzleId (deep link via `AppRoute.board(...)`)
- Resume pill `onAppear` after 1.5 s: no auto-dismiss; persists until user navigates away or resumes
- Bootstrap never blocks Home — auth happens in background; Home is always interactive

## e. A11y notes

- Resume pill: `.accessibilityLabel("Resume \(difficultyLabel) puzzle, elapsed \(elapsed)")` + `.accessibilityHint("Opens the board")` + `.accessibilityAddTraits(.isButton)`
- Sidebar (Mac): native `List` selection handles VoiceOver; no override needed
- Dynamic Type acceptance: must survive `xSmall` … `xxxLarge` (resume pill wraps to 2 lines at xxxLarge — that's OK)
- Color-blind: resume pill carries icon + text, not color-only

## f. Design rationale

RootView is a coordinator, not a screen. We deliberately paint **at most** one pill on top of HomeView, rather than a full "loading splash" or a modal resume prompt. Reason: §What v1.4 promises "leaving never loses progress" — interrupting the user with a modal on every cold start to say "want to resume?" trains them that the app is fussy. A persistent, dismissable (by navigating away) pill respects both intents: see it, ignore it, or tap it.

Rejected: (1) full-screen splash with auth spinner — wastes cold-start budget and adds anxiety; (2) auto-resume on launch — violates §How.5.5 explicit "no auto-resume" rule. The pill is a compromise between discoverability and player agency.
