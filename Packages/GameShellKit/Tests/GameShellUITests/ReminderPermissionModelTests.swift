// ReminderPermissionModelTests — drives the #287 Phase 2 permission model with
// the shared `FakeNotificationAuthorizing` fake (no system center touched).
//
// Covers the proposal §5 flow contract: cold launch stays notDetermined,
// accepting the primer fires exactly one request and resolves the status,
// provisional flag propagates, and refresh re-reads a Settings change.

import Testing
@testable import GameShellUI
import Reminders
import RemindersTesting

@MainActor
@Suite("GameShellUI — ReminderPermissionModel")
struct ReminderPermissionModelTests {

    @Test func coldLaunch_staysNotDetermined_noRequest() async {
        let fake = FakeNotificationAuthorizing(status: .notDetermined)
        let model = ReminderPermissionModel(authorizer: fake)

        #expect(model.status == .notDetermined)
        // No primer accepted yet → no system prompt fired.
        let flags = await fake.requestedProvisionalFlags
        #expect(flags.isEmpty)
    }

    @Test func requestFromPrimer_firesOneExplicitRequest_resolvesAuthorized() async {
        let fake = FakeNotificationAuthorizing(status: .notDetermined)
        await fake.setResolvedStatus(.authorized)
        let model = ReminderPermissionModel(authorizer: fake)  // provisional: false (U1)

        let resolved = await model.requestFromPrimer()

        #expect(resolved == .authorized)
        #expect(model.status == .authorized)
        let flags = await fake.requestedProvisionalFlags
        #expect(flags == [false])  // exactly one, explicit (not provisional)
    }

    @Test func requestFromPrimer_resolvesDenied() async {
        let fake = FakeNotificationAuthorizing(status: .notDetermined)
        await fake.setResolvedStatus(.denied)
        let model = ReminderPermissionModel(authorizer: fake)

        let resolved = await model.requestFromPrimer()

        #expect(resolved == .denied)
        #expect(model.status == .denied)
    }

    @Test func provisionalFlag_propagatesToAuthorizer() async {
        let fake = FakeNotificationAuthorizing(status: .notDetermined)
        let model = ReminderPermissionModel(authorizer: fake, provisional: true)

        await model.requestFromPrimer()

        let flags = await fake.requestedProvisionalFlags
        #expect(flags == [true])
    }

    @Test func refreshStatus_readsSettingsChange() async {
        let fake = FakeNotificationAuthorizing(status: .denied)
        let model = ReminderPermissionModel(authorizer: fake, initialStatus: .denied)
        #expect(model.status == .denied)

        // Simulate the user flipping Allow on in Settings, then a foreground.
        await fake.setCurrentStatus(.authorized)
        await model.refreshStatus()

        #expect(model.status == .authorized)
    }
}
