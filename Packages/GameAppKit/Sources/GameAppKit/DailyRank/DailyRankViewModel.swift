// DailyRankViewModel — shared Daily Rank screen VM (#983).
//
// Owns tab (difficulty) + scope (World/Friends) selection, a per-(tab,scope)
// load-state cache, and the four first-class states from the approved spec
// (github.com/wei18/Sudoku#983 comment): not-signed-in, friends-not-
// authorized, populated-but-empty, and populated. Injected with a single
// `any GameCenterClient` — the same DI shape `GameRootViewModel` already
// uses (constructor injection, no singleton) — so a fresh instance can be
// wired at the `.dailyRank` route without threading GameRootViewModel itself
// through GameAppKit's leaf screen.
//
// Not generic over `Route`: this screen never pushes further routes (it only
// side-effects via `GameCenterDashboard.present`), so it stays a concrete
// type — simpler call sites in both apps' `LiveRouteFactory`.

public import SwiftUI
public import GameCenterClient

@MainActor
@Observable
public final class DailyRankViewModel {
    public let tabs: [DailyRankTab]
    public var selectedTabId: String
    public var selectedScope: DailyRankScope = .world

    public private(set) var authState: GameCenterAuthState

    private let gameCenter: any GameCenterClient
    private var cache: [CacheKey: DailyRankLoadState] = [:]

    private struct CacheKey: Hashable {
        let tabId: String
        let scope: DailyRankScope
    }

    /// - Parameters:
    ///   - gameCenter: game-agnostic GC seam; each app's `LiveRouteFactory`
    ///     already holds one and forwards it here.
    ///   - tabs: per-game difficulty tabs, in display order. Must be non-empty.
    ///   - initialAuthState: snapshot of `GameRootViewModel.authState` at the
    ///     moment the route was pushed — avoids a redundant `authenticate()`
    ///     call (bootstrap already ran one); `signIn()` below re-authenticates
    ///     on demand if this snapshot reads not-authenticated.
    public init(
        gameCenter: any GameCenterClient,
        tabs: [DailyRankTab],
        initialAuthState: GameCenterAuthState
    ) {
        precondition(!tabs.isEmpty, "DailyRankViewModel requires at least one tab")
        self.gameCenter = gameCenter
        self.tabs = tabs
        self.selectedTabId = tabs[0].id
        self.authState = initialAuthState
    }

    public var selectedTab: DailyRankTab {
        tabs.first { $0.id == selectedTabId } ?? tabs[0]
    }

    public var state: DailyRankLoadState {
        cache[CacheKey(tabId: selectedTabId, scope: selectedScope)] ?? .idle
    }

    // MARK: - Selection

    public func selectTab(_ id: String) {
        guard id != selectedTabId else { return }
        selectedTabId = id
        Task { await loadIfNeeded() }
    }

    public func selectScope(_ scope: DailyRankScope) {
        guard scope != selectedScope else { return }
        selectedScope = scope
        Task { await loadIfNeeded() }
    }

    // MARK: - Lifecycle

    public func onAppear() async {
        await loadIfNeeded()
    }

    public func retry() async {
        cache[CacheKey(tabId: selectedTabId, scope: selectedScope)] = nil
        await loadIfNeeded()
    }

    // MARK: - State 1: sign in

    public func signIn() async {
        do {
            authState = try await gameCenter.authenticate()
        } catch {
            authState = .unauthenticated
        }
        guard case .authenticated = authState else { return }
        // A fresh sign-in can change every cached result (e.g. friends scope
        // now resolvable) — drop the whole cache rather than just this key.
        cache.removeAll()
        await loadIfNeeded()
    }

    // MARK: - State 2: friends grant path

    public func requestFriendsAccess() async {
        _ = try? await gameCenter.requestFriendsAuthorization()
        cache[CacheKey(tabId: selectedTabId, scope: .friends)] = nil
        await loadIfNeeded()
    }

    // MARK: - Secondary affordance

    public func openGameCenter() {
        GameCenterDashboard.present(leaderboardId: selectedTab.leaderboardId)
    }

    // MARK: - Load

    private func loadIfNeeded() async {
        let key = CacheKey(tabId: selectedTabId, scope: selectedScope)
        if case .loaded = cache[key] { return }
        await load(tab: selectedTab, scope: selectedScope, key: key)
    }

    private func load(tab: DailyRankTab, scope: DailyRankScope, key: CacheKey) async {
        cache[key] = .loading

        guard case .authenticated(let localPlayer) = authState else {
            commit(.failed(.notSignedIn), for: key)
            return
        }

        let gkScope: LeaderboardScope
        if scope == .friends {
            let friendsStatus = await gameCenter.friendsAuthorizationStatus()
            guard friendsStatus == .authorized else {
                commit(.failed(.friendsNotAuthorized), for: key)
                return
            }
            gkScope = .friendsAllTime
        } else {
            gkScope = .globalAllTime
        }

        do {
            let top = try await gameCenter.fetchLeaderboardSlice(
                leaderboardId: tab.leaderboardId,
                scope: gkScope,
                aroundLocalPlayer: false,
                limit: 10
            )
            var localEntry = top.entries.first { $0.player.teamPlayerId == localPlayer.teamPlayerId }
            if localEntry == nil {
                // Local player wasn't in the top slice — a second,
                // player-centred fetch resolves their own rank/time
                // (`LeaderboardLoader.loadSlice(aroundLocalPlayer:)` doc,
                // GameCenterKit/Sources/GameCenterClient/Leaderboard/Slice.swift).
                let own = try? await gameCenter.fetchLeaderboardSlice(
                    leaderboardId: tab.leaderboardId,
                    scope: gkScope,
                    aroundLocalPlayer: true,
                    limit: 5
                )
                localEntry = own?.entries.first { $0.player.teamPlayerId == localPlayer.teamPlayerId }
            }
            commit(.loaded(DailyRankResult(
                topEntries: top.entries,
                localPlayerEntry: localEntry,
                localPlayerId: localPlayer.teamPlayerId
            )), for: key)
        } catch {
            commit(.failed(.network), for: key)
        }
    }

    /// Only writes the result if the user hasn't switched tab/scope while the
    /// fetch was in flight — a stale response must not clobber the state of
    /// whatever the user is looking at now. `loadIfNeeded` re-fires the fetch
    /// for the current selection independently, so nothing is left stuck.
    private func commit(_ state: DailyRankLoadState, for key: CacheKey) {
        guard key == CacheKey(tabId: selectedTabId, scope: selectedScope) else { return }
        cache[key] = state
    }
}
