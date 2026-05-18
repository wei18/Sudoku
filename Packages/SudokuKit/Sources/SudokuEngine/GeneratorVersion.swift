// GeneratorVersion — frozen-once-shipped identifier for the generator algorithm.
//
// Per design.md §How.4.5: bumping this enum requires a new leaderboard family.
// v1 is the initial production version.

public enum GeneratorVersion: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case v1
}
