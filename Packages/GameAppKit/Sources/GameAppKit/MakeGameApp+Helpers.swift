// MakeGameApp+Helpers — boot + audio helpers for `makeGameApp` (#556).
//
// Split out of `MakeGameApp.swift` to keep that file under the 400-line gate.

internal import Foundation
internal import Telemetry
internal import MonetizationCore
internal import MonetizationUI
internal import AdsAdMob
internal import IAPStoreKit2
internal import GameAudio
internal import SettingsUI

// MARK: - bootMonetization

/// App-launch monetization boot. Runs UMP consent → AdMob SDK initialize.
/// iOS-only: AdMob / UMP are iOS xcframeworks. On macOS returns immediately.
func bootMonetization(adProvider: any AdProvider, telemetry: Telemetry) async {
    #if !os(iOS)
    return
    #else
    let bridges = MonetizationBootBridges.live(adProvider: adProvider)
    let telemetryHandle = telemetry
    let coordinator = MonetizationBootCoordinator(
        bridges: bridges,
        log: { outcome in
            if !outcome.succeeded {
                Task {
                    await telemetryHandle.observe(
                        .errorOccurred(
                            source: "MonetizationBoot",
                            code: outcome.step.rawValue,
                            message: outcome.errorDescription ?? "unknown"
                        )
                    )
                }
            } else {
                Task {
                    await telemetryHandle.observe(
                        .bootStepSucceeded(source: "MonetizationBoot", step: outcome.step.rawValue)
                    )
                }
            }
        }
    )
    await coordinator.boot()
    #endif
}

// MARK: - Audio settings helper

/// Builds an `AudioSettingsModel` backed by `UserDefaults.standard` under
/// `keyPrefix.*` keys. Defaults match the spec: BGM on, haptics on, not muted,
/// volumes 0.7. Each setter fans out to the injected `player`.
@MainActor
func makeAudioSettings(player: any SoundPlaying, keyPrefix: String) -> AudioSettingsModel {
    let defaults = UserDefaults.standard
    let musicVolumeKey = "\(keyPrefix).musicVolume"
    let sfxVolumeKey = "\(keyPrefix).sfxVolume"
    let mutedKey = "\(keyPrefix).isMuted"
    let hapticsKey = "\(keyPrefix).hapticsEnabled"
    let musicEnabledKey = "\(keyPrefix).musicEnabled"

    func volume(_ key: String) -> Double {
        defaults.object(forKey: key) == nil ? 0.7 : defaults.double(forKey: key)
    }
    func flag(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) == nil ? fallback : defaults.bool(forKey: key)
    }

    return AudioSettingsModel(
        player: player,
        getMusicVolume: { volume(musicVolumeKey) },
        setMusicVolume: { defaults.set($0, forKey: musicVolumeKey) },
        getSFXVolume: { volume(sfxVolumeKey) },
        setSFXVolume: { defaults.set($0, forKey: sfxVolumeKey) },
        getIsMuted: { flag(mutedKey, default: false) },
        setMuted: { defaults.set($0, forKey: mutedKey) },
        getHapticsEnabled: { flag(hapticsKey, default: true) },
        setHapticsEnabled: { defaults.set($0, forKey: hapticsKey) },
        getMusicEnabled: { flag(musicEnabledKey, default: true) },
        setMusicEnabled: { defaults.set($0, forKey: musicEnabledKey) }
    )
}

// MARK: - ATT primer helper

/// Builds the `ATTPrimerCoordinator` used by `makeGameApp`. #935 batch 5:
/// routes both touch points through `resolveATTIsNotDetermined` /
/// `resolveATTRequestSystemPrompt` (MakeGameApp+UITestOverrides.swift) so
/// `-uitest-att-primer` can force a deterministic `.notDetermined` primer
/// presentation for the N15 negative-flow E2E test — every other launch
/// gets the real `ATTPresenter` touch points unchanged.
@MainActor
func makeATTPrimerCoordinator() -> ATTPrimerCoordinator {
    ATTPrimerCoordinator(
        isNotDetermined: resolveATTIsNotDetermined(fallback: {
            await ATTPresenter.currentStatus() == .notDetermined
        }),
        requestSystemPrompt: resolveATTRequestSystemPrompt(fallback: {
            _ = await ATTPresenter.requestIfNeeded()
        })
    )
}

// MARK: - IAP client helper

/// Builds the `IAPClient` used by `makeGameApp`. #935 batch 5: routes
/// through `resolveIAPClient` (MakeGameApp+UITestOverrides.swift) so
/// `-uitest-iap-script` can swap in a scripted fake for the N22
/// cancel/fail/pending negative flow — every other launch gets the real
/// `LiveStoreKit2IAPClient` unchanged.
@MainActor
func makeIAPClient(removeAdsProductId: String, telemetry: Telemetry) -> any IAPClient {
    resolveIAPClient(makeLive: LiveStoreKit2IAPClient(
        knownProductIds: [removeAdsProductId],
        onCatalogDesync: { [telemetry] productId in
            Task {
                await telemetry.observe(
                    .errorOccurred(
                        source: "LiveStoreKit2IAPClient",
                        code: "catalog_desync_post_purchase",
                        message: "post-purchase refetch returned empty for productId=\(productId)"
                    )
                )
            }
        }
    ))
}

// MARK: - Reminder persistence helper

/// The `UserDefaults`-backed persistence seams the shared Settings reminder
/// entry (#287) needs, rooted under `subsystem` so Sudoku/Minesweeper never
/// collide. Grouped into one type so `makeGameApp` wires one value instead of
/// four loose closures.
struct ReminderPersistence {
    let getFireTime: () -> (hour: Int, minute: Int)
    let setFireTime: (_ hour: Int, _ minute: Int) -> Void
    /// Whether the daily-ready reminder is currently scheduled — distinct
    /// from OS authorization (#817: `ReminderSettingsModel.disable()` needs
    /// this so the OFF affordance's effect survives relaunch; the OS
    /// authorization status alone can't represent "authorized but the user
    /// turned in-app scheduling off"). Tri-state: a missing key reads `nil`,
    /// which tells `ReminderSettingsModel.onAppear()` to seed the flag once
    /// from scheduler ground truth (`hasPending(kind:)`) and persist it —
    /// installs that tapped the pre-#817 "Turn off reminders" genuinely
    /// cancelled their notification with nowhere to record it, so a blind
    /// `true` default would show them "On" while reality is off.
    let getIsScheduled: () -> Bool?
    let setIsScheduled: (Bool) -> Void
}

/// Builds `ReminderPersistence` over `UserDefaults.standard`. Fire time
/// defaults to 9:00 AM local when unset; keys match each game's prior store
/// (`<subsystem>.reminder.dailyReady{Hour,Minute}`) so persisted values +
/// scheduled reminders carry over byte-identically. Device-local pref — the
/// OS schedules locally so none of this is CloudKit-synced.
func makeReminderPersistence(subsystem: String) -> ReminderPersistence {
    let defaults = UserDefaults.standard
    let fireTimeHourKey = "\(subsystem).reminder.dailyReadyHour"
    let fireTimeMinuteKey = "\(subsystem).reminder.dailyReadyMinute"
    let isScheduledKey = "\(subsystem).reminder.dailyReadyScheduled"

    return ReminderPersistence(
        getFireTime: {
            guard defaults.object(forKey: fireTimeHourKey) != nil else {
                return (hour: 9, minute: 0)
            }
            return (
                hour: defaults.integer(forKey: fireTimeHourKey),
                minute: defaults.integer(forKey: fireTimeMinuteKey)
            )
        },
        setFireTime: { hour, minute in
            defaults.set(hour, forKey: fireTimeHourKey)
            defaults.set(minute, forKey: fireTimeMinuteKey)
        },
        getIsScheduled: {
            guard defaults.object(forKey: isScheduledKey) != nil else { return nil }
            return defaults.bool(forKey: isScheduledKey)
        },
        setIsScheduled: { scheduled in
            defaults.set(scheduled, forKey: isScheduledKey)
        }
    )
}
