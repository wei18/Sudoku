// NavigationPreferencePropagationTests — #763's load-bearing assumption,
// verified live.
//
// The #763 fix rests on ONE SwiftUI behavior: a `.preference(...)` set by a
// view pushed via `.navigationDestination(for:)` propagates up through the
// `NavigationStack` to an ancestor's `.onPreferenceChange` (that is exactly
// how a board's overlay-active flag reaches `RootShellView`'s sidebar mask).
// SwiftUI has known preference-propagation quirks around presentation
// boundaries, so this suite exercises the real pipeline instead of assuming:
// an NSWindow-hosted `NavigationStack` (the #209 harness — a bare
// NSHostingView never runs the full window-backed layout pass) pushes a
// minimal emitter view by driving the path binding, and the test pumps the
// main run loop until the ancestor's `.onPreferenceChange` observes the flip
// to `true` — and back to `false` when the path pops (preferences from
// removed views revert to `defaultValue`, which is what auto-clears the
// sidebar mask when the board leaves the screen).

#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing
@testable import SudokuUI
import GameShellUI

// MARK: - Fixtures (file-scope: SwiftLint `nesting` — types ≤1 level deep)

/// Thread-safe recording box. `.onPreferenceChange`'s closure is `@Sendable`
/// (macOS 15+ SDK), so the box must be Sendable; a lock keeps it honest.
private final class PreferenceRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Bool] = []

    func record(_ value: Bool) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    var last: Bool? {
        lock.lock()
        defer { lock.unlock() }
        return values.last
    }
}

/// Path storage the test mutates; `@Observable` so mutating `path` actually
/// invalidates the mounted harness view (a plain external Binding would not).
@Observable
@MainActor
private final class PathModel {
    var path: [Int] = []
}

/// Ancestor-with-pushed-child shape mirroring the production wiring:
/// `RootShellView.onPreferenceChange` sits above the `NavigationStack` whose
/// `navigationDestination` hosts the preference-publishing board.
private struct PropagationHarness: View {
    @Bindable var model: PathModel
    let recorder: PreferenceRecorder

    var body: some View {
        NavigationStack(path: $model.path) {
            Text("root")
                .navigationDestination(for: Int.self) { _ in
                    // Minimal stand-in for a board with its overlay up.
                    Text("pushed")
                        .preference(key: BoardModalOverlayActivePreferenceKey.self, value: true)
                }
        }
        .onPreferenceChange(BoardModalOverlayActivePreferenceKey.self) { value in
            recorder.record(value)
        }
    }
}

// MARK: - Suite

@MainActor
@Suite("BoardModalOverlayActivePreferenceKey — propagation through navigationDestination (#763)")
struct NavigationPreferencePropagationTests {

    /// Pump the main run loop until `condition` holds or `timeout` elapses.
    /// Preference delivery happens in SwiftUI's commit phase, which needs run
    /// loop turns after the path mutation — same recursive-run pattern as
    /// XCTest's classic `RunLoop.run(until:)` waits.
    private func pump(timeout: TimeInterval = 3.0, until condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }

    @Test(.enabled(if: !SnapshotEnv.isXcodeCloud))
    func pushedDestinationPreferenceReachesAncestorAndClearsOnPop() {
        let model = PathModel()
        let recorder = PreferenceRecorder()
        let (_, window) = windowSnapshotView(
            PropagationHarness(model: model, recorder: recorder),
            size: SnapshotLayouts.mac,
            colorScheme: .light,
            sizeClass: .regular
        )
        defer { window.close() }

        // Initial commit: no push, so the ancestor must observe the default.
        pump { recorder.last != nil }
        #expect(recorder.last == false,
                "initial commit must deliver the preference's defaultValue (false) to the ancestor")

        // Drive the push exactly like production does (path mutation).
        model.path = [1]
        pump { recorder.last == true }
        #expect(recorder.last == true,
                "a pushed navigationDestination's .preference(value: true) must reach the ancestor's .onPreferenceChange — the #763 sidebar mask depends on it")

        // Pop: the emitter unmounts, so the preference must revert to the
        // default — this is what auto-clears the macOS sidebar mask.
        model.path = []
        pump { recorder.last == false }
        #expect(recorder.last == false,
                "popping the destination must revert the ancestor-observed value to false")
    }
}
#endif
