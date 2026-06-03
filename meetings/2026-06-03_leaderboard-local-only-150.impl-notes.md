# Impl-notes — narrow LeaderboardLoader to local-player centring (#150)

## Decision: signature shape
Two options offered by Leader:
- (A) `aroundLocalPlayer: Bool` (true = centre on local player, false = top-of-board)
- (B) keep a param but rename/retype it

Chose **(A) `aroundLocalPlayer: Bool`**. Rationale:
- The live `GKLeaderboardLoader` already only branches on `player != nil` and
  always substitutes `GKLocalPlayer.local`. The string payload was never read.
  A `Bool` makes the real capability ("centre on the local player, or not")
  explicit and impossible to misuse — no caller can pass an id we silently drop.
- (B) would preserve a `String`/id-shaped param that still *looks* like it
  accepts an arbitrary player, i.e. the exact dishonesty CR S3 flagged.

## Scope expansion vs the dispatch brief
Brief scoped only `LeaderboardLoader.loadSlice`. But the dishonest `around
player: String?` runs the full chain:

  GameCenterClient.fetchLeaderboardSlice (VM-facing public protocol)
    -> LeaderboardSliceService.fetch
      -> LeaderboardLoader.loadSlice (live: GKLeaderboardLoader)

Narrowing only the loader would leave the *most visible* surface
(`GameCenterClient.fetchLeaderboardSlice(around: String?)`) still lying. So I
narrowed the whole chain to `aroundLocalPlayer: Bool`. Conformers/callers
updated: GameCenterClient protocol, LiveGameCenterClient, GKLeaderboardLoader,
LeaderboardSliceService, FakeGameCenterClient, FakeLeaderboardLoader,
CompletionViewModel (SudokuKit), + all tests.

## Default value
`aroundLocalPlayer: Bool = false` on the public protocol methods so the common
"top of the world" call (CompletionViewModel) can drop the argument; matches the
prior `around: nil` default intent.

## Test semantics change
FakeLeaderboardLoader.Call.around: String? -> aroundLocalPlayer: Bool, and
FakeGameCenterOperation.fetchLeaderboardSlice gains aroundLocalPlayer: Bool so
tests assert local-vs-top rather than an arbitrary id string. The old
`aroundPlayerPassesPlayerThrough` test (asserting `calls[0].around == "P50"`)
is now `aroundLocalPlayerFlagPassesThrough` asserting the Bool.
