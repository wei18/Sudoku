// Board — 4×4 grid of optional tile values for 2048.
//
// Each cell holds nil (empty) or a power-of-two integer (2, 4, 8, … 131072).
// Value type, Sendable, Equatable, Codable — mirrors the design of Cell in
// MinesweeperEngine: pure data, no behaviour, no Apple-framework imports.
//
// Indexing is row-major: index(row:col:) = row * 4 + col, same convention as
// MinesweeperEngine.

// swiftlint:disable identifier_name
// `r`, `c`, `i` are idiomatic for tight grid traversal.

internal import Foundation

public struct Board: Sendable, Equatable, Hashable, Codable {

    // MARK: - Constants

    public static let size: Int = 4
    public static let cellCount: Int = 16

    // MARK: - Storage

    /// Flat row-major array of 16 optional tile values.
    /// nil = empty; non-nil = a power of two (2, 4, 8, …).
    public private(set) var tiles: [Int?]

    // MARK: - Init

    /// Empty board (all nil).
    public init() {
        tiles = Array(repeating: nil, count: Self.cellCount)
    }

    /// Restore from a previously-captured flat tile array (persistence round-trip).
    public init(tiles: [Int?]) {
        precondition(tiles.count == Self.cellCount, "tiles must have exactly \(Self.cellCount) elements")
        self.tiles = tiles
    }

    // MARK: - Indexing

    public func index(row: Int, col: Int) -> Int { row * Self.size + col }

    public func inBounds(row: Int, col: Int) -> Bool {
        row >= 0 && row < Self.size && col >= 0 && col < Self.size
    }

    public subscript(row: Int, col: Int) -> Int? {
        get { tiles[index(row: row, col: col)] }
        set { tiles[index(row: row, col: col)] = newValue }
    }

    // MARK: - Queries

    /// Indices of all empty (nil) cells in row-major order.
    public var emptyIndices: [Int] {
        tiles.indices.filter { tiles[$0] == nil }
    }

    public var isEmpty: Bool { tiles.allSatisfy { $0 == nil } }

    /// Returns true if any tile has value ≥ 2048.
    public var containsTarget: Bool { tiles.contains { ($0 ?? 0) >= 2048 } }

    // MARK: - Internal mutation

    mutating func setTile(at index: Int, value: Int?) {
        tiles[index] = value
    }
}

// swiftlint:enable identifier_name
