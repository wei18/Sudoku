// PuzzleStore — product-layer wrapper over `SudokuEngine.PuzzleGenerator`.
//
// Responsibilities (docs/v1/design.md §How.5.1):
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
public import Telemetry

public actor PuzzleStore: PuzzleProviderProtocol {
    private let generator: any PuzzleGenerating
    private let generatorVersion: GeneratorVersion
    private let saltSource: PracticeSalt
    private let logger: any LoggerProtocol

    /// In-memory cache of `fetchDailyTrio`. Keyed by `(utcDayString,
    /// generatorVersion)` so a generator version bump (§How.4.5) invalidates
    /// the prior day's contents.
    ///
    /// Practice puzzles are NOT cached (§How.4.7): salts are fresh per call.
    private var dailyTrioCache: [DailyCacheKey: [PuzzleEnvelope]] = [:]

    private struct DailyCacheKey: Hashable, Sendable {
        let day: String
        let generatorVersion: GeneratorVersion
    }

    public init(
        generator: any PuzzleGenerating = LivePuzzleGenerating(),
        generatorVersion: GeneratorVersion = .v1,
        saltSource: PracticeSalt = PracticeSalt(),
        logger: (any LoggerProtocol)? = nil
    ) {
        self.generator = generator
        self.generatorVersion = generatorVersion
        self.saltSource = saltSource
        // Default logger: `OSLogSink`'s live adapter. We don't construct an
        // OSLoggerAdapter directly here (it's internal to Telemetry) — instead
        // we re-use the public `OSLogSink(subsystem:category:)` path's
        // adapter by going through a small inline init. For the default case
        // we accept nil and treat it as "no logging" via a private no-op.
        self.logger = logger ?? NoOpLogger()
    }

    // MARK: - PuzzleProviderProtocol

    public func fetchDailyTrio(date: Date) async throws -> [PuzzleEnvelope] {
        let key = DailyCacheKey(day: UTCDay.string(from: date), generatorVersion: generatorVersion)
        if let cached = dailyTrioCache[key] {
            return cached
        }
        var envelopes: [PuzzleEnvelope] = []
        envelopes.reserveCapacity(3)
        for difficulty in [Difficulty.easy, .medium, .hard] {
            let seed = dailySeed(date: date, difficulty: difficulty)
            let puzzle = try runGenerator(seed: seed, difficulty: difficulty)
            let identity = PuzzleIdentity.daily(date: date, difficulty: difficulty)
            envelopes.append(PuzzleEnvelope(puzzle: puzzle, identity: identity))
        }
        dailyTrioCache[key] = envelopes
        return envelopes
    }

    public func fetchPracticePool(difficulty: Difficulty) async throws -> PuzzleEnvelope {
        let salt = saltSource.next()
        // Log salt `.public` per §How.4.1 末段 — deterministic content, no PII,
        // enables "player reports a hard puzzle" debugging.
        logger.log(
            level: .info,
            message: "PracticeSalt salt=0x\(String(salt, radix: 16, uppercase: true)) difficulty=\(difficulty.rawValue)",
            privacy: .publicValue
        )
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
            day: UTCDay.string(from: date),
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
        let kind: ParsedKind
        let difficulty: Difficulty
    }

    internal enum ParsedKind {
        case daily(day: String)
        case practice(salt: UInt64)
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

// MARK: - Default logger

/// Default logger when callers don't inject one. Production composition is
/// expected to inject `OSLogSink`'s adapter via the `logger:` parameter; the
/// no-op keeps the default path zero-cost when telemetry isn't wired up
/// (e.g. command-line / unit tests that don't care).
private struct NoOpLogger: LoggerProtocol {
    func log(level: LogLevel, message: String, privacy: LogPrivacy) {}
}

// Legacy anchor: kept so older test imports of `moduleAnchor` keep compiling
// during the transitional period. Removed once unused.
public func moduleAnchor() {}
