// MinesweeperWinCountStore — device-local cumulative win tally (#700).
//
// Backs the "Volume" achievements (Sweeper/Veteran/Master), which count wins
// across BOTH modes combined. This is intentionally a plain `UserDefaults`
// counter, not a CloudKit record: it only needs to survive app relaunch on
// THIS device, never sync across devices (a GC-reported achievement already
// carries its own server-side state; a slightly-under-counted tally after a
// reinstall just means the achievement re-crosses its threshold a bit later,
// which is an acceptable trade-off for the ~1-line implementation).
//
// Key namespace mirrors `ReminderSettingsStore`'s bundle-id-rooted convention
// (`com.wei18.sudoku.reminder.*`), scoped to Minesweeper.

public import Foundation

/// Not `Sendable`: `UserDefaults` is not `Sendable`, and this value is only
/// ever touched on `@MainActor` (via `MinesweeperGameViewModel`), so it never
/// crosses an actor boundary — same reasoning as `ReminderSettingsStore`.
public struct MinesweeperWinCountStore {

    private static let cumulativeWinCountDefaultsIdentifier = "com.wei18.minesweeper.achievement.cumulativeWinCount"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Current cumulative win count (both modes combined), 0 if never won.
    public var currentCount: Int {
        defaults.integer(forKey: Self.cumulativeWinCountDefaultsIdentifier)
    }

    /// Increments the tally by one and returns the new total, INCLUDING this win.
    public func incrementAndGet() -> Int {
        let next = currentCount + 1
        defaults.set(next, forKey: Self.cumulativeWinCountDefaultsIdentifier)
        return next
    }
}
