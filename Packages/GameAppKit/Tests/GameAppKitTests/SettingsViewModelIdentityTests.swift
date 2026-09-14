// SettingsViewModelIdentityTests — pins the #1058 phase 2f contract: `SettingsView`
// owns its `SettingsViewModel` as `@State`, so an ancestor re-render that mints
// a fresh model cannot replace the instance whose one-shot
// `.task { bootstrap() }` already ran.
//
// Both LiveRouteFactories build `SettingsViewModel(...)` inline inside the
// `.settings` `navigationDestination` builder, which SwiftUI re-invokes on any
// ancestor re-render (the #909 shape). `GameRoot` gained a `scenePhase`
// dependency in this PR, so every scene-phase change is such a re-render; with
// a plain stored property the freshly minted model (`isCacheStateReady ==
// false`, `.task` does not re-fire) replaced the bootstrapped one and the
// Settings "cache ready" anchor never appeared (Minesweeper E2E N19, #1078).
//
// Identity is observed through what the model renders: the Version row shows
// `appVersion`, so model "A" is minted on the first builder call and "B" on
// every later one. After the re-render the host must still paint "A". The
// private property itself is unreachable without a production hook.

#if canImport(AppKit)
import AppKit
import Foundation
import SwiftUI
import Testing
import Persistence
import SudokuEngine
import SudokuGameState
@testable import GameAppKit

private actor IdentityStubPersistence: PersistenceProtocol {
    func bootstrap() async throws {}
    func latestInProgress() async throws -> SavedGameSummary? { nil }
    func loadOrCreate(
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws -> GameSessionSnapshot {
        throw PersistenceError.zoneNotProvisioned
    }
    func save(
        _ snapshot: GameSessionSnapshot,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty
    ) async throws {}
    func markCompleted(_ summary: SavedGameSummary) async throws {}
    func deleteAbandoned(recordName: String) async throws {}
    func fetchCompletedDailyIds(for date: Date) async throws -> Set<String> { [] }
    func fetchCompletedDailyIdsByDay() async throws -> [String: Set<String>] { [:] }
    func fetchPersonalRecord(mode: Mode, difficulty: Difficulty) async throws -> PersonalRecord {
        PersonalRecord(
            recordName: "",
            mode: .daily,
            difficulty: .easy,
            bestTimeSeconds: nil,
            totalTimeSeconds: 0,
            completedCount: 0,
            lastUpdatedAt: Date(timeIntervalSince1970: 0),
            completedPuzzleIds: []
        )
    }
    func upsertPersonalRecord(_ record: PersonalRecord) async throws {}
}

@Observable
@MainActor
private final class RenderTick {
    var value = 0
}

/// Mints a fresh model on EVERY body evaluation, exactly like the `.settings`
/// destination builder in both LiveRouteFactories.
private struct MintingAncestor: View {
    let tick: RenderTick
    let mint: @MainActor () -> SettingsViewModel

    var body: some View {
        // Observable dependency: bumping `value` re-evaluates this body. Only a
        // `let` declaration bypasses the `ViewBuilder` transform (`_ = …` is an
        // expression statement the builder rejects) — same idiom as
        // `BoardModalOverlayHoistTests`.
        // swiftlint:disable:next redundant_discardable_let
        let _ = tick.value
        SettingsView(viewModel: mint())
    }
}

@MainActor
private struct Harness {
    let tick = RenderTick()
    let window: NSWindow
    let host: NSHostingView<MintingAncestor>
    /// `versions[0]` labels the first minted model; the last entry labels every
    /// later one.
    init(versions: [String]) {
        let box = MintBox(versions: versions)
        let tick = self.tick
        host = NSHostingView(rootView: MintingAncestor(tick: tick, mint: { box.mint() }))
        host.frame = NSRect(x: 0, y: 0, width: 402, height: 800)
        window = NSWindow(
            contentRect: host.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.contentView = host
        mintBox = box
    }

    private let mintBox: MintBox

    var mintCount: Int { mintBox.minted.count }
    var firstModel: SettingsViewModel? { mintBox.minted.first }

    func rerender() {
        tick.value += 1
        host.layoutSubtreeIfNeeded()
    }

    func pixels() -> Data {
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return Data() }
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.tiffRepresentation ?? Data()
    }
}

@MainActor
private final class MintBox {
    let versions: [String]
    private(set) var minted: [SettingsViewModel] = []

    init(versions: [String]) { self.versions = versions }

    func mint() -> SettingsViewModel {
        let label = minted.isEmpty ? versions[0] : versions[versions.count - 1]
        let model = SettingsViewModel(appVersion: label, persistence: IdentityStubPersistence())
        minted.append(model)
        return model
    }
}

@MainActor
private func settle(_ harness: Harness) async {
    // If the hosted `.task` fires, let the first model's bootstrap land before
    // the first capture so both captures are post-bootstrap. Bounded; the
    // anchor it toggles paints no pixels either way.
    let deadline = ContinuousClock.now.advanced(by: .seconds(1))
    while harness.firstModel?.isCacheStateReady != true, ContinuousClock.now < deadline {
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("SettingsView — model identity survives ancestor re-renders (#1058 2f)")
@MainActor
struct SettingsViewModelIdentityTests {

    @Test("an ancestor re-render that mints a new model keeps rendering the first one")
    func firstModelSurvivesAncestorRerender() async {
        let harness = Harness(versions: ["1.0.0-A", "9.9.9-B"])
        await settle(harness)
        let before = harness.pixels()
        #expect(harness.mintCount == 1)

        harness.rerender()
        await settle(harness)
        let after = harness.pixels()

        #expect(harness.mintCount >= 2, "the ancestor body must have minted a second model")
        #expect(!before.isEmpty)
        #expect(after == before, "the Version row must still show model A's text")
    }

    @Test("the compare is not vacuous: a host that starts on model B renders differently")
    func differentModelRendersDifferently() async {
        let harnessA = Harness(versions: ["1.0.0-A"])
        let harnessB = Harness(versions: ["9.9.9-B"])
        await settle(harnessA)
        await settle(harnessB)
        let pixelsA = harnessA.pixels()
        let pixelsB = harnessB.pixels()
        #expect(!pixelsA.isEmpty)
        #expect(pixelsA != pixelsB)
    }
}
#endif
