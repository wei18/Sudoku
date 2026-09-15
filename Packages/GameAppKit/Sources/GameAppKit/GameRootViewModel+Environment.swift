// GameRootViewModel+Environment — the environment keys `GameRoot` injects so
// route views can `.onChange` this VM's state without holding a direct
// reference to it. Split out of `GameRootViewModel.swift` purely to keep that
// file under the 400-line `file_length` ceiling (same rationale as
// `DailyHubViewModel+Testing.swift`).

public import SwiftUI
public import GameShellUI
internal import MonetizationUI

// MARK: - EnvironmentKey (#761)

private struct GameSessionTeardownCountKey: EnvironmentKey {
    static let defaultValue: Int = 0
}

public extension EnvironmentValues {
    /// `GameRootViewModel.sessionTeardownCount`, injected by `GameRoot` so any
    /// route view can `.onChange` it to react to a game session ending — the
    /// explicit signal Daily hub refresh (#761) rides instead of `.onAppear`,
    /// which does not re-fire when a `fullScreenCover` dismisses.
    var gameSessionTeardownCount: Int {
        get { self[GameSessionTeardownCountKey.self] }
        set { self[GameSessionTeardownCountKey.self] = newValue }
    }
}

// MARK: - EnvironmentKey (#1021 CR3b)

private struct GameSelectedTabKey: EnvironmentKey {
    static let defaultValue: AppTab = .today
}

public extension EnvironmentValues {
    /// `GameRootViewModel.selectedTab`, injected by `GameRoot` so a tab root
    /// can `.onChange` it to react to becoming the active tab again.
    ///
    /// Exists alongside `gameSessionTeardownCount` for a case that signal
    /// cannot cover: a phase-1 Daily-load failure means the player never
    /// started a game session at all, so `sessionTeardownCount` may never
    /// bump (it only would if they happened to play a game from Practice).
    /// Simply switching back to Today is the recovery path a real player
    /// actually takes, so route views that need to react to THAT read this
    /// key instead. Read-only by design — a tab switch itself carries no
    /// side effects (§3.6.2 / N-AB); this key exists so a view can OBSERVE
    /// the switch, never drive it.
    var gameSelectedTab: AppTab {
        get { self[GameSelectedTabKey.self] }
        set { self[GameSelectedTabKey.self] = newValue }
    }
}

// MARK: - EnvironmentKey (#1080)

private struct BannerAccessoryLeaseKey: EnvironmentKey {
    static let defaultValue: BannerSlotLease? = nil
}

// `internal` (not `public`, unlike the other environment keys above): only
// `GameRoot` (injects it) and `BannerAccessoryView` (reads it) use this key,
// both inside GameAppKit — #1080 CR (over-public API).
extension EnvironmentValues {
    /// The `tabViewBottomAccessory` capsule's banner lease, injected by
    /// `GameRoot` (scene-lifetime `@State`) so `BannerAccessoryView` can keep
    /// its registration stable across the accessory's native re-hosting of
    /// its content (#1080 — see `meetings/2026-09-11_1058-slot-model-design.md`
    /// §"Externally owned lease (#1080)").
    /// `nil` for any other host: every OTHER slot keeps its own self-owned
    /// lease via `BannerSlotView`'s default init.
    var bannerAccessoryLease: BannerSlotLease? {
        get { self[BannerAccessoryLeaseKey.self] }
        set { self[BannerAccessoryLeaseKey.self] = newValue }
    }
}
