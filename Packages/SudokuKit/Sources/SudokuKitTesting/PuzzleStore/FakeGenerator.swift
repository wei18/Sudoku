// FakeGenerator — test stand-in for `PuzzleGenerating`. Records every call
// and yields a deterministic canned `Puzzle` per seed, with optional
// one-shot overrides for error injection (cache / exhaustion tests).
//
// Test-only; lives in SudokuKitTesting. Implemented as a lock-protected
// final class (not an actor) because `PuzzleGenerating.generate` is
// synchronous — wrapping isolation in `Task` would force the protocol to
// become `async` everywhere downstream just to satisfy the fake.

internal import Foundation
public import PuzzleStore
public import SudokuEngine

public final class FakeGenerator: PuzzleGenerating, @unchecked Sendable {

    public struct Call: Sendable, Equatable {
        public let seed: UInt64
        public let difficulty: Difficulty
        public let version: GeneratorVersion
    }

    private let lock = NSLock()
    private var _callCount: Int = 0
    private var _calls: [Call] = []
    private var pendingOverrides: [Result<Puzzle, GeneratorError>] = []

    public init() {}

    public var callCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _callCount
    }

    public var calls: [Call] {
        lock.lock(); defer { lock.unlock() }
        return _calls
    }

    /// Enqueue a one-shot result consumed by the next `generate(...)` call
    /// (FIFO). When empty the fake falls back to `CannedPuzzle`.
    public func enqueueNext(_ result: Result<Puzzle, GeneratorError>) {
        lock.lock(); defer { lock.unlock() }
        pendingOverrides.append(result)
    }

    public func resetOverrides() {
        lock.lock(); defer { lock.unlock() }
        pendingOverrides.removeAll()
    }

    public func generate(
        seed: UInt64,
        difficulty: Difficulty,
        version: GeneratorVersion
    ) throws -> Puzzle {
        lock.lock()
        _callCount += 1
        _calls.append(Call(seed: seed, difficulty: difficulty, version: version))
        let override = pendingOverrides.isEmpty ? nil : pendingOverrides.removeFirst()
        lock.unlock()
        if let override {
            switch override {
            case .success(let puzzle): return puzzle
            case .failure(let error): throw error
            }
        }
        return CannedPuzzle.make(seed: seed, difficulty: difficulty, version: version)
    }
}

// MARK: - CannedPuzzle

/// Deterministic canned puzzle keyed by `(seed, difficulty)`. Bit-identical
/// per seed — sufficient for cache / id round-trip assertions without paying
/// the real generator's cost.
enum CannedPuzzle {
    static func make(seed: UInt64, difficulty: Difficulty, version: GeneratorVersion) -> Puzzle {
        // A known valid solved grid.
        let solvedString =
            "534678912" +
            "672195348" +
            "198342567" +
            "859761423" +
            "426853791" +
            "713924856" +
            "961537284" +
            "287419635" +
            "345286179"
        // swiftlint:disable force_try
        let solved = try! Board(clues: solvedString)
        let cluesToKeep: Int
        switch difficulty {
        case .easy:   cluesToKeep = 50
        case .medium: cluesToKeep = 35
        case .hard:   cluesToKeep = 28
        }
        var chars = Array(solvedString)
        var rng = seed | 1
        var keptCount = chars.count
        for index in chars.indices.reversed() {
            if keptCount <= cluesToKeep { break }
            rng &*= 0x9E37_79B9_7F4A_7C15
            rng ^= rng >> 30
            if (rng & 1) == 0 {
                chars[index] = "."
                keptCount -= 1
            }
        }
        let clues = try! Board(clues: String(chars))
        // swiftlint:enable force_try
        return Puzzle(
            clues: clues,
            solution: solved,
            difficulty: difficulty,
            generatorVersion: version,
            seed: seed
        )
    }
}
