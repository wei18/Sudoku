// DailyRankModels — value types for the shared Daily Rank screen (#983).
//
// The screen shows the daily recurring leaderboards both apps already submit
// to (Sudoku's `LeaderboardKind.daily*` / Minesweeper's
// `MinesweeperLeaderboardID.daily(for:)`), World vs Friends scoped, per
// difficulty. GameAppKit stays free of either app's own difficulty enum —
// each app hands in its own `[DailyRankTab]` (id + localized title key +
// resolved leaderboard id) at composition time.

public import SwiftUI
public import GameCenterClient

/// One difficulty tab: a stable id (cache key), the localized title shown on
/// the segmented control, and the leaderboard id it queries. `titleKey`
/// deliberately reuses each app's EXISTING difficulty-name catalog entries
/// (Sudoku: "Easy"/"Medium"/"Hard"; Minesweeper: "Beginner"/"Intermediate"/
/// "Expert") — no new difficulty-name strings are introduced by this screen.
///
/// Not `Sendable`: `LocalizedStringKey` (like `HomeModeContent.subtitleKey`)
/// isn't Sendable either. `DailyRankTab` only ever crosses into the
/// `@MainActor`-isolated `DailyRankViewModel`, so this mirrors that existing
/// precedent rather than needing its own workaround.
public struct DailyRankTab: Identifiable, Equatable {
    public let id: String
    public let titleKey: LocalizedStringKey
    public let leaderboardId: String

    public init(id: String, titleKey: LocalizedStringKey, leaderboardId: String) {
        self.id = id
        self.titleKey = titleKey
        self.leaderboardId = leaderboardId
    }
}

/// World vs Friends scope toggle. Maps to `LeaderboardScope.globalAllTime` /
/// `.friendsAllTime` at fetch time — `GameCenterClient.swift:119-122`.
public enum DailyRankScope: String, CaseIterable, Sendable, Equatable, Identifiable {
    case world
    case friends

    public var id: String { rawValue }

    public var titleKey: LocalizedStringKey {
        switch self {
        case .world: return "World"
        case .friends: return "Friends"
        }
    }
}

/// A resolved fetch for one (tab, scope): the top slice plus — when the local
/// player isn't already inside it — a separately-fetched own-rank entry
/// (`aroundLocalPlayer: true`). Per #983 §How: "top slice + the local
/// player's own rank/time".
public struct DailyRankResult: Sendable, Equatable {
    public let topEntries: [LeaderboardEntry]
    public let localPlayerEntry: LeaderboardEntry?
    public let localPlayerId: String?

    public init(
        topEntries: [LeaderboardEntry],
        localPlayerEntry: LeaderboardEntry?,
        localPlayerId: String?
    ) {
        self.topEntries = topEntries
        self.localPlayerEntry = localPlayerEntry
        self.localPlayerId = localPlayerId
    }

    /// `true` when the local player's own entry is already inside
    /// `topEntries` — the view then renders no separate "Your Rank" section.
    public var localPlayerInTop: Bool {
        guard let localPlayerId else { return false }
        return topEntries.contains { $0.player.teamPlayerId == localPlayerId }
    }
}

/// Per (tab, scope) load state. `.failed(.notSignedIn)` / `.friendsNotAuthorized`
/// are first-class explainer states, never a blank view — #983 §States 1/2.
public enum DailyRankLoadState: Equatable {
    case idle
    case loading
    case loaded(DailyRankResult)
    case failed(DailyRankFailure)
}

/// Why a (tab, scope) load didn't produce a result. `.notSignedIn` and
/// `.friendsNotAuthorized` are pre-flight checks against `authState` /
/// `friendsAuthorizationStatus()` (never hit GameKit); `.network` covers
/// every other throw from `fetchLeaderboardSlice` (offline, GameKit error).
public enum DailyRankFailure: Sendable, Equatable {
    case notSignedIn
    case friendsNotAuthorized
    case network
}
