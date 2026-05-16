# 07 — LeaderboardView

## a. View identity

- **Purpose**: Full leaderboard browsing. Scope toggle (Global / Around me / Friends) × difficulty toggle.
- **Triggers** (per §How.5.1): `GameCenterClient.fetchLeaderboardSlice(scope:)`.
- **States**:
  - `loading`
  - `loaded(entries)`
  - `empty(scope)` — e.g. "no friends playing yet"
  - `unauthenticated` — GC degraded; show single CTA
  - `error(reason)` — fetch failed; show retry

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌──────────────────────────────────────┐
│ < Leaderboard        │               │ Leaderboard                          │
│                      │               │                                      │
│ ┌──────────────────┐ │               │  ┌──────────────────────────────┐    │
│ │Global│Around│Frnd│ │               │  │ Global │ Around me │ Friends │    │
│ └──────────────────┘ │               │  └──────────────────────────────┘    │
│ ┌──────────────────┐ │               │  ┌─────────────────────────────────┐ │
│ │E│M│H│X│           │ │               │  │ Easy · Medium · Hard · Expert  │ │
│ └──────────────────┘ │               │  └─────────────────────────────────┘ │
│                      │               │                                      │
│ 1.  alice    3:48    │               │  1.  alice         3:48              │
│ 2.  bob      3:55    │               │  2.  bob           3:55              │
│ 3.  carol    4:02    │               │  3.  carol         4:02              │
│ 4.  dave     4:18    │               │  ...                                 │
│ 5.  eve      4:24    │               │ 17. **you**        4:11   (around)   │
│ ...                  │               │                                      │
│ 17. **you**  4:11    │               │                                      │
└──────────────────────┘               └──────────────────────────────────────┘
```

## b.2 Unauthenticated variant

```
┌──────────────────────┐
│ < Leaderboard        │
│                      │
│      🔒              │
│   Sign in to         │
│   Game Center        │
│   to see rankings    │
│  [ Sign in ]         │
└──────────────────────┘
```

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/LeaderboardView_Designs.swift
import SwiftUI

private struct LBEntry: Identifiable { let rank: Int; let name: String; let time: String; let isMe: Bool; var id: Int { rank } }
private enum LBScope: String, CaseIterable, Identifiable { case global = "Global", around = "Around me", friends = "Friends"; var id: String { rawValue }; var key: LocalizedStringKey { LocalizedStringKey(rawValue) } }
private enum LBDifficulty: String, CaseIterable, Identifiable { case easy = "Easy", medium = "Medium", hard = "Hard", expert = "Expert"; var id: String { rawValue }; var key: LocalizedStringKey { LocalizedStringKey(rawValue) } }

private enum LBStatePreview {
    case loaded([LBEntry])
    case unauthenticated
    case error
    case loading
}

struct LeaderboardView_Designs: View {
    @State private var scope: LBScope = .global
    @State private var difficulty: LBDifficulty = .easy
    var state: LBStatePreview = .loaded([
        .init(rank: 1, name: "alice", time: "3:48", isMe: false),
        .init(rank: 2, name: "bob", time: "3:55", isMe: false),
        .init(rank: 3, name: "carol", time: "4:02", isMe: false),
        .init(rank: 17, name: "you", time: "4:11", isMe: true),
    ])

    var body: some View {
        VStack(spacing: 12) {
            Picker("Scope", selection: $scope) {
                ForEach(LBScope.allCases) { Text($0.key).tag($0) }
            }
            .pickerStyle(.segmented)
            .glassEffect(.regular, in: .rect(cornerRadius: 10))

            Picker("Difficulty", selection: $difficulty) {
                ForEach(LBDifficulty.allCases) { Text($0.key).tag($0) }
            }
            .pickerStyle(.segmented)

            content
        }
        .padding(16)
        .navigationTitle("Leaderboard")
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .loaded(let entries):
            List(entries) { row($0) }
                .listStyle(.plain)
                .refreshable {
                    // Pull-to-refresh on iPhone; triggers same refetch as ⌘R on Mac.
                }
                .background(
                    // Hidden ⌘R shortcut for Mac keyboard refresh.
                    Button("Refresh") { }
                        .keyboardShortcut("r", modifiers: .command)
                        .accessibilityHidden(true)
                        .hidden()
                )
        case .unauthenticated:
            unauthState
        case .error:
            errorState
        case .loading:
            ProgressView().controlSize(.large).frame(maxHeight: .infinity)
        }
    }

    private func row(_ e: LBEntry) -> some View {
        HStack {
            Text("\(e.rank).").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Text(e.name)
                .fontWeight(e.isMe ? .semibold : .regular)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(e.name)                          // macOS hover tooltip for full name
            Spacer()
            Text(e.time).monospacedDigit()
        }
        .listRowBackground(e.isMe ? Color.accentColor.opacity(0.12) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(e.isMe
            ? "Rank \(e.rank), you, \(e.name), \(e.time)"
            : "Rank \(e.rank), \(e.name), \(e.time)")
    }

    private var unauthState: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock").font(.system(size: 48)).foregroundStyle(.secondary)
            Text("Sign in to Game Center").font(.title3.weight(.medium))
            Text("Rankings sync once you sign in.").font(.callout).foregroundStyle(.secondary)
            Button("Sign in") { }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(minHeight: 48)
        }
        .frame(maxHeight: .infinity)
    }

    private var errorState: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 36)).foregroundStyle(.orange)
            Text("Couldn't load leaderboard.")
            Button { } label: { Label("Retry", systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
        }
        .frame(maxHeight: .infinity)
    }
}

#Preview("Leaderboard — iPhone, light, en") {
    NavigationStack { LeaderboardView_Designs() }
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}

#Preview("Leaderboard — unauth, iPhone, light, ja") {
    NavigationStack { LeaderboardView_Designs(state: .unauthenticated) }
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.light)
}

#Preview("Leaderboard — Mac, dark, zh-TW") {
    NavigationStack { LeaderboardView_Designs() }
        .environment(\.locale, .init(identifier: "zh-Hant"))
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 600)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Scope picker | system segmented | default | wrapped in `.glassEffect` (only chrome control on screen with glass) |
| Difficulty picker | system segmented | default | no glass; sits below scope |
| Row rank | `text.secondary` | — | `.body .monospacedDigit()` 40 pt fixed |
| Row name | `text.primary` | mine = `.semibold` | `.body` |
| Row time | `text.primary` | — | `.body .monospacedDigit()` |
| Mine row bg | `accent.muted` | mine | α0.12 |
| Empty / error icon | `text.secondary` / `status.warning` | per state | 36–48 pt |
| Sign in CTA | `accent.primary` | unauth | `.borderedProminent` |

Interaction:
- Scope change → refetch with `.task(id: scope)`
- Difficulty change → same
- Pull-to-refresh on iPhone; `⌘R` on Mac
- Tap own row → no-op (we already know we're us)

## e. A11y notes

- Each row combined element: `"Rank 17, you, 4 minutes 11 seconds"` for self; `"Rank 1, alice, 3 minutes 48 seconds"` for others
- Pickers: native VO support
- Dynamic Type: rank column fixed-width; name truncates to 1 line with middle-truncation (`.truncationMode(.middle)`). Full name is available via the row's `.accessibilityLabel(fullName)` for VoiceOver and via a macOS hover tooltip (`.help(fullName)`). `<DESIGNER-DECISION: 1-line middle-truncate + VO label + Mac hover tooltip; no popover-on-tap. Rationale: HIG default for leaderboards is single-line rows; popover-on-tap is unusual UX for ranking lists and conflicts with the "tap own row = no-op" rule above. Full name remains accessible without adding a tap-gesture surface.>`
- Color-blind: "you" highlighted by font weight + accent tint background — survives monochrome rendering

## f. Design rationale

Two stacked segmented controls (scope + difficulty) instead of a single Menu picker because the matrix is small (3×4 = 12 combinations) and discoverability matters — many players will never have tapped "Friends" scope and we want it visible. Glass on the scope picker, flat on difficulty: the visual hierarchy says "scope is the bigger choice."

Rejected: (1) tab bar for scope — uses too much chrome on a screen that's mostly a list; (2) single combined "Easy Global" Menu — hides the friend-scope discoverability; (3) infinite scroll with on-the-fly fetching — overkill for v1 (§How.3 leaderboard slice is bounded). Show what `fetchLeaderboardSlice` returns and stop.

Three-way error state separation (`unauthenticated` vs `error` vs `empty`) mirrors CompletionView for consistency — players who see GC unauth there should see the same UI here.
