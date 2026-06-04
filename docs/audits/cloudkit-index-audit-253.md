# CloudKit Index Audit — SavedGame + MonetizationState (#253)

**Status:** Observability / cost-accounting. NOT a v2.5 blocker, NOT a schema or code change.
**Date:** 2026-06-05
**Scope:** Quantify the index cost already committed to Production on 2026-06-02 (#217),
identify TRUE unused indexes, recommend live-with-it vs migrate.

## TL;DR

- Only **3 fields** participate in any query path: `status`, `mode`, `puzzleId` (all on `SavedGame`).
- Every other indexed field is dead weight whose QUERYABLE/SORTABLE/SEARCHABLE index can never be removed (Apple's Production rule: add-only).
- The clearest waste is the **three BYTES fields** auto-indexed QUERYABLE/SORTABLE — `notesState`, `undoStack`, `statusEnvelope` — which are opaque JSON blobs that cannot meaningfully be filtered or sorted and never appear in a predicate.
- `MonetizationState` is a per-account **singleton** fetched only by record name; **none** of its fields are ever queried, so every index on it is pure overhead.
- Recommendation: **live with it** (cost is bounded and tiny per user); do not migrate. See §5.

---

## 1. Ground truth — what the code actually queries

### RecordPredicate cases (`PrivateCKGateway.swift:43-47`)

```
case all(recordType:)                       — DEAD: zero callers anywhere (prod or test)
case statusEquals(recordType:, status:)     — used
case dailyCompletedOn(dayPrefix:)           — used
```

### Production query call sites (only two exist)

| Call site | Predicate | NSPredicate (from `LivePrivateCKGateway.translate`) | Fields touched |
|---|---|---|---|
| `SavedGameStore.latestInProgress()` (`SavedGameStore.swift:64`) | `.statusEquals(…, "inProgress")` | `status == %@` | **status** |
| `SavedGameStore.fetchCompletedDailyIds(for:)` (`SavedGameStore.swift:169`) | `.dailyCompletedOn(dayPrefix:)` | `mode == %@ AND status == %@ AND puzzleId BEGINSWITH %@` | **mode**, **status**, **puzzleId** |

Everything else in the data path is a **record-name lookup**, which uses no field index:
- `gateway.fetch(recordName:)` — `loadOrCreate`, `markCompleted`, the conflict re-fetch, and the entire `MonetizationState` load path.
- `gateway.save(_:)` / `gateway.delete(recordName:)` — writes, no index needed to execute (but writes do pay write-amplification on every indexed field; see §3).

**Net:** the union of all queried fields is exactly `{ status, mode, puzzleId }`, all on `SavedGame`. `puzzleId` is used via `BEGINSWITH` (prefix match), which CloudKit serves from a QUERYABLE/SORTABLE string index.

> Note on the deployed schema file: `~/GitHub/Wei18/tmp/sudoku-full-schema.ckdb` exists on disk but
> sits outside this isolated worktree and could not be opened from here (read denied across the
> isolation boundary). This audit therefore takes the deployed index shape from the issue body's
> enumeration ("auto-inferred QUERYABLE / SORTABLE on most fields; BYTES fields QUERYABLE SORTABLE")
> and cross-references it against the field list the code actually writes (authoritative, read from
> `SavedGameMapper.swift` + `LiveMonetizationStateStore.swift`). If the exact per-field index set
> ever needs byte-level confirmation, re-run this audit with the `.ckdb` readable in-scope.

---

## 2. Field × index × usage table

Index column reflects the issue's stated auto-inferred Production shape (QUERYABLE/SORTABLE on
scalar+string fields, and — the flagged anomaly — QUERYABLE/SORTABLE even on BYTES fields).
"Verdict" is grounded in §1.

### SavedGame (13 fields written — `SavedGameMapper.payload`)

| Field | Type | Deployed index (per issue) | In any predicate? | Verdict |
|---|---|---|---|---|
| `status` | String | QUERYABLE SORTABLE | Yes — `.statusEquals` + `.dailyCompletedOn` | **USED** (`status == %@`) |
| `mode` | String | QUERYABLE SORTABLE | Yes — `.dailyCompletedOn` | **USED** (`mode == %@`) |
| `puzzleId` | String | QUERYABLE SORTABLE | Yes — `.dailyCompletedOn` | **USED** (`puzzleId BEGINSWITH %@`) |
| `boardState` | String | QUERYABLE SORTABLE | No | **UNUSED** |
| `difficulty` | String | QUERYABLE SORTABLE | No (decoded from payload, never filtered) | **UNUSED** |
| `lastModifiedAt` | Date | QUERYABLE SORTABLE | No — newest-wins is computed in-memory (`.max` in `latestInProgress`, `SavedGameStore.swift:79`), never a server sort/filter | **UNUSED** |
| `elapsedSeconds` | Int(64) | QUERYABLE SORTABLE | No | **UNUSED** |
| `startedAt` | Date | QUERYABLE SORTABLE | No | **UNUSED** |
| `generatorVersion` | Int(64) | QUERYABLE SORTABLE | No | **UNUSED** |
| `schemaVersion` | Int(64) | QUERYABLE SORTABLE | No | **UNUSED** |
| `notesState` | **BYTES** | QUERYABLE SORTABLE | No (opaque JSON blob) | **UNUSED — clear waste** |
| `undoStack` | **BYTES** | QUERYABLE SORTABLE | No (opaque JSON blob) | **UNUSED — clear waste** |
| `statusEnvelope` | **BYTES** | QUERYABLE SORTABLE | No (opaque JSON blob) | **UNUSED — clear waste** |

### MonetizationState (5 fields — `LiveMonetizationStateStore.payload`)

Record is a **singleton** (`recordName = "monetization-state"`, one per iCloud account), loaded
**only** via `fetch(recordName:)`. There is no `MonetizationState` query predicate in the codebase
at all. Every index on every field here is unreachable.

| Field | Type | Deployed index (per issue) | In any predicate? | Verdict |
|---|---|---|---|---|
| `firstLaunchAt` | Date | QUERYABLE SORTABLE | No | **UNUSED** |
| `hasPurchasedRemoveAds` | Int(64) | QUERYABLE SORTABLE | No | **UNUSED** |
| `lastShownDate` | Date | QUERYABLE SORTABLE | No | **UNUSED** |
| `dismissedDate` | Date | QUERYABLE SORTABLE | No | **UNUSED** |
| `lastSeenWallClock` | Date | QUERYABLE SORTABLE | No | **UNUSED** |

### Summary count

| Record type | Fields | USED indexes | UNUSED indexes | of which BYTES (clear waste) |
|---|---|---|---|---|
| SavedGame | 13 | 3 (`status`, `mode`, `puzzleId`) | 10 | 3 (`notesState`, `undoStack`, `statusEnvelope`) |
| MonetizationState | 5 | 0 | 5 | 0 |
| **Total** | **18** | **3** | **15** | **3** |

No field is marked **TBD** — every field's query reachability is determinable from the two
predicate definitions and their only two call sites. (The issue listed several as "TBD audit";
this audit resolves all of them to USED/UNUSED.)

---

## 3. Cost framing for the unused-but-permanent indexes

Apple's rule: once a field is indexed in **Production**, the index cannot be dropped — only added.
So the 15 unused indexes above are **permanent**. The cost has two components, both *bounded per
user* because this is a private-database, per-account dataset (no global fan-out):

**(a) Storage** — each QUERYABLE/SORTABLE index is a per-record secondary structure (≈ the field's
indexed value + a record pointer). For the scalar/short-string fields (`elapsedSeconds`,
`schemaVersion`, `startedAt`, …) the per-record index entry is a handful of bytes; negligible.

**(b) Write-amplification** — this is the real recurring cost. `SavedGame` is written on **every
save tick** during active play (autosave + conflict-merge resubmits, `SavedGameStore.save`). Each
write must update *every* indexed field's index, including the ones never read. The BYTES fields
dominate here:
- `notesState`, `undoStack`, `statusEnvelope` are **JSON blobs** that change on essentially every
  move (notes toggles, undo pushes, status transitions). A QUERYABLE/SORTABLE index over a
  multi-hundred-byte blob means CloudKit re-indexes the full blob value on every save, for an index
  that **no predicate can ever use** (you cannot meaningfully `==`, `<`, or `BEGINSWITH` an opaque
  encoded blob). This is the textbook definition of wasted write-amplification.

**Bounded total:** there is exactly one `MonetizationState` record per account and a small set of
`SavedGame` records (one per active practice/daily puzzle, with stale dailies filtered/cleaned). So
the *aggregate* waste per user is small in absolute terms — but it is paid on the **hot save path**
and it is **forever**. Qualitative verdict: real but non-urgent; visible (if at all) only as a minor
write-cost line once CK Dashboard storage metrics are populated post-launch.

The single most defensible "this should never have been indexed" call-out:
**`notesState`, `undoStack`, `statusEnvelope` — BYTES blobs carrying QUERYABLE/SORTABLE indexes.**

---

## 4. Why "migrate to remove an index" is the *only* technical removal path

You cannot un-index a Production field. The only way to land a lean index set is to **write to new
field names** with the desired (or absent) index, migrate readers/writers to the new names, and
abandon the old fields. That is a full schema-v2 migration: new `SavedGameMapper` keys, a read
fallback window, a Production re-deploy, and dual-write/backfill for in-flight records. The old
indexed fields don't disappear — they just stop being written — so this *reduces future write-amp*
but does **not** reclaim the historical index storage.

---

## 5. Recommendation — live with it

**Live with it. Do not migrate.**

| | Live with it (recommended) | Migrate to lean field names |
|---|---|---|
| Eng cost | Zero | High — new schema version, dual-read fallback, backfill, Production re-deploy, regression risk on the conflict-merge hot path |
| Write-amp saved | None | Eliminates re-indexing of the 3 BYTES blobs + 12 scalar indexes on every save |
| Storage reclaimed | None | None for historical records (old fields persist) |
| User-visible benefit | None | None (no correctness or latency change; private per-user data) |
| Risk | None | Touches `SavedGameStore` save/merge — the exact code path most sensitive to bugs |

The cost is **bounded per user, tiny in absolute bytes, and incurred only on a private per-account
dataset**. The migration is a non-trivial change to the most conflict-sensitive store in the package,
for zero user-facing benefit and zero historical-storage reclamation. The asymmetry is decisive:
**accept the committed cost, do not migrate.**

**Guardrail for future schema work (the actionable takeaway):** the real lesson is *don't let the
next record type auto-infer indexes blindly.* When the next Production schema deploy happens (or if a
SavedGame schema-v2 is ever forced for unrelated reasons), declare BYTES fields and write-only scalar
fields as **non-indexed** explicitly, mirroring the `PersonalRecord` lean precedent (#243). That is
the only place this audit should influence a code change — and only opportunistically, never as its
own task.

---

## Appendix — sources read

- `Packages/PersistenceKit/Sources/Persistence/PrivateCKGateway.swift` — `RecordPredicate` cases.
- `Packages/PersistenceKit/Sources/Persistence/Live/LivePrivateCKGateway.swift` — `translate(predicate:)` NSPredicate construction; `fetch`/`save`/`delete`/`query` impls.
- `Packages/PersistenceKit/Sources/Persistence/Live/SavedGameStore.swift` — the only two `query(` call sites + `Field` key set.
- `Packages/PersistenceKit/Sources/Persistence/Live/SavedGameMapper.swift` — the 13 written `SavedGame` fields incl. `statusEnvelope`.
- `Packages/PersistenceKit/Sources/Persistence/Live/LiveMonetizationStateStore.swift` — the 5 `MonetizationState` fields + record-name-only fetch.
- `gh issue view 253` (deployed index shape); `gh pr view 243` (PersonalRecord lean precedent).
- `~/GitHub/Wei18/tmp/sudoku-full-schema.ckdb` — present on disk, NOT readable from this isolated worktree (see §1 note).
