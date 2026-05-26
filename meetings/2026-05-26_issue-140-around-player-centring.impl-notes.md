# Issue #140 — Around-player leaderboard centring

## Scope decision (applied per Leader pre-research, 2026-05-26)
- `around: String?` (teamPlayerID) cannot be cheaply converted to a `GKPlayer`
  instance: `GKPlayer.loadPlayers(forIdentifiers:)` takes `gamePlayerID`,
  not `teamPlayerID`.
- **Narrowed scope**: when `around != nil`, use `GKLocalPlayer.local` for the
  rank-lookup call. This covers the realistic production use case
  (CompletionView centres on the LOCAL player). If a future feature ever
  needs "centre around ANOTHER player", file a follow-up issue.
- Documented in code comment on `GKLeaderboardLoader.loadSlice`.

## Testability seam
- `GKLeaderboardLoader.loadSlice` calls real `GKLeaderboard`; no protocol
  seam exists for the live adapter (by design — `FakeLeaderboardLoader`
  replaces the whole adapter in tests).
- New range-arithmetic is extracted as a pure static helper
  `GKLeaderboardLoader.makeRange(centeredOnRank:limit:)` so it can be unit
  tested without GameKit. The "two-call sequence" branching itself is left
  to Phase 10 manual device validation (consistent with the file's
  pre-existing "COMPILE-ONLY in this phase" stance).

## Tests added
In a new file `GKLeaderboardLoaderRangeTests.swift` (NOT the Service-wiring
test file, since the existing tests don't reach the adapter):

1. `centresWindowOnRank` — rank 50, limit 8 → `NSRange(location: 46, length: 8)`
2. `clampsToOneWhenRankNearTop` — rank 2, limit 8 → `NSRange(location: 1, length: 8)`
3. `fallbackToTopNWhenNoRank` — rank nil → `NSRange(location: 1, length: 8)`

Existing 3 `LiveGameCenterClientLeaderboardSliceTests` continue to pass
(unchanged `LeaderboardSliceService` shape).

## Out of scope (per issue body)
- Friends-scope auth gating — pre-existing limitation, separate issue
- CompletionView UI changes — consumers already pass `around: player`
