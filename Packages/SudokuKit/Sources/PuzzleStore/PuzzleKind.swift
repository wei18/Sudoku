// PuzzleKind — coarse classification (daily vs practice) used for routing
// and analytics. Encoded into `PuzzleIdentity.puzzleId` shape; see
// `PuzzleIdentity.swift`.

public enum PuzzleKind: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case daily
    case practice
}
