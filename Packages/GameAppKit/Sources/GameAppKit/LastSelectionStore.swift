// LastSelectionStore — persists a single "last selected" String preference
// (#720 gap-fill: Sudoku + Minesweeper Practice difficulty both reset to a
// fixed default every launch instead of remembering the player's last pick).
//
// Sudoku's and Minesweeper's `Difficulty` enums are distinct types, so this
// seam is generalized over `String` (the enum's `rawValue`) rather than
// parameterized over a shared protocol — each call site encodes/decodes its
// own enum via `.rawValue` / `init?(rawValue:)`. Mirrors
// `MinesweeperWinCountStore`'s injectable-`UserDefaults` shape so tests never
// touch the real `UserDefaults.standard`.

public import Foundation

/// Not `Sendable`: `UserDefaults` is not `Sendable`. Call sites are all
/// `@MainActor` (composition-root wiring / SwiftUI view state), so this never
/// crosses an actor boundary — same reasoning as `MinesweeperWinCountStore`.
public struct LastSelectionStore {
    private let key: String
    private let fallback: String
    private let defaults: UserDefaults

    public init(key: String, fallback: String, defaults: UserDefaults = .standard) {
        self.key = key
        self.fallback = fallback
        self.defaults = defaults
    }

    /// Last-persisted value, or `fallback` if nothing has been stored yet.
    public func load() -> String {
        defaults.string(forKey: key) ?? fallback
    }

    /// Persists `value` as the new last-selected preference.
    public func save(_ value: String) {
        defaults.set(value, forKey: key)
    }
}
