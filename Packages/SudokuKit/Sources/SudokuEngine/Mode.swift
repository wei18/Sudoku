// Mode — coarse game-mode classification (daily vs practice).
//
// Promoted to a leaf-module enum per M5 (issue #65): boundary types
// (Persistence / Telemetry / GameCenterClient) previously crossed string
// values for `mode`, which made typos at call sites silently drop scores.
//
// CloudKit serialization contract: existing user save data has `mode`
// stored as a CKRecord `String` field with values exactly `"daily"` /
// `"practice"`. The raw values declared here MUST match that wire format
// so legacy records round-trip; mappers serialize via `Mode.rawValue` at
// the CK seam (see `SavedGameMapper` / `PersonalRecordMapper`).
//
// PuzzleStore's prior `PuzzleKind` (same shape) has been collapsed into
// this single source of truth.

public enum Mode: String, Sendable, Equatable, Hashable, Codable, CaseIterable {
    case daily
    case practice
}
