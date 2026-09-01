// CompletionOverlayScaffoldTests — snapshots for the §3.5 CTA hierarchy (#1023,
// was #652's two-button Play-Again layout).
//
// #1023: the scaffold is now a full-height glass panel (no more opaque
// warm-paper background) driven by `variant`/`outcomeKind`/`context` instead
// of a raw `onPlayAgain` closure. This file's baselines ALL churn from the
// background removal — expected, see the dispatch's "snapshot churn" note.
// Pins the visual contract for all 4 §3.5 CTA-hierarchy rows.

#if canImport(AppKit)
import Foundation
import SnapshotTesting
import SwiftUI
import Testing
import GameShellUI
@testable import SudokuUI

@MainActor
@Suite("CompletionOverlayScaffold — §3.5 CTA hierarchy (#1023)")
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

    private func host(_ context: CompletionContext, outcomeKind: CompletionOutcome.Kind = .success) -> NSView {
        hostingView(
            // #1023: the panel-rise (M10) reveal is `.onAppear`-driven, same
            // limitation `CompletionScreen`'s hero reveal has — never fires on
            // an offscreen `NSHostingView` (see `completionHeroSkipsReveal`'s
            // doc comment). Without this the panel renders fully transparent
            // (opacity 0, the pre-reveal state) — a blank snapshot that looks
            // like the AssetCatalogCompiler plugin isn't attached, but isn't.
            CompletionOverlayScaffold(
                variant: .liveSolve,
                outcomeKind: outcomeKind,
                context: context,
                onClose: {},
                card: { sampleCard }
            )
            .environment(\.completionHeroSkipsReveal, true),
            size: SnapshotLayouts.iPhone,
            colorScheme: .light,
            sizeClass: .compact
        )
    }

    // MARK: - Snapshot: Practice, two-button (Play Again above Close)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_practice_playAgain_iPhoneLight() {
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(
                of: host(.practice(onPlayAgain: {})),
                as: .image,
                named: "CompletionOverlayScaffold-iPhone-light-practice-playAgain"
            )
        }
    }

    // MARK: - Snapshot: Daily, more today (Next: Medium above Done)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_dailyMoreToday_iPhoneLight() {
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(
                of: host(.dailyMoreToday(nextDifficultyLabel: "Medium", onNext: {})),
                as: .image,
                named: "CompletionOverlayScaffold-iPhone-light-dailyMoreToday"
            )
        }
    }

    // MARK: - Snapshot: Daily, all done (See you tomorrow, single button)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_dailyAllDone_iPhoneLight() {
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(
                of: host(.dailyAllDone),
                as: .image,
                named: "CompletionOverlayScaffold-iPhone-light-dailyAllDone"
            )
        }
    }

    // MARK: - Snapshot: loss, two-button (Try Again above Close)

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func snapshot_loss_tryAgain_iPhoneLight() {
        withSnapshotTesting(record: SnapshotMode.recordMode) {
            assertSnapshot(
                of: host(.loss(onTryAgain: {}), outcomeKind: .failure),
                as: .image,
                named: "CompletionOverlayScaffold-iPhone-light-loss-tryAgain"
            )
        }
    }
}
#endif
