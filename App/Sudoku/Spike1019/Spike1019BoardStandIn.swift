// Spike1019BoardStandIn — THROWAWAY. See Spike1019RootView.swift for
// context. Stands in for BoardView: owns its own local pause/completion
// @State (mirroring a real board's GameViewModel), publishes
// `BoardModalOverlayActivePreferenceKey` with the same condition that drives
// its own overlay visibility (per that key's doc comment), and — for the
// `.naive` mount strategy only — mounts the overlay stand-in directly on
// itself via `.overlay {}`, exactly like `BoardView.swift` /
// `MinesweeperBoardView.swift` do today.

public import SwiftUI
public import GameShellUI

struct Spike1019BoardStandIn: View {
    let mountStrategy: Spike1019MountStrategy
    @Binding var overlayKind: Spike1019OverlayKind
    let coordinator: Spike1019OverlayCoordinator

    @State private var isActive = false

    var body: some View {
        VStack(spacing: 16) {
            Text("Board placeholder — #1019 spike")
                .font(.headline)
            Text("No real board content — scope is B-4 only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Trigger Pause") {
                overlayKind = .pause
                activate()
            }
            .accessibilityIdentifier("spike.triggerPause")
            Button("Trigger Completion") {
                overlayKind = .completion
                activate()
            }
            .accessibilityIdentifier("spike.triggerCompletion")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            // NAIVE mount point: mirrors BoardView's `.overlay {}` — same
            // subtree the ancestor TabView's `.disabled(...)` reaches.
            if mountStrategy == .naive, isActive {
                Spike1019OverlayStandIn(kind: overlayKind, idPrefix: "naive") {
                    isActive = false
                }
            }
        }
        // #763: publish with the SAME condition driving this board's own
        // overlay, exactly like BoardModalOverlayActivePreferenceKey's doc
        // comment prescribes.
        .preference(key: BoardModalOverlayActivePreferenceKey.self, value: isActive)
    }

    private func activate() {
        isActive = true
        // Register the down-flow dismiss seam for the HOISTED strategy's
        // overlay (rendered outside this subtree, no direct binding to
        // `isActive`).
        coordinator.dismiss = { isActive = false }
    }
}
