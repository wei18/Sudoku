// StreakTokens — streak signaling tokens (#1023 R5 / design.md §5.2, §5.3).
//
// Extracted to a sibling file (same repo convention as the other +Feature
// splits — Theme.swift is at its 400-line ceiling) rather than growing
// Theme.swift further. Consumed by Phase B's streak view (M3/M4 pip
// advance); defined now — alongside `CompletionMotionPlan`'s M1–M10 table,
// which it drives — so adding it later doesn't churn the `Theme` protocol a
// second time.

public struct StreakTokens: Sendable, Equatable, Hashable {
    /// The "off" (not-yet-advanced) pip fill — the ON state reuses
    /// `accent.celebratory`, matching the streak flame's existing color.
    public let pipOff: ThemeColor

    public init(pipOff: ThemeColor) {
        self.pipOff = pipOff
    }
}
