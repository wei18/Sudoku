// Spike1019RootView — THROWAWAY. Issue #1019 (epic #1014, P0-5 / design risk
// B-4). Do NOT build on this branch; it exists only to answer:
//
//   "If RootShellView is rewritten as a `sidebarAdaptable` TabView, does
//    #763's guarantee survive — pause/completion overlays mask ONLY the
//    detail/content column while every sidebar row and tab-switch control
//    becomes truly non-interactive?"
//
// Deliberately: no real Today/Practice/Progress content (that's #1021's
// scope), no persistence, no GameRootViewModel. Just enough shell to answer
// the B-4 question with idb-driven evidence.
//
// Two candidate mount strategies are wired side-by-side behind a runtime
// picker so both can be driven in one build:
//
// - `.naive`   — mirrors the CURRENT `BoardView` shape verbatim: the
//   pause/completion stand-in is mounted as an `.overlay {}` on the "board"
//   content itself, deep inside the pushed tab route — the same subtree
//   `RootShellView`'s `.disabled(isBoardModalOverlayActive)` would need to
//   spare. Tests whether a literal 1:1 port of the current fix survives the
//   TabView rewrite.
// - `.hoisted` — the candidate fix shape: the overlay stand-in is rendered
//   as a ZStack sibling of the TabView, OUTSIDE the subtree the
//   `.disabled(...)` modifier reaches, while the TabView itself (sidebar
//   rows + tab-switch chrome + tab content) is disabled as one unit.
//
// Both strategies read the SAME `BoardModalOverlayActivePreferenceKey` #763
// introduced, propagated up from the "board" stand-in exactly like a real
// board does today.

public import SwiftUI
public import GameShellUI

enum Spike1019OverlayKind: String {
    case pause
    case completion
}

enum Spike1019MountStrategy: String, CaseIterable, Identifiable {
    case naive
    case hoisted
    var id: String { rawValue }
}

/// Shared down-flow seam: the active board stand-in registers how to clear
/// its own local `isActive` state here so the HOISTED overlay (rendered
/// outside that subtree, with no direct binding to it) can still dismiss it.
/// Throwaway equivalent of "the board owns its own pause/terminal state."
@Observable
final class Spike1019OverlayCoordinator {
    var dismiss: (() -> Void)?
}

struct Spike1019RootView: View {
    enum SpikeTab: String, Hashable, CaseIterable {
        case today, practice, progress

        var title: String {
            switch self {
            case .today: return "Today"
            case .practice: return "Practice"
            case .progress: return "Progress"
            }
        }

        var systemImage: String {
            switch self {
            case .today: return "sun.max"
            case .practice: return "pencil"
            case .progress: return "chart.bar"
            }
        }
    }

    @State private var selection: SpikeTab = .today
    @State private var mountStrategy: Spike1019MountStrategy = .naive
    @State private var overlayKind: Spike1019OverlayKind = .pause
    @State private var coordinator = Spike1019OverlayCoordinator()
    // #763 mirror: this is PURELY a derived mirror of the child-published
    // preference — never set directly here, exactly like RootShellView's
    // `isBoardModalOverlayActive`.
    @State private var isBoardModalOverlayActive = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Picker("Mount strategy", selection: $mountStrategy) {
                    Text("Naive").tag(Spike1019MountStrategy.naive)
                    Text("Hoisted").tag(Spike1019MountStrategy.hoisted)
                }
                .pickerStyle(.segmented)
                .padding()
                .disabled(isBoardModalOverlayActive)
                .accessibilityIdentifier("spike.mountPicker")

                TabView(selection: $selection) {
                    ForEach(SpikeTab.allCases, id: \.self) { tab in
                        Tab(tab.title, systemImage: tab.systemImage, value: tab) {
                            NavigationStack {
                                Spike1019BoardStandIn(
                                    mountStrategy: mountStrategy,
                                    overlayKind: $overlayKind,
                                    coordinator: coordinator
                                )
                                .navigationTitle(tab.title)
                            }
                        }
                    }
                }
                .tabViewStyle(.sidebarAdaptable)
                .accessibilityIdentifier("spike.tabView")
                // #763: same preference key RootShellView observes today.
                .onPreferenceChange(BoardModalOverlayActivePreferenceKey.self) { active in
                    isBoardModalOverlayActive = active
                }
                // Candidate B-4 mask: disable the WHOLE TabView (sidebar rows
                // + tab-switch chrome + tab content) as one unit — there is
                // no user-authored sidebar `List` to target independently
                // once the sidebar is system-generated by `sidebarAdaptable`.
                .disabled(isBoardModalOverlayActive)
            }

            // HOISTED candidate fix: rendered as a ZStack sibling, OUTSIDE
            // the `.disabled(...)` scope above.
            if mountStrategy == .hoisted, isBoardModalOverlayActive {
                Spike1019OverlayStandIn(kind: overlayKind, idPrefix: "hoisted") {
                    coordinator.dismiss?()
                }
            }
        }
    }
}
