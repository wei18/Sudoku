# #552 — PersonalRecord best-time optimistic concurrency (impl-notes)

Branch `feat/552-personalrecord-optimistic`. Highest-risk: data correctness + reverses
parts of #544/#567 (re-introduces a SCOPED etag layer) + reworks #578's sink routing.
Reference impl for the etag mechanics: commit **`fc557b8`** (`git show fc557b8`).

## Problem (low severity, but real)
`PersonalRecord` write is now live (#578) via `.allKeys` last-write-wins. Under a multi-device
race, device B (stale fetch) can write a SLOWER best-time and clobber device A's faster one,
and B's write can drop A's `completedPuzzleIds`. Fix = optimistic concurrency for PersonalRecord
ONLY (SavedGame/Monetization keep `.allKeys` — resume/entitlement want last-write-wins).

## A. Etag plumbing (re-introduce, scoped — ref fc557b8)
1. `PrivateCKGateway.swift` — `RecordPayload.encodedSystemFields: Data?` (server etag+recordID),
   EXCLUDED from `Equatable`/`Hashable` (custom `==`/`hash` over recordType+recordName+fields).
   Add to `init` with default `nil`.
2. `LivePrivateCKGateway`:
   - `payload(from: CKRecord)`: archive `record.encodeSystemFields(with:)` → `encodedSystemFields`.
   - `baseRecord(from: payload, zoneID:)`: if `encodedSystemFields` present, `NSKeyedUnarchiver`
     (requiresSecureCoding) → restored `CKRecord` (keeps recordID+etag); else fresh `CKRecord`.
     `record(from:)` uses `baseRecord`. (Copy fc557b8 verbatim.)

## B. Per-record save policy
3. NEW `RecordSavePolicy: Sendable` enum in PrivateCKGateway.swift: `.lastWriteWins`, `.ifUnchanged`.
4. Protocol requirement becomes `func save(_ payload: RecordPayload, policy: RecordSavePolicy) async throws`.
   Add extension default `func save(_ payload: RecordPayload) async throws { try await save(payload, policy: .lastWriteWins) }`
   so all 12 existing `gateway.save(payload)` callers stay UNCHANGED.
5. `LivePrivateCKGateway.save(_:policy:)`: `.lastWriteWins → .allKeys`, `.ifUnchanged →
   .ifServerRecordUnchanged` in `modifyRecords(saving:deleting:savePolicy:atomically:)`.
   Keep the existing `translate(_:recordName:)` (`serverRecordChanged → .syncConflict`).
6. `FakePrivateCKGateway.save(_:policy:)` — model CloudKit optimistic concurrency:
   - keep `records: [String:RecordPayload]` + add `versions: [String:Int]`; `etag(v) = Data("etag-v\(v)".utf8)`.
   - `.ifUnchanged`: if `versions[name]` exists, require `payload.encodedSystemFields == etag(versions[name])` else `throw .syncConflict(recordName:)`. (absent = insert, accepted.)
   - `.lastWriteWins`: accept unconditionally.
   - both branches: `version = (versions[name] ?? 0) + 1`; stamp stored copy's `encodedSystemFields = etag(version)`; store.
   - `seed(_:)` stamps v1; `fetch` returns the stamped payload. Existing `alwaysOnSave` failure mode + `.operations` recording unchanged.

## C. PersonalRecordStore optimistic write path
7. `recordCompletion(puzzleId:mode:difficulty:elapsedSeconds:)` — bounded retry (e.g. `maxAttempts = 3`):
   ```
   let name = Self.recordName(mode:difficulty:)
   for _ in 0..<maxAttempts {
       let existingPayload = try await gateway.fetch(recordName: name)         // carries etag
       let existing = existingPayload.flatMap(PersonalRecordMapper.record) ?? .empty(mode:difficulty:at: clock())
       guard let updated = existing.recordingCompletion(puzzleId:elapsedSeconds:at: clock()) else { return existing } // dedup
       var payload = PersonalRecordMapper.payload(from: updated)
       payload.encodedSystemFields = existingPayload?.encodedSystemFields     // carry etag for ifUnchanged
       do { try await gateway.save(payload, policy: .ifUnchanged); return updated }
       catch PersistenceError.syncConflict { continue }                       // re-fetch → re-min → re-union → retry
   }
   throw PersistenceError.syncConflict(recordName: name)
   ```
   `recordingCompletion` (from #578) already does `min(best)` + `ids ∪ {puzzleId}` against the FRESH
   server record → the merge is correct on retry. The dedup `nil` return covers "our own prior write
   actually landed".
8. `upsert(_ record:)` stays `.lastWriteWins` (generic facade set; not the completion path).

## D. Facade + sink routing (so the LIVE path uses the retry)
9. `PersistenceProtocol`: add `func recordPuzzleCompletion(puzzleId:mode:difficulty:elapsedSeconds:) async throws`
   + a DEFAULT extension impl (`fetchPersonalRecord` → `recordingCompletion` → `upsertPersonalRecord`)
   so the 13 conformers/fakes need NO change. `LivePersistence` OVERRIDES it →
   `personalRecordStore().recordCompletion(...)` (the optimistic retry path).
10. Refactor `PersonalRecordSink.receive` to call `persistence.recordPuzzleCompletion(...)` instead of
    fetch+merge+upsert (simplifies the sink; the merge/retry now lives behind the facade).

## Tests (TDD, fail-first)
- RecordPayload: `encodedSystemFields` excluded from `==`/`hash`.
- FakePrivateCKGateway: `.ifUnchanged` with stale/absent/matching etag (conflict / insert / accept); version bump.
- PersonalRecordStore **race test** (THE acceptance): two stores share one FakePrivateCKGateway.
  A records fast (best=100, puzzle pA); B (fetched before A's write) records slower (best=200, puzzle pB)
  → B's first save conflicts → B retries → final record: **bestTimeSeconds == 100** (A's faster kept),
  completedCount == 2, completedPuzzleIds == {pA, pB} (union). Also: exhausting `maxAttempts` throws.
- recordPuzzleCompletion default-impl (a fake) records via fetch+upsert; LivePersistence override hits the store.
- All existing PersistenceKit tests stay green.

## Out of scope
- SavedGame/Monetization stay `.allKeys` (intentional).
- The general RetryHarness/ConflictResolver (#567) stays deleted — this is a FOCUSED inline retry.
