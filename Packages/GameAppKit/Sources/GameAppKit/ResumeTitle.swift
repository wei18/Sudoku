// ResumeTitle — builds the localized "Resume <difficulty>" pill title (#623
// follow-up).
//
// `ResumePill` renders a plain `String` title; each game's `fetchResume` mapping
// builds it. That used to be a raw `"Resume \(difficulty.rawValue.capitalized)"`
// interpolation, so BOTH the "Resume" prefix and the difficulty name stayed
// English in every non-en locale. This composes the title from two app-catalog
// keys — the difficulty name (e.g. "Easy" / "Beginner", already localized for the
// hubs) and a `"Resume %@"` format — resolved against `Bundle.main`, the app
// bundle that owns the catalog. Game-agnostic: callers pass the capitalized
// difficulty key string, so Sudoku and Minesweeper share one implementation.
//
// Each lookup passes the key itself as the `value:` fallback, so a missing catalog
// entry (e.g. snapshot/preview running in a bundle without the strings) degrades
// to the English key text — keeping `"Resume Easy"` rendering byte-stable.

internal import Foundation

public enum ResumeTitle {
    /// Localized "Resume <difficulty>". `difficultyKey` is the capitalized
    /// difficulty name used as a catalog key (e.g. `"Easy"`, `"Beginner"`).
    public static func make(difficultyKey: String) -> String {
        let name = Bundle.main.localizedString(
            forKey: difficultyKey, value: difficultyKey, table: nil
        )
        let format = Bundle.main.localizedString(
            forKey: "Resume %@", value: "Resume %@", table: nil
        )
        return String(format: format, name)
    }
}
