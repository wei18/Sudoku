// LiveRouteFactory — Tiles2048's concrete `RouteFactory<AppRoute>`.
//
// Mirrors MinesweeperKit.LiveRouteFactory. Thinner than MS (no audio, no
// reminders in M4) but identical structure and optionality discipline. The
// factory exists for the same shape reason: keep `Game2048Root.init` at one
// argument (the factory) even as destination construction grows.
//
// SDD-003 Epic 1 two-context board contract (mirrors MinesweeperKit #491):
//   push context  (path != nil): GameBoardRedirect → modal via onPresentBoard.
//   modal context (path == nil): GameRoot builds modal content inline here;
//     the redirect must NOT fire or the modal shows Color.clear.

public import SwiftUI
public import GameCenterClient
public import GameShellUI
public import GameAppKit
public import Game2048UI
public import MonetizationCore
public import MonetizationUI
public import Game2048Persistence
public import Persistence
public import Telemetry
public import SettingsUI

internal import Foundation
#if canImport(UIKit)
internal import UIKit
#endif

public struct LiveRouteFactory: RouteFactory {
    public typealias Route = AppRoute

    private let monetizationController: MonetizationStateController?
    private let persistence: (any PersistenceProtocol)?
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    private let gameCenter: (any GameCenterClient)?
    private let errorReporter: (any ErrorReporter)?
    private let toastController: ToastController?
    // M4: saved-game store, threaded into boards and .resumeBoard loader.
    private let savedGameStore: Game2048SavedGameStore?
    // SDD-003 Epic 1: closure that modal-presents a board route.
    private let onPresentBoard: (@MainActor (AppRoute) -> Void)?

    public init(
        monetizationController: MonetizationStateController? = nil,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        persistence: (any PersistenceProtocol)? = nil,
        gameCenter: (any GameCenterClient)? = nil,
        errorReporter: (any ErrorReporter)? = nil,
        toastController: ToastController? = nil,
        savedGameStore: Game2048SavedGameStore? = nil,
        onPresentBoard: (@MainActor (AppRoute) -> Void)? = nil
    ) {
        self.monetizationController = monetizationController
        self.adProvider = adProvider
        self.adGate = adGate
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.errorReporter = errorReporter
        self.toastController = toastController
        self.savedGameStore = savedGameStore
        self.onPresentBoard = onPresentBoard
    }

    @MainActor
    public func view(for route: AppRoute, path: Binding<[AppRoute]>?) -> AnyView {
        switch route {
        case .daily:
            return AnyView(
                Game2048DailyHubView(
                    path: path ?? .constant([]),
                    banner: { bannerSlot() }
                )
            )
        case .practice:
            return AnyView(
                Game2048PracticeHubView(
                    path: path ?? .constant([]),
                    banner: { bannerSlot() }
                )
            )
        case .board(let seed, let mode):
            // SDD-003 Epic 1 / #491 / #559: two-context board contract delegated
            // to shared `boardDestination` helper in GameAppKit.
            // Build a fully-wired VM (with persistence + GC seams), then hand
            // the VM to the view. This keeps Game2048BoardView's public surface
            // minimal — it always takes a pre-built VM, not raw seed+mode+deps.
            let recordName = Game2048SavedGameStore.recordName(modeRaw: mode.rawValue)
            let viewModel = Game2048GameViewModel(
                seed: seed,
                mode: mode,
                gameCenter: gameCenter,
                errorReporter: errorReporter,
                store: savedGameStore,
                recordName: savedGameStore != nil ? recordName : nil
            )
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                AnyView(
                    Game2048BoardView(
                        viewModel: viewModel,
                        adProvider: self.adProvider,
                        adGate: self.adGate
                    )
                )
            }
        case .resumeBoard(let recordName, let mode):
            // #491 / #559: same two-context contract as .board, delegated to helper.
            return boardDestination(
                route: route,
                path: path,
                onPresentBoard: onPresentBoard
            ) {
                guard let savedGameStore = self.savedGameStore else { return AnyView(EmptyView()) }
                return AnyView(
                    Game2048BoardLoaderView(
                        recordName: recordName,
                        mode: mode,
                        store: savedGameStore,
                        adProvider: self.adProvider,
                        adGate: self.adGate,
                        gameCenter: self.gameCenter,
                        errorReporter: self.errorReporter
                    )
                )
            }
        case .settings:
            let version = (Bundle.main
                .object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String)
                ?? "1.0.0"
            let persistence = self.persistence
            let errorReporter = self.errorReporter
            let toastController = self.toastController
            return AnyView(
                Game2048SettingsView(
                    version: version,
                    clearCache: {
                        await Self.clearCache(
                            persistence: persistence,
                            errorReporter: errorReporter,
                            toastController: toastController
                        )
                    },
                    monetizationController: monetizationController,
                    notices: Self.makeSettingsNotices(),
                    banner: { bannerSlot() }
                )
            )
        }
    }

    // MARK: - Banner helper

    /// Epic 5: banner slot for non-Home, non-Board screens. The cast from
    /// `AdProvider` → `BannerViewProviding` follows the §9.1 pattern (keeps
    /// Game2048AppComposition off GoogleMobileAds).
    @MainActor
    private func bannerSlot() -> some View {
        if let adProvider, let adGate {
            AnyView(
                BannerSlotView(
                    adProvider: adProvider,
                    adGate: adGate,
                    bannerHost: adProvider as? any BannerViewProviding
                )
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            )
        } else {
            AnyView(EmptyView())
        }
    }

    // MARK: - Notices

    @MainActor
    internal static func makeSettingsNotices() -> SettingsNoticesConfig {
        let year = Calendar.current.component(.year, from: Date())
        var onAcknowledgements: (@MainActor () -> Void)?
        #if canImport(UIKit)
        onAcknowledgements = {
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        }
        #endif
        return SettingsNoticesConfig(
            onAcknowledgements: onAcknowledgements,
            copyright: "© \(year) Wei"
        )
    }

    // MARK: - Clear cache

    @MainActor
    static func clearCache(
        persistence: (any PersistenceProtocol)?,
        errorReporter: (any ErrorReporter)?,
        toastController: ToastController?
    ) async {
        guard let persistence else { return }
        do {
            if let candidate = try await persistence.latestInProgress() {
                try await persistence.deleteAbandoned(recordName: candidate.recordName)
            }
            toastController?.show(
                Toast(
                    style: .success,
                    message: String(localized: "Cache cleared", bundle: .main)
                )
            )
        } catch {
            await errorReporter?.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "LiveRouteFactory.clearCache"
            )
            toastController?.show(
                Toast(
                    style: .failure,
                    message: String(localized: "Couldn't clear cache", bundle: .main)
                )
            )
        }
    }

    // MARK: - Navigation helpers

    @MainActor
    internal static func popToNewGame(path: Binding<[AppRoute]>?) {
        path?.wrappedValue.removeAll()
    }
}
