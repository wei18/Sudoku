// ReminderSettingsStore — the persisted daily-ready fire time (#287 Phase 2).
//
// The #321 seam: the Settings fire-time picker will bind to this exact store.
// This file ships ONLY the persisted value + a sane 9:00 AM local default — NOT
// the picker UI (that is #321).
//
// Storage choice: `UserDefaults` (device-local), not the CloudKit `Persistence`
// stack Settings uses for game records. A notification fire time is a per-device
// preference (the OS schedules locally), so syncing it across devices via
// CloudKit would be wrong — a reminder fires on the device that scheduled it.
// This matches the "match the existing pattern" instruction by picking the
// Apple-idiomatic home for a local pref; Sudoku has no prior local-prefs store,
// so this is the first.

public import Foundation

/// The hour+minute (local time) the daily-ready reminder should fire. Defaults
/// to 9:00 AM. `Sendable` value type; the store reads/writes it from `UserDefaults`.
public struct ReminderFireTime: Sendable, Equatable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    /// Spec default: 9:00 AM local (proposal §5; design S05/S09 "9:00 AM").
    public static let defaultDailyReady = ReminderFireTime(hour: 9, minute: 0)
}

/// `UserDefaults`-backed persistence for the daily-ready fire time. Constructed
/// with the standard suite by default; tests inject an ephemeral suite.
///
/// Not `Sendable`: `UserDefaults` is not `Sendable`, and this value is only ever
/// touched on `@MainActor` (the coordinator + #321's Settings picker), so it
/// never crosses an actor boundary. (Same reasoning as the MainActor-only copy
/// value types in GameShellUI.)
public struct ReminderSettingsStore {

    // Namespaced keys (oslog-logger-defaults bundle-id convention extended to
    // defaults keys). #321's picker writes through `dailyReadyFireTime`.
    private static let hourKey = "com.wei18.sudoku.reminder.dailyReadyHour"
    private static let minuteKey = "com.wei18.sudoku.reminder.dailyReadyMinute"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The persisted daily-ready fire time, defaulting to 9:00 AM when unset.
    /// `UserDefaults.integer(forKey:)` returns 0 for a missing key, which is
    /// indistinguishable from a real `0` (midnight); we gate on key presence so
    /// "no value yet" yields the 9 AM default rather than midnight.
    public var dailyReadyFireTime: ReminderFireTime {
        get {
            guard defaults.object(forKey: Self.hourKey) != nil else {
                return .defaultDailyReady
            }
            return ReminderFireTime(
                hour: defaults.integer(forKey: Self.hourKey),
                minute: defaults.integer(forKey: Self.minuteKey)
            )
        }
        nonmutating set {
            defaults.set(newValue.hour, forKey: Self.hourKey)
            defaults.set(newValue.minute, forKey: Self.minuteKey)
        }
    }
}
