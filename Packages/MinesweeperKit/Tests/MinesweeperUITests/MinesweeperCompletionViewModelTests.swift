// swiftlint:disable identifier_name
//
// MinesweeperCompletionViewModelTests — post-game Completion surface (#292).
//
// Covers the VM that backs `MinesweeperCompletionView`:
//   - win  → fetches a local-player-centred leaderboard slice (#150 path) and
//            settles on `.loaded`.
//   - loss → stays hero-only (no fetch, `.unauthenticated` affordance).
//   - nil client (MVP / preview) → `.unauthenticated`, never spins.
//   - degrade states (`.failed` / `.unauthenticated`) via the testing seam,
//     mirroring Sudoku's CompletionViewTests (FakeGameCenterClient has no
//     fetch-error knob, so the degrade transitions are seeded directly).
//   - bootstrap idempotency (the `.task` re-entry must not re-fetch).

import Foundation
import Testing
@testable import MinesweeperUI
import MinesweeperEngine
import GameCenterClient
import GameCenterTesting

@MainActor
@Suite("MinesweeperCompletionViewModel — post-game surface")
struct MinesweeperCompletionViewModelTests {

    private static let sampleSlice = LeaderboardSlice(
        leaderboardId: MinesweeperLeaderboardID.easyDaily,
        scope: .globalAllTime,
        entries: [
            LeaderboardEntry(rank: 1, player: PlayerSummary(teamPlayerId: "P1", displayName: "alice"), score: 41),
            LeaderboardEntry(rank: 2, player: PlayerSummary(teamPlayerId: "P2", displayName: "bob"), score: 55),
            LeaderboardEntry(rank: 3, player: PlayerSummary(teamPlayerId: "P3", displayName: "carol"), score: 73),
        ],
        totalPlayerCount: 900,
        fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    private func makeViewModel(
        didWin: Bool = true,
        elapsedSeconds: Int = 65,
        gameCenter: (any GameCenterClient)? = FakeGameCenterClient()
    ) -> MinesweeperCompletionViewModel {
        MinesweeperCompletionViewModel(
            didWin: didWin,
            elapsedSeconds: elapsedSeconds,
            leaderboardId: MinesweeperLeaderboardID.easyDaily,
            gameCenter: gameCenter
        )
    }

    // MARK: - Win → completion state

    @Test func winBootstrapLoadsSlice() async {
        let fake = FakeGameCenterClient()
        await fake.setLeaderboardSlice(Self.sampleSlice)
        let vm = makeViewModel(didWin: true, gameCenter: fake)

        await vm.bootstrap()

        if case .loaded(let slice) = vm.state {
            #expect(slice.entries.count == 3)
        } else {
            Issue.record("expected .loaded, got \(vm.state)")
        }
    }

    @Test func winFetchesAroundLocalPlayer() async {
        // #150 / #292: the slice must be centred on the local player.
        let fake = FakeGameCenterClient()
        await fake.setLeaderboardSlice(Self.sampleSlice)
        let vm = makeViewModel(didWin: true, gameCenter: fake)

        await vm.bootstrap()

        let ops = await fake.operations
        let fetches = ops.compactMap { op -> (Bool, String)? in
            if case let .fetchLeaderboardSlice(id, _, around, _) = op { return (around, id) }
            return nil
        }
        #expect(fetches.count == 1)
        #expect(fetches.first?.0 == true)
        #expect(fetches.first?.1 == MinesweeperLeaderboardID.easyDaily)
    }

    @Test func didWinAndElapsedAreExposedForHero() {
        let vm = makeViewModel(didWin: true, elapsedSeconds: 125)
        #expect(vm.didWin == true)
        #expect(vm.elapsedSeconds == 125)
    }

    // MARK: - Loss → hero only, no fetch

    @Test func lossDoesNotFetchSlice() async {
        let fake = FakeGameCenterClient()
        let vm = makeViewModel(didWin: false, gameCenter: fake)

        await vm.bootstrap()

        // No score to rank on a loss → no fetch, hero-only affordance.
        let ops = await fake.operations
        let fetched = ops.contains {
            if case .fetchLeaderboardSlice = $0 { return true }
            return false
        }
        #expect(fetched == false)
        #expect(vm.state == .unauthenticated)
    }

    // MARK: - nil client (MVP / preview)

    @Test func nilClientDegradesToUnauthenticated() async {
        let vm = makeViewModel(didWin: true, gameCenter: nil)
        await vm.bootstrap()
        #expect(vm.state == .unauthenticated)
    }

    // MARK: - Degrade states (mirror Sudoku — seeded via testing seam)

    @Test func failedStateSurvivesBootstrapReEntry() async {
        let vm = makeViewModel()
        vm.setStateForTesting(.failed("network offline"))
        // The `.task` re-entry must NOT overwrite a settled degrade state.
        await vm.bootstrap()
        #expect(vm.state == .failed("network offline"))
    }

    @Test func unauthenticatedStateSurvivesBootstrapReEntry() async {
        let vm = makeViewModel()
        vm.setStateForTesting(.unauthenticated)
        await vm.bootstrap()
        #expect(vm.state == .unauthenticated)
    }

    @Test func retryClearsLatchAndReFetches() async {
        // After a failure, Retry must re-enter the fetch exactly once more.
        let fake = FakeGameCenterClient()
        await fake.setLeaderboardSlice(Self.sampleSlice)
        let vm = makeViewModel(didWin: true, gameCenter: fake)

        vm.setStateForTesting(.failed("boom"))
        await vm.retry()

        if case .loaded = vm.state {
            // expected
        } else {
            Issue.record("expected .loaded after retry, got \(vm.state)")
        }
        let ops = await fake.operations
        let fetchCount = ops.filter {
            if case .fetchLeaderboardSlice = $0 { return true }
            return false
        }.count
        #expect(fetchCount == 1)
    }

    // MARK: - Bootstrap idempotency

    @Test func bootstrapFetchesOnceAcrossReEntries() async {
        let fake = FakeGameCenterClient()
        await fake.setLeaderboardSlice(Self.sampleSlice)
        let vm = makeViewModel(didWin: true, gameCenter: fake)

        await vm.bootstrap()
        await vm.bootstrap()
        await vm.bootstrap()

        let ops = await fake.operations
        let fetchCount = ops.filter {
            if case .fetchLeaderboardSlice = $0 { return true }
            return false
        }.count
        #expect(fetchCount == 1)
    }

    // MARK: - CTA route
    //
    // `viewLeaderboardTapped()` reaches the shared `GameCenterDashboard.present`,
    // which hits Apple's `GKAccessPoint.shared` singleton — not faked / asserted
    // from unit scope without a UI host (it would actually trigger the system
    // dashboard on macOS). Exercised manually in sandbox validation, mirroring
    // Sudoku's CompletionViewTests note (#49). The route is covered by the
    // `leaderboardId` plumbing assertions in `MinesweeperGameCenterSubmitTests`
    // (`leaderboardIdSchemeIsVersionSuffixed`).
}

// swiftlint:enable identifier_name
