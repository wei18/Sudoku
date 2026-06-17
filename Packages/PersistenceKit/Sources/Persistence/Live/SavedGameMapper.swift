// SavedGameMapper — `GameSessionSnapshot` ↔ `RecordPayload` mapping.
//
// Encodes the 12 fields per §How.2. The puzzle's `clues` / `solution`
// boards are NOT round-tripped through the record — `loadOrCreate` rebuilds
// them via the injected `puzzleLoader` (a `puzzleId` is deterministic).

internal import Foundation
internal import SudokuGameState
internal import SudokuEngine

internal enum SavedGameMapper {

    private struct UndoEnvelope: Codable {
        let undo: [Move]
        let redo: [Move]
    }

    private struct StatusEnvelope: Codable {
        let value: GameSessionStatus
    }

    private struct NotesEnvelope: Codable {
        let value: NotesGrid
    }

    static func payload(
        from snapshot: GameSessionSnapshot,
        recordName: String,
        puzzleId: String,
        mode: Mode,
        difficulty: Difficulty,
        lastModifiedAt: Date,
        schemaVersion: Int
    ) -> RecordPayload {
        let encoder = JSONEncoder()
        // swiftlint:disable force_try
        let notesData = try! encoder.encode(NotesEnvelope(value: snapshot.notes))
        let undoData = try! encoder.encode(
            UndoEnvelope(undo: snapshot.undoMoves, redo: snapshot.redoMoves)
        )
        let statusData = try! encoder.encode(StatusEnvelope(value: snapshot.status))
        // swiftlint:enable force_try

        let statusString: String
        switch snapshot.status {
        case .completed:
            statusString = "completed"
        default:
            statusString = "inProgress"
        }

        // Per impl-notes 2026-05-20_wave-2-blocker-fixes §B4: write the
        // snapshot's authoritative `startedAt`. Fall back to `lastModifiedAt`
        // ONLY when the snapshot was taken before `.start()` was ever
        // dispatched (idle snapshot — first save of a fresh record).
        let startedAt = snapshot.startedAt ?? lastModifiedAt

        // M5 (issue #65): CK wire format encodes raw String; the call-site
        // `Mode` / `Difficulty` enums round-trip via `.rawValue` here.
        let fields: [String: RecordValue] = [
            SavedGameStore.Field.puzzleId: .string(puzzleId),
            SavedGameStore.Field.mode: .string(mode.rawValue),
            SavedGameStore.Field.difficulty: .string(difficulty.rawValue),
            SavedGameStore.Field.boardState: .string(snapshot.currentBoard.encoded()),
            SavedGameStore.Field.notesState: .data(notesData),
            SavedGameStore.Field.undoStack: .data(undoData),
            SavedGameStore.Field.startedAt: .date(startedAt),
            SavedGameStore.Field.lastModifiedAt: .date(lastModifiedAt),
            SavedGameStore.Field.elapsedSeconds: .int(snapshot.elapsedSeconds),
            SavedGameStore.Field.status: .string(statusString),
            SavedGameStore.Field.generatorVersion: .int(generatorVersionInt(snapshot.puzzle.generatorVersion)),
            SavedGameStore.Field.schemaVersion: .int(schemaVersion),
            // Cache the full GameSessionStatus enum separately so we can
            // restore states beyond "inProgress / completed" (e.g. `.paused`).
            "statusEnvelope": .data(statusData),
            // SDD-003 Epic 3: cumulative conflicting-placement counter.
            SavedGameStore.Field.mistakeCount: .int(snapshot.mistakeCount)
        ]
        return RecordPayload(
            recordType: PrivateCKConstants.savedGameRecordType,
            recordName: recordName,
            fields: fields
        )
    }

    static func snapshot(from payload: RecordPayload, puzzle: Puzzle) throws -> GameSessionSnapshot {
        guard case .string(let boardString) = payload.fields[SavedGameStore.Field.boardState] else {
            throw PersistenceError.underlying(domain: "Persistence", code: 1, description: "missing boardState")
        }
        guard case .data(let notesData) = payload.fields[SavedGameStore.Field.notesState] else {
            throw PersistenceError.underlying(domain: "Persistence", code: 2, description: "missing notesState")
        }
        guard case .data(let undoData) = payload.fields[SavedGameStore.Field.undoStack] else {
            throw PersistenceError.underlying(domain: "Persistence", code: 3, description: "missing undoStack")
        }
        guard case .int(let elapsed) = payload.fields[SavedGameStore.Field.elapsedSeconds] else {
            throw PersistenceError.underlying(domain: "Persistence", code: 4, description: "missing elapsedSeconds")
        }
        let decoder = JSONDecoder()
        let notes = try decoder.decode(NotesEnvelope.self, from: notesData).value
        let undo = try decoder.decode(UndoEnvelope.self, from: undoData)

        // Prefer the encoded enum when present (covers `.paused` etc.);
        // fall back to the string-encoded status for older records.
        let status: GameSessionStatus
        if case .data(let statusData) = payload.fields["statusEnvelope"] {
            status = try decoder.decode(StatusEnvelope.self, from: statusData).value
        } else if case .string(let raw) = payload.fields[SavedGameStore.Field.status] {
            status = raw == "completed" ? .completed : .playing
        } else {
            status = .idle
        }

        let board = try Board(encoded: boardString, against: puzzle)

        // Rehydrate `startedAt` from the CK record (per §B4). Missing /
        // wrong-type fields collapse to nil — restore() will treat that as
        // "session never started", which is correct for fresh records.
        let startedAt: Date?
        if case .date(let value) = payload.fields[SavedGameStore.Field.startedAt] {
            startedAt = value
        } else {
            startedAt = nil
        }

        // SDD-003 Epic 3: restore the mistake counter. Absent in older records
        // (saved before this field existed) → default to 0, which is correct
        // (those sessions had no mistake tracking).
        let mistakeCount: Int
        if case .int(let value) = payload.fields[SavedGameStore.Field.mistakeCount] {
            mistakeCount = value
        } else {
            mistakeCount = 0
        }

        return GameSessionSnapshot(
            puzzle: puzzle,
            currentBoard: board,
            status: status,
            elapsedSeconds: elapsed,
            undoMoves: undo.undo,
            redoMoves: undo.redo,
            notes: notes,
            startedAt: startedAt,
            mistakeCount: mistakeCount
        )
    }

    static func summary(from payload: RecordPayload) -> SavedGameSummary? {
        guard
            case .string(let puzzleId) = payload.fields[SavedGameStore.Field.puzzleId],
            case .string(let modeRaw) = payload.fields[SavedGameStore.Field.mode],
            case .string(let difficultyRaw) = payload.fields[SavedGameStore.Field.difficulty],
            case .date(let lastModifiedAt) = payload.fields[SavedGameStore.Field.lastModifiedAt],
            case .int(let elapsed) = payload.fields[SavedGameStore.Field.elapsedSeconds],
            case .string(let status) = payload.fields[SavedGameStore.Field.status],
            case .int(let genVersion) = payload.fields[SavedGameStore.Field.generatorVersion]
        else {
            return nil
        }
        // M5 (issue #65): decode raw wire strings into typed enums. Unknown
        // values (e.g. a CKRecord written by a future schema with a new
        // difficulty case) drop the row from the summary projection rather
        // than crashing — same posture as the other `guard case` rejections.
        guard let mode = Mode(rawValue: modeRaw),
              let difficulty = Difficulty(rawValue: difficultyRaw) else {
            return nil
        }
        return SavedGameSummary(
            recordName: payload.recordName,
            puzzleId: puzzleId,
            mode: mode,
            difficulty: difficulty,
            lastModifiedAt: lastModifiedAt,
            elapsedSeconds: elapsed,
            status: status,
            generatorVersion: genVersion
        )
    }

    /// Map `GeneratorVersion` (a `String` raw-value enum) to the `Int(64)`
    /// CloudKit field type. v1 → 1.
    static func generatorVersionInt(_ version: GeneratorVersion) -> Int {
        switch version {
        case .v1: return 1
        }
    }
}

// MARK: - Board reconstruction helper

private extension Board {
    /// Reconstruct a board from the 81-char encoded string while preserving
    /// the puzzle's `givenMask`. `Board(clues:)` would mark every
    /// non-`.` cell as given, which is wrong for the in-progress board
    /// (the player's own digits are not givens).
    init(encoded: String, against puzzle: Puzzle) throws {
        self = puzzle.clues
        guard encoded.count == Board.cellCount else {
            throw PersistenceError.underlying(
                domain: "Persistence", code: 5, description: "invalid board length"
            )
        }
        for (index, character) in encoded.enumerated() {
            let digit: Int?
            if character == "." {
                digit = nil
            } else if let int = Int(String(character)) {
                digit = int
            } else {
                throw PersistenceError.underlying(
                    domain: "Persistence", code: 6, description: "invalid board char"
                )
            }
            // Skip given cells (preserve the immutable clue grid).
            if givenMask[index] { continue }
            try setDigit(digit, atIndex: index)
        }
    }
}
