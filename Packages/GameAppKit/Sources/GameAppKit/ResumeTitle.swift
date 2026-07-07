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

    /// `%d:%02d` elapsed label for the resume pill subtitle (e.g. `"3:21"` for
    /// 201 seconds). Hoisted from byte-identical `elapsed` implementations that
    /// used to live separately in Sudoku's and Minesweeper's app composition
    /// (#710) so both apps share one implementation.
    public static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
