// ReminderSettingsIdentityTests — issue #909.
//
// Bug: Settings → Reminders → "Daily reminder" primer sheet appeared then
// immediately dismissed on the FIRST tap after a cold launch. Root cause:
// `ReminderSettingsModel` was NOT cached — `GameDeps.makeReminderSettings`
// was a factory closure invoked fresh inside the `.settings` case of
// `LiveRouteFactory.view(for:path:)`, which SwiftUI re-runs on every
// `.navigationDestination` re-render (not just once per Settings mount). A
// concurrent bootstrap `.task` re-rendering an ancestor right after the user
// tapped "Daily reminder" replaced the just-flipped model (isPrimerPresented
// = true) with a BRAND NEW model (isPrimerPresented = false), so the sheet's
// `.sheet(isPresented: $model.isPrimerPresented)` binding read false and
// dismissed itself.
//
// Fix: `GameDeps.reminderSettings` / `LiveRouteFactory.reminderSettings` now
// hold a single, eagerly-built `ReminderSettingsEntry` value instead of a
// factory closure — every `.settings` render reuses the SAME
// `ReminderSettingsModel` instance.
//
// This test pins the fix's guarantee directly at `LiveRouteFactory`: TWO
// separate `view(for: .settings, path:)` calls on the same factory instance
// must surface the identical `ReminderSettingsModel` object. Digging the
// model out of the `AnyView` needs a recursive `Mirror` walk (AnyView
// type-erases its payload, and `SettingsView`'s `reminderSettings` field is
// `private`) — the same technique `RouteFactoryTests.underlyingTypeDescription`
// uses one level shallower (type-name fingerprinting); here we go one level
// further to compare object IDENTITY, not just type.

import Foundation
import SwiftUI
import Testing
import GameCenterClient
import GameCenterTesting
import MonetizationCore
import MonetizationTesting
import Persistence
import SudokuPersistence
import SudokuKitTesting
import Telemetry
import Reminders
import SettingsUI
@testable import SudokuAppComposition
@testable import SudokuUI

@MainActor
@Suite("LiveRouteFactory — Settings reminder-entry identity (#909)")
struct ReminderSettingsIdentityTests {

    /// Builds a real `ReminderSettingsEntry` over the `Reminders` Noop
    /// conformers — no system notification center touched. Mirrors
    /// `MinesweeperSettingsViewTests.settingsViewConstructsWithReminderSection`'s
    /// construction recipe.
    private func makeReminderSettingsEntry() -> ReminderSettingsEntry {
        let model = ReminderSettingsModel(
            permissionModel: ReminderPermissionModel(authorizer: NoopNotificationAuthorizing()),
            scheduler: NoopReminderScheduler(),
            kind: .dailyReady,
            content: ReminderContent(title: "t", body: "b"),
            getFireTime: { (hour: 9, minute: 0) },
            setFireTime: { _ in }
        )
        return ReminderSettingsEntry(
            model: model,
            copy: ReminderSettingsCopy(
                sectionTitle: "Reminders",
                enableTitle: "Daily reminder",
                enableCTA: "Turn On",
                enabledTitle: "Daily reminder",
                enabledStatus: "On",
                disableTitle: "Turn off reminders",
                timeTitle: "Time",
                deniedTitle: "Notifications are off",
                deniedCTA: "Fix"
            ),
            primerCopy: ReminderPrimerCopy(
                title: "t", lede: "l", bullets: ["b"],
                acceptCTA: "a", declineCTA: "d", fineprint: "f"
            ),
            deniedCopy: ReminderDeniedCopy(
                title: "t", message: "m", openSettingsCTA: "o",
                dismissCTA: "d", macOSGuidance: "g"
            )
        )
    }

    private func makeFactory(reminderSettings: ReminderSettingsEntry) -> LiveRouteFactory {
        let adGateStore = FakeAdGateStateStore(
            initial: AdGateState(firstLaunchAt: Date(timeIntervalSince1970: 0))
        )
        return LiveRouteFactory(
            puzzleProvider: FakePuzzleProvider(),
            persistence: FakePersistence(),
            gameCenter: FakeGameCenterClient(),
            telemetry: Telemetry(sinks: []),
            adProvider: FakeAdProvider(),
            iapClient: FakeIAPClient(),
            adGate: AdGate(store: adGateStore),
            reminderSettings: reminderSettings
        )
    }

    /// Recursively walks a `Mirror` tree looking for the first
    /// `ReminderSettingsModel` instance it can find — the only way to reach
    /// past `AnyView`'s type erasure and `SettingsView`'s `private` storage.
    private func findReminderModel(in value: Any, depth: Int = 0) -> ReminderSettingsModel? {
        if let model = value as? ReminderSettingsModel { return model }
        guard depth < 12 else { return nil }
        for child in Mirror(reflecting: value).children {
            if let found = findReminderModel(in: child.value, depth: depth + 1) {
                return found
            }
        }
        return nil
    }

    @Test func settingsRouteReusesTheSameReminderModelAcrossRepeatedRenders() throws {
        let entry = makeReminderSettingsEntry()
        let factory = makeFactory(reminderSettings: entry)

        // Two independent calls, exactly like SwiftUI re-invoking the
        // `.navigationDestination` builder closure on an unrelated ancestor
        // re-render (the #909 repro shape) — NOT a single render reused twice.
        let firstView = factory.view(for: .settings, path: nil)
        let secondView = factory.view(for: .settings, path: nil)

        let firstModel = try #require(
            findReminderModel(in: firstView),
            "Expected to find a ReminderSettingsModel inside the first .settings render"
        )
        let secondModel = try #require(
            findReminderModel(in: secondView),
            "Expected to find a ReminderSettingsModel inside the second .settings render"
        )

        // The #909 regression: a factory closure minted a FRESH model (with
        // isPrimerPresented reset to false) on every render. The fix's
        // guarantee is object identity across renders.
        #expect(firstModel === secondModel)
        // Sanity: both point back at the exact entry this test constructed.
        #expect(firstModel === entry.model)
    }

    /// Negative control for `findReminderModel`: two factories built from two
    /// DIFFERENT entries must resolve to DIFFERENT model instances — proving
    /// the recursive Mirror walk tracks the actual injected object instead of
    /// vacuously matching any `ReminderSettingsModel` it happens to see
    /// (which would make the positive test above pass unconditionally).
    @Test func differentFactoriesSurfaceDifferentReminderModels() throws {
        let entryA = makeReminderSettingsEntry()
        let entryB = makeReminderSettingsEntry()
        #expect(entryA.model !== entryB.model)

        let viewA = makeFactory(reminderSettings: entryA).view(for: .settings, path: nil)
        let viewB = makeFactory(reminderSettings: entryB).view(for: .settings, path: nil)

        let modelA = try #require(findReminderModel(in: viewA))
        let modelB = try #require(findReminderModel(in: viewB))
        #expect(modelA === entryA.model)
        #expect(modelB === entryB.model)
        #expect(modelA !== modelB)
    }
}
