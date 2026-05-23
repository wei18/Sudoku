// SubmitGuards — the three Daily-only / first-time / same-UTC-day rules
// gating GameCenter score submission (docs/v1/design.md §How.3.1 + §How.3.3 Sink
// pseudocode).
//
// Rules enforced:
// 1. Practice puzzles never submit. Practice puzzleIds start with
//    `"practice-"` (see PuzzleStore.PuzzleIdentity); the prefix detection
//    is duplicated here intentionally rather than depending on the
//    PuzzleStore target — GameCenterClient sits at the same layer as
//    PuzzleStore and Persistence in the dependency graph, and pulling
//    PuzzleStore in would invert the direction (PuzzleStore would no
//    longer be reusable in isolation by SudokuUI's leaf views).
// 2. Same puzzleId never submits twice. Caller seeds `completedDailyPuzzleIds`
//    from Persistence.fetchCompletedDailyIds(for:) on launch; subsequent
//    completions append via `markSubmitted`.
// 3. Cross-day completions never submit. Apple GameKit always writes to
//    the *currently active* daily occurrence; if a player completed
//    today's puzzle after UTC rollover the score would mis-rank into
//    tomorrow's leaderboard. The actor parses the leading `YYYY-MM-DD`
//    from the daily puzzleId and compares to the current UTC day.

public import Foundation

public actor SubmitGuards: Sendable {

    private var completedDailyPuzzleIds: Set<String>
    private let clock: @Sendable () -> Date

    public init(
        seedCompletedIds: Set<String> = [],
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.completedDailyPuzzleIds = seedCompletedIds
        self.clock = clock
    }

    public func shouldSubmit(puzzleId: String) -> Bool {
        // Rule 1: Practice puzzles never submit.
        if isPracticePuzzleId(puzzleId) { return false }
        // Rule 2: dedup.
        if completedDailyPuzzleIds.contains(puzzleId) { return false }
        // Rule 3: cross-day check.
        guard let puzzleDay = Self.extractDailyDay(from: puzzleId) else {
            return false
        }
        let today = Self.utcDayString(from: clock())
        return puzzleDay == today
    }

    public func markSubmitted(puzzleId: String) {
        completedDailyPuzzleIds.insert(puzzleId)
    }

    public func snapshotCompletedIds() -> Set<String> {
        completedDailyPuzzleIds
    }

    // MARK: - Helpers

    private func isPracticePuzzleId(_ puzzleId: String) -> Bool {
        puzzleId.hasPrefix("practice-")
    }

    /// Extract the leading `YYYY-MM-DD` segment of a daily puzzleId.
    /// Returns nil if the id doesn't match the daily shape (e.g. practice).
    static func extractDailyDay(from puzzleId: String) -> String? {
        // Daily shape: "YYYY-MM-DD-easy" / "...-medium" / "...-hard".
        // Practice shape: "practice-<base32>-<difficulty>".
        guard !puzzleId.hasPrefix("practice-") else { return nil }
        let parts = puzzleId.split(separator: "-")
        // Need at least 4 dash-separated pieces: YYYY, MM, DD, <difficulty>.
        guard parts.count >= 4 else { return nil }
        let day = "\(parts[0])-\(parts[1])-\(parts[2])"
        // Cheap shape sanity (4-2-2 digits).
        guard parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              parts[0].allSatisfy(\.isNumber),
              parts[1].allSatisfy(\.isNumber),
              parts[2].allSatisfy(\.isNumber) else {
            return nil
        }
        return day
    }

    /// Format a Date as `YYYY-MM-DD` in UTC. Mirrors PuzzleStore's
    /// `utcDayString(from:)` — duplicated here to avoid the cross-target
    /// dependency.
    static func utcDayString(from date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        // swiftlint:disable:next force_unwrapping
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }
}
