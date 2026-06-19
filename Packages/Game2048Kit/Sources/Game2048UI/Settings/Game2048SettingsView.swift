// Game2048SettingsView — Tiles2048 Settings.
//
// Mirrors MinesweeperKit/SettingsView. Wraps `GameShellUI.SettingsScreen`
// (shared grouped-Form chrome). Mounts the shared `RemoveAdsRow` /
// `AdsRemovedRow` / `RestorePurchasesRow` under a `Section("Purchases")`.
// Game Center entry row mirrors the #492-merged pattern.
//
// Banner is injected by LiveRouteFactory (Epic 5 pattern; SettingsKit /
// GameShellUI must NOT import MonetizationUI).
//
// #479: `reminderSettings` + `audioSettings` added (from GameDeps via
// LiveRouteFactory) so the Settings screen shows the Sound + Reminders
// sections. Defaulted nil so previews / tests keep the byte-identical
// screen without those sections.

public import SwiftUI
public import MonetizationUI
public import SettingsUI
// #560: shared `GameCenterDashboard.present()` (was the per-app copy).
internal import GameCenterClient

public struct Game2048SettingsView<Banner: View>: View {
    private let version: String
    private let clearCache: @MainActor () async -> Void
    private let monetizationController: MonetizationStateController?
    // #479: shared Reminders entry (enable / prime permission / fire-time).
    // Defaulted nil so previews / tests mount a byte-identical screen without
    // the section; the host (LiveRouteFactory) injects one wired to RemindersKit Live.
    private let reminderSettings: ReminderSettingsEntry?
    // #479: shared Sound section model (mute / volumes / BGM / haptics).
    // Defaulted nil so previews / tests keep the byte-identical screen without
    // the section; the host (LiveRouteFactory) injects the live-player-backed model.
    private let audioSettings: AudioSettingsModel?
    private let notices: SettingsNoticesConfig?
    private let banner: Banner

    public init(
        version: String = "1.0.0",
        clearCache: @escaping @MainActor () async -> Void = {},
        monetizationController: MonetizationStateController? = nil,
        reminderSettings: ReminderSettingsEntry? = nil,
        audioSettings: AudioSettingsModel? = nil,
        notices: SettingsNoticesConfig? = nil,
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.version = version
        self.clearCache = clearCache
        self.monetizationController = monetizationController
        self.reminderSettings = reminderSettings
        self.audioSettings = audioSettings
        self.notices = notices
        self.banner = banner()
    }

    public var body: some View {
        SettingsScreen(
            version: version,
            tint: .accentColor,
            clearCache: clearCache,
            reminderSettings: reminderSettings.map {
                // #479: same building block MS mounts; map the entry into
                // the shell's config. Direct pass-through since
                // ReminderSettingsEntry == SettingsScreenReminderConfig fields.
                SettingsScreenReminderConfig(
                    model: $0.model,
                    copy: $0.copy,
                    primerCopy: $0.primerCopy,
                    deniedCopy: $0.deniedCopy
                )
            },
            audioSettings: audioSettings,
            notices: notices,
            // Game Center entry: present native GC dashboard (#492 pattern).
            onGameCenter: { GameCenterDashboard.present() },
            purchases: {
                if let controller = monetizationController {
                    Section("Purchases") {
                        if controller.hasPurchasedRemoveAds {
                            AdsRemovedRow(tintColor: .accentColor)
                        } else {
                            RemoveAdsRow(
                                controller: controller,
                                tintColor: .accentColor
                            )
                        }
                        RestorePurchasesRow(
                            controller: controller,
                            tintColor: .accentColor
                        )
                    }
                }
            },
            banner: { self.banner }
        )
        .task {
            if let controller = monetizationController {
                await controller.bootstrap()
            }
        }
    }
}

#Preview {
    NavigationStack {
        Game2048SettingsView()
    }
}
