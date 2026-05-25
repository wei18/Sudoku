// IdentityTests — Phase 6.1 (design.md §How.4.3, plan.md §6.1).
//
// PuzzleIdentity is the product-layer name for a puzzle. The id format is
// deterministic content (no PII) — `OSLog .public`-safe per §How.4.1 / §6.4.
//
// Format chosen:
//   - daily:    "YYYY-MM-DD-{difficulty}"        UTC date floor.
//   - practice: "practice-{base32(salt)}-{difficulty}"
//
// Base32 here is Douglas Crockford's alphabet ("0123456789ABCDEFGHJKMNPQRSTVWXYZ",
// no I L O U) applied to the UInt64 little-endian bytes. Crockford was picked
// over RFC 4648 to avoid visually ambiguous glyphs in puzzle IDs that may
// appear in user-facing diagnostics / bug reports (§How.4.1 末段).

import Foundation
import Testing
@testable import PuzzleStore
import SudokuEngine

@Suite("PuzzleIdentity")
struct PuzzleIdentityTests {

    @Test func dailyIdentityFormat() {
        // 2026-06-01 15:30 UTC → floor → 2026-06-01.
        let date = Date(timeIntervalSince1970: 1_780_327_800) // 2026-06-01T15:30:00Z
        let easy = PuzzleIdentity.daily(date: date, difficulty: .easy)
        let medium = PuzzleIdentity.daily(date: date, difficulty: .medium)
        let hard = PuzzleIdentity.daily(date: date, difficulty: .hard)
        #expect(easy.puzzleId == "2026-06-01-easy")
        #expect(medium.puzzleId == "2026-06-01-medium")
        #expect(hard.puzzleId == "2026-06-01-hard")
        #expect(easy.kind == .daily)
        #expect(easy.difficulty == .easy)
    }

    @Test func dailyIdentityFloorsToUTCMidnight() {
        // Two times on same UTC day → same id; one second past midnight → next day.
        let earlyUTC = Date(timeIntervalSince1970: 1_780_272_000) // 2026-06-01T00:00:00Z
        let lateUTC = Date(timeIntervalSince1970: 1_780_358_399) // 2026-06-01T23:59:59Z
        let nextDay = Date(timeIntervalSince1970: 1_780_358_400) // 2026-06-02T00:00:00Z
        #expect(PuzzleIdentity.daily(date: earlyUTC, difficulty: .easy).puzzleId == "2026-06-01-easy")
        #expect(PuzzleIdentity.daily(date: lateUTC, difficulty: .easy).puzzleId == "2026-06-01-easy")
        #expect(PuzzleIdentity.daily(date: nextDay, difficulty: .easy).puzzleId == "2026-06-02-easy")
    }

    @Test func practiceIdentityBase32() {
        let id = PuzzleIdentity.practice(salt: 0, difficulty: .easy)
        #expect(id.puzzleId.hasPrefix("practice-"))
        #expect(id.puzzleId.hasSuffix("-easy"))
        #expect(id.kind == .practice)

        // Distinct salts produce distinct ids.
        let first = PuzzleIdentity.practice(salt: 0x1234_5678_9ABC_DEF0, difficulty: .medium)
        let second = PuzzleIdentity.practice(salt: 0x1234_5678_9ABC_DEF1, difficulty: .medium)
        #expect(first.puzzleId != second.puzzleId)
        #expect(first.puzzleId.hasSuffix("-medium"))
    }

    @Test func practiceIdentityCrockfordAlphabet() {
        // Body between "practice-" and "-{difficulty}" only contains
        // Crockford base32 chars (0-9, A-Z minus I L O U).
        let id = PuzzleIdentity.practice(salt: 0xFFFF_FFFF_FFFF_FFFF, difficulty: .hard).puzzleId
        let body = id
            .replacingOccurrences(of: "practice-", with: "")
            .replacingOccurrences(of: "-hard", with: "")
        let allowed = Set("0123456789ABCDEFGHJKMNPQRSTVWXYZ")
        for char in body {
            #expect(allowed.contains(char), "unexpected char '\(char)' in practice id body \(body)")
        }
    }

    @Test func valueTypeConformances() {
        let id1 = PuzzleIdentity.daily(date: Date(timeIntervalSince1970: 0), difficulty: .easy)
        let id2 = PuzzleIdentity.daily(date: Date(timeIntervalSince1970: 0), difficulty: .easy)
        #expect(id1 == id2)
        #expect(id1.hashValue == id2.hashValue)
        // Sendable: compile-time check via passing to actor (deferred to FakeGenerator step).
    }

    @Test func codableRoundtrip() throws {
        let original = PuzzleIdentity.practice(salt: 42, difficulty: .hard)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PuzzleIdentity.self, from: data)
        #expect(decoded == original)
    }

    @Test func modeCases() {
        // M5 (issue #65): `PuzzleKind` was collapsed into `SudokuEngine.Mode`.
        #expect(Mode.allCases.count == 2)
        #expect(Mode.allCases.contains(.daily))
        #expect(Mode.allCases.contains(.practice))
    }
}
