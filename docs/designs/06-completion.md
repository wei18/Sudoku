# 06 — CompletionView

## a. View identity

- **Purpose**: Shown when a session reaches `completed`. Displays time, personal record delta, and a leaderboard slice (top + around-player). Modal.
- **Triggers** (per §How.5.1): `GameCenterClient.fetchLeaderboardSlice(.globalTop)` + `.aroundPlayer` (Daily mode + authenticated only); `Persistence` to compute personal record delta.
- **Presentation**: iPhone `.fullScreenCover`; Mac `.sheet`.
- **States**:
  - `loading` — fetching leaderboard slice
  - `authenticated(slice)` — happy path
  - `unauthenticated` — GC degraded; show CTA "Sign in to Game Center"
  - `fetchFailed` — show personal record only + "Couldn't load leaderboard" inline
  - `practiceMode` — no leaderboard call at all; just personal record + "Play again"

## b. ASCII wireframe

```
iPhone (compact)                       Mac (regular)
┌──────────────────────┐               ┌──────────────────────────────────────┐
│             [ Done ] │               │              [ × ]                   │
│                      │               │                                      │
│  ╭──────────────────╮│               │  ╭────────────────────────────────╮  │
│  │  ✓               ││               │  │  ✓  Solved!                    │  │
│  │  Solved!         ││               │  │  Easy · 4:11  (new best −0:23) │  │
│  │  Easy · 4:11     ││               │  ╰────────────────────────────────╯  │
│  │  new best −0:23  ││               │                                      │
│  ╰──────────────────╯│               │  Leaderboard — Easy daily today      │
│                      │               │  1.  alice         3:48              │
│  Top                 │               │  2.  bob           3:55              │
│  1. alice  3:48      │               │  3.  carol         4:02              │
│  2. bob    3:55      │               │  …                                   │
│  3. carol  4:02      │               │  17. **you**       4:11  ← (around)  │
│                      │               │  18. dave          4:18              │
│  Around you          │               │  19. eve           4:24              │
│  16. ...  4:09       │               │                                      │
│ ▶17. you   4:11      │               │  [ View full leaderboard → ]         │
│  18. dave  4:18      │               │                                      │
│                      │               │                                      │
│  [ View full ] [Play]│               │  [ Play again ]   [ Done ]           │
└──────────────────────┘               └──────────────────────────────────────┘
```

## b.2 Unauthenticated variant

Hero block stays. Below it: `"Sign in to Game Center to compare with others."` + button. No leaderboard rows.

## b.3 Fetch-failed variant

Hero block stays. Below it: `"Couldn't load leaderboard. Tap to retry."` + retry button (SF `arrow.clockwise`).

## c. SwiftUI preview code skeleton

```swift
// DESIGN PREVIEW ONLY — docs/designs/code/CompletionView_Designs.swift
import SwiftUI

private struct LBEntry: Identifiable { let rank: Int; let name: String; let time: String; let isMe: Bool; var id: Int { rank } }

private enum CompletionStatePreview {
    case authenticated(top: [LBEntry], around: [LBEntry])
    case unauthenticated
    case fetchFailed
    case loading
    case practiceMode
}

struct CompletionView_Designs: View {
    // Token stub helpers (snapshot stability — production uses design-system tokens).
    // Literal hex sourced from design-system.md.
    private var statusSuccess: Color { Color(red: 0x1B/255, green: 0x7A/255, blue: 0x3E/255) }   // status.success light
    private var statusError: Color { Color(red: 0xC8/255, green: 0x36/255, blue: 0x2B/255) }    // status.error light

    var state: CompletionStatePreview = .authenticated(
        top: [.init(rank: 1, name: "alice", time: "3:48", isMe: false),
              .init(rank: 2, name: "bob", time: "3:55", isMe: false),
              .init(rank: 3, name: "carol", time: "4:02", isMe: false)],
        around: [.init(rank: 16, name: "frank", time: "4:09", isMe: false),
                 .init(rank: 17, name: "you", time: "4:11", isMe: true),
                 .init(rank: 18, name: "dave", time: "4:18", isMe: false)])

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                hero
                content
                buttons
            }
            .padding(20)
        }
        .background(Color(.systemBackground))
    }

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill").font(.system(size: 56)).foregroundStyle(statusSuccess)
            Text("Solved!").font(.largeTitle.weight(.semibold))
            Text("Easy · 4:11").font(.title3).foregroundStyle(.secondary)
            // Delta uses sign (−) + monospaced digit + color → color-blind safe triple encoding.
            Text("new best −0:23").font(.callout.monospacedDigit()).foregroundStyle(statusSuccess)
        }
        .frame(maxWidth: .infinity).padding(24)
        .glassEffect(.regular, in: .rect(cornerRadius: 20))
    }

    @ViewBuilder private var content: some View {
        switch state {
        case .authenticated(let top, let around):
            VStack(alignment: .leading, spacing: 16) {
                section("Top") { ForEach(top) { row($0) } }
                section("Around you") { ForEach(around) { row($0) } }
            }
        case .unauthenticated:
            VStack(spacing: 12) {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Sign in to Game Center to compare with others.").multilineTextAlignment(.center)
                Button("Sign in") { }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .frame(minHeight: 48)
            }
        case .fetchFailed:
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 32)).foregroundStyle(.orange)
                Text("Couldn't load leaderboard.").font(.body)
                Button { } label: { Label("Retry", systemImage: "arrow.clockwise") }
                    .buttonStyle(.bordered)
            }
        case .loading:
            ProgressView().controlSize(.large).frame(maxWidth: .infinity, minHeight: 120)
        case .practiceMode:
            // §How.3 — Practice does not write to GC; suppress all GC UI here.
            EmptyView()
        }
    }

    private func section<C: View>(_ title: LocalizedStringKey, @ViewBuilder rows: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(spacing: 4) { rows() }
        }
    }

    private func row(_ e: LBEntry) -> some View {
        HStack {
            Text("\(e.rank).").monospacedDigit().foregroundStyle(.secondary).frame(width: 32, alignment: .trailing)
            Text(e.name).fontWeight(e.isMe ? .semibold : .regular)
            Spacer()
            Text(e.time).monospacedDigit()
        }
        .padding(.vertical, 6).padding(.horizontal, 8)
        .background(e.isMe ? Color.accentColor.opacity(0.12) : Color.clear, in: .rect(cornerRadius: 8))
    }

    @ViewBuilder private var buttons: some View {
        if case .practiceMode = state {
            // Practice: hero + "Play again" only — no Leaderboard CTA per §How.3.
            Button("Play again") { }.buttonStyle(.borderedProminent)
        } else {
            HStack(spacing: 12) {
                Button("View full leaderboard") { }.buttonStyle(.bordered)
                Button("Play again") { }.buttonStyle(.borderedProminent)
            }
        }
    }
}

#Preview("Completion — authenticated, iPhone, light, en") {
    CompletionView_Designs(state: .authenticated(
        top: [.init(rank: 1, name: "alice", time: "3:48", isMe: false)],
        around: [.init(rank: 17, name: "you", time: "4:11", isMe: true)]
    ))
    .environment(\.locale, .init(identifier: "en"))
    .preferredColorScheme(.light)
}

#Preview("Completion — unauthenticated, iPhone, light, zh-TW") {
    CompletionView_Designs(state: .unauthenticated)
        .environment(\.locale, .init(identifier: "zh-Hant"))
        .preferredColorScheme(.light)
}

#Preview("Completion — failed, Mac, dark, ja") {
    CompletionView_Designs(state: .fetchFailed)
        .environment(\.locale, .init(identifier: "ja"))
        .preferredColorScheme(.dark)
        .frame(width: 700, height: 500)
}

#Preview("Completion — practiceMode, iPhone, light, en") {
    // Practice mode: hero + Play again only; no Leaderboard section; GC UI suppressed (§How.3).
    CompletionView_Designs(state: .practiceMode)
        .environment(\.locale, .init(identifier: "en"))
        .preferredColorScheme(.light)
}
```

## d. Visual / interaction spec

| Element | Token | State | Spec |
|---|---|---|---|
| Hero background | `surface.glass` | always | `.glassEffect(.regular, in: rect(20))` |
| Solved icon | `status.success` | — | `checkmark.circle.fill` 56 pt |
| "Solved!" headline | `text.primary` | — | `.largeTitle .semibold` |
| Subtitle (mode · time) | `text.secondary` | — | `.title3` |
| Record delta | `status.success` (improvement) / `text.secondary` (no change) | — | `.callout` |
| Section header ("Top" / "Around you") | `text.primary` | — | `.headline` |
| Row rank | `text.secondary` | — | `.body .monospacedDigit()`, right-aligned, fixed 32 pt |
| Row name | `text.primary` | mine = `.semibold` | `.body` |
| Row time | `text.primary` | — | `.body .monospacedDigit()` |
| "You" row highlight | `accent.muted` | mine | bg fill α0.12 |
| Unauthenticated CTA | `accent.primary` | — | `.bordered` |
| Failed retry | `accent.primary` | — | `.bordered` with `arrow.clockwise` icon |
| "View full leaderboard" | `accent.primary` | — | `.bordered` |
| "Play again" | `accent.primary` | — | `.borderedProminent` |

Interaction:
- Hero stats fade-in cascade on appear: solved icon → headline → subtitle → delta, 60 ms stagger, 350 ms each. Skipped under reduce-motion.
- "View full leaderboard" → push `LeaderboardView` via `AppRoute.leaderboard(...)`
- "Play again" (Practice mode) → draw new puzzle of same difficulty, dismiss + push BoardView
- "Done" / `×` → dismiss back to caller (DailyHub or PracticeHub)

## e. A11y notes

- Hero composed: `.accessibilityElement(children: .combine)` → `"Solved Easy in 4 minutes 11 seconds, new best, 23 seconds faster"`
- Each LB row: combined element, `"Rank 17, you, 4 minutes 11 seconds"`. The mine-flag is announced via "you" in label, not just visual highlight
- Dynamic Type: ranks remain monospaced-digit + fixed 32 pt label width. Names wrap if needed.
- Color-blind: record delta uses sign (`−0:23` vs `+0:05`) plus color; never color-alone

## f. Design rationale

This screen has a narrow window — players close it within ~3 seconds typically. We optimize **glance-ability**: a single hero block tells the player the only thing they want to know (did I improve?). Leaderboard slice is secondary content below the fold.

Three state variants are first-class, not edge cases, because §How.6.3 (GC error matrix) and §How.3.4 (auth degraded) both route here. Authentication-failed and fetch-failed are *different* user experiences — one needs a CTA to sign in, the other needs a retry — so we don't collapse them.

Rejected: (1) full-screen confetti / celebration animation — anti-pattern for a contemplation game and creates "did I lose progress?" anxiety when dismissed accidentally; (2) showing all 100 leaderboard entries inline — that's what LeaderboardView is for, link instead; (3) Practice mode showing a fake-leaderboard — Practice doesn't write to GC (§How.3), so showing rankings would be dishonest.

`<DESIGNER-DECISION: Keep the `−0:23` delta text. It is already color-blind safe via the triple encoding (sign character + monospaced digit + color); a "PB" chip would be gratuitous and redundant. Rationale: the sign + monospaced digit reads unambiguously in monochrome / high-contrast / VO; a chip adds visual chrome without information. PB chip moved to §Backlog if user feedback later requests it.>`
