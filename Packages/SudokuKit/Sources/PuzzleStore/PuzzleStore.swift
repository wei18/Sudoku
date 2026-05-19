// PuzzleStore — product-layer wrapper over `SudokuEngine.PuzzleGenerator`.
//
// Responsibilities (design.md §How.5.1):
//   - Derive deterministic seeds from (generatorVersion, dateUTC|salt, difficulty)
//     per §How.4.1.
//   - Assemble `PuzzleEnvelope` (Puzzle + PuzzleIdentity).
//   - Cache the daily trio in-memory keyed by (dateUTC, generatorVersion)
//     per §How.4.7 — see step 6.3.
//   - Mint practice salts + log them `.public` per §How.4.1 末段 — step 6.4.
//
// SudokuEngine remains pure: it knows nothing about dates, ids, salts, OSLog.

public import Foundation
public import SudokuEngine

public actor PuzzleStore: PuzzleProviderProtocol {
    private let generator: any PuzzleGenerating
    private let generatorVersion: GeneratorVersion

    public init(
        generator: any PuzzleGenerating = LivePuzzleGenerating(),
        generatorVersion: GeneratorVersion = .v1
    ) {
        self.generator = generator
        self.generatorVersion = generatorVersion
    }

    // MARK: - PuzzleProviderProtocol

    public func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope] {
        var envelopes: [PuzzleEnvelope] = []
        envelopes.reserveCapacity(3)
        for difficulty in [Difficulty.easy, .medium, .hard] {
            let seed = dailySeed(date: date, difficulty: difficulty)
            let puzzle = try runGenerator(seed: seed, difficulty: difficulty)
            let identity = PuzzleIdentity.daily(date: date, difficulty: difficulty)
            envelopes.append(PuzzleEnvelope(puzzle: puzzle, identity: identity))
        }
        return envelopes
    }

    public func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope {
        // Salt sourcing + logging deferred to step 6.4. For step 6.2 we use a
        // system-entropy UInt64 directly so the "distinct salts → distinct ids"
        // contract is observable.
        let salt = UInt64.random(in: 0...UInt64.max)
        let seed = practiceSeed(salt: salt, difficulty: difficulty)
        let puzzle = try runGenerator(seed: seed, difficulty: difficulty)
        let identity = PuzzleIdentity.practice(salt: salt, difficulty: difficulty)
        return PuzzleEnvelope(puzzle: puzzle, identity: identity)
    }

    public func puzzle(for puzzleId: String) async throws -> Puzzle {
        let parsed = try Self.parse(puzzleId: puzzleId)
        let seed: UInt64
        switch parsed.kind {
        case .daily(let day):
            seed = Self.dailySeed(
                day: day,
                difficulty: parsed.difficulty,
                generatorVersion: generatorVersion
            )
        case .practice(let salt):
            seed = Self.practiceSeed(
                salt: salt,
                difficulty: parsed.difficulty,
                generatorVersion: generatorVersion
            )
        }
        return try runGenerator(seed: seed, difficulty: parsed.difficulty)
    }

    // MARK: - Generator wrapping

    private func runGenerator(seed: UInt64, difficulty: Difficulty) throws -> Puzzle {
        do {
            return try generator.generate(
                seed: seed,
                difficulty: difficulty,
                version: generatorVersion
            )
        } catch {
            throw PuzzleStoreError.generatorFailed(underlying: String(describing: error))
        }
    }

    // MARK: - Seed derivation (§How.4.1)

    /// Daily seed: `stableHash(generatorVersion, utcDayString, difficulty)`.
    private func dailySeed(date: Date, difficulty: Difficulty) -> UInt64 {
        Self.dailySeed(
            day: utcDayString(from: date),
            difficulty: difficulty,
            generatorVersion: generatorVersion
        )
    }

    private func practiceSeed(salt: UInt64, difficulty: Difficulty) -> UInt64 {
        Self.practiceSeed(
            salt: salt,
            difficulty: difficulty,
            generatorVersion: generatorVersion
        )
    }

    internal static func dailySeed(
        day: String,
        difficulty: Difficulty,
        generatorVersion: GeneratorVersion
    ) -> UInt64 {
        var hash = StableHash()
        hash.combine(generatorVersion.rawValue)
        hash.combine("daily")
        hash.combine(day)
        hash.combine(difficulty.rawValue)
        return hash.value
    }

    internal static func practiceSeed(
        salt: UInt64,
        difficulty: Difficulty,
        generatorVersion: GeneratorVersion
    ) -> UInt64 {
        var hash = StableHash()
        hash.combine(generatorVersion.rawValue)
        hash.combine("practice")
        hash.combine(salt)
        hash.combine(difficulty.rawValue)
        return hash.value
    }

    // MARK: - puzzleId parsing

    internal struct ParsedPuzzleId {
        enum Kind {
            case daily(day: String)
            case practice(salt: UInt64)
        }
        let kind: Kind
        let difficulty: Difficulty
    }

    internal static func parse(puzzleId: String) throws -> ParsedPuzzleId {
        let parts = puzzleId.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        // Practice shape: "practice-<body>-<difficulty>" → 3 parts.
        if parts.count == 3, parts[0] == "practice" {
            guard let difficulty = Difficulty(rawValue: parts[2]) else {
                throw PuzzleStoreError.unknownDifficulty(parts[2])
            }
            guard let salt = CrockfordBase32.decode(parts[1]) else {
                throw PuzzleStoreError.malformedPuzzleId(puzzleId)
            }
            return ParsedPuzzleId(kind: .practice(salt: salt), difficulty: difficulty)
        }
        // Daily shape: "YYYY-MM-DD-<difficulty>" → 4 parts.
        if parts.count == 4 {
            let year = parts[0]
            let month = parts[1]
            let day = parts[2]
            let difficultyToken = parts[3]
            guard year.count == 4, month.count == 2, day.count == 2,
                  year.allSatisfy(\.isNumber),
                  month.allSatisfy(\.isNumber),
                  day.allSatisfy(\.isNumber) else {
                throw PuzzleStoreError.malformedPuzzleId(puzzleId)
            }
            guard let difficulty = Difficulty(rawValue: difficultyToken) else {
                throw PuzzleStoreError.unknownDifficulty(difficultyToken)
            }
            return ParsedPuzzleId(kind: .daily(day: "\(year)-\(month)-\(day)"), difficulty: difficulty)
        }
        throw PuzzleStoreError.malformedPuzzleId(puzzleId)
    }
}

// MARK: - StableHash

/// Deterministic FNV-1a 64-bit hash, with explicit framing per element so that
/// `combine("a"), combine("b")` and `combine("ab")` produce different outputs.
/// This is the §How.4.1 `stableHash` primitive: NOT `Swift.Hasher` (whose
/// output is randomized per process). Bit-identical across architectures.
internal struct StableHash {
    private static let fnvOffsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let fnvPrime: UInt64 = 0x0000_0100_0000_01B3

    private(set) var value: UInt64 = StableHash.fnvOffsetBasis

    mutating func combine(_ bytes: [UInt8]) {
        // Length prefix so different segmentations don't collide.
        let length = UInt64(bytes.count)
        absorb(length.littleEndianBytes)
        absorb(bytes)
    }

    mutating func combine(_ string: String) {
        combine(Array(string.utf8))
    }

    mutating func combine(_ word: UInt64) {
        combine(word.littleEndianBytes)
    }

    private mutating func absorb(_ bytes: [UInt8]) {
        for byte in bytes {
            value ^= UInt64(byte)
            value &*= StableHash.fnvPrime
        }
    }
}

private extension UInt64 {
    var littleEndianBytes: [UInt8] {
        let lowEndian = self.littleEndian
        return [
            UInt8(truncatingIfNeeded: lowEndian),
            UInt8(truncatingIfNeeded: lowEndian >> 8),
            UInt8(truncatingIfNeeded: lowEndian >> 16),
            UInt8(truncatingIfNeeded: lowEndian >> 24),
            UInt8(truncatingIfNeeded: lowEndian >> 32),
            UInt8(truncatingIfNeeded: lowEndian >> 40),
            UInt8(truncatingIfNeeded: lowEndian >> 48),
            UInt8(truncatingIfNeeded: lowEndian >> 56),
        ]
    }
}

// MARK: - CrockfordBase32 decode

extension CrockfordBase32 {
    static func decode(_ input: String) -> UInt64? {
        guard input.isEmpty == false else { return nil }
        var result: UInt64 = 0
        for char in input.uppercased() {
            guard let index = alphabet.firstIndex(of: char) else { return nil }
            // Guard overflow: 64 bits = 13 base32 digits max; we tolerate the
            // bounds check implicitly because `result << 5` will overflow trap
            // before yielding a wrong value, but we still bail out early.
            let (shifted, overflow) = result.multipliedReportingOverflow(by: 32)
            if overflow { return nil }
            result = shifted &+ UInt64(index)
        }
        return result
    }
}

// Legacy anchor: kept so older test imports of `moduleAnchor` keep compiling
// during the transitional period. Removed once unused.
public func moduleAnchor() {}
