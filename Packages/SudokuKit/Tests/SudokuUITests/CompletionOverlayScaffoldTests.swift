// CompletionOverlayScaffoldTests — snapshot for the two-button Play-Again layout (#652).
//
// Pins the visual contract: when onPlayAgain is wired, CompletionOverlayScaffold
// renders "Play Again" (borderedProminent) ABOVE "Close" (bordered). The existing
// CompletionViewTests baselines cover the Close-only (nil onPlayAgain) path; this
// file covers the two-button path exclusively. No existing baselines are touched.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import GameShellUI
@testable import SudokuUI

@MainActor
@Suite("CompletionOverlayScaffold — Play Again two-button layout (#652)")
struct CompletionOverlayScaffoldTests {

    // Minimal card: the scaffold's job is the button layout, not the card content.
    private var sampleCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(.green)
            Text("Solved!")
                .font(.title.bold())
            Text("4:11")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(32)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial, in: .rect(cornerRadius: 20))
        .padding(.horizontal, 24)
    }

    // MARK: - Snapshot: two-button (Play Again above Close)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_playAgain_iPhoneLight() {
        let host = hostingView(
            CompletionOverlayScaffold(
                onClose: {},
                onPlayAgain: {},
                card: { sampleCard }
            ),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(
                of: host,
                as: .image,
                named: "CompletionOverlayScaffold-iPhone-light-playAgain"
            )
        }
    }
}
#endif
