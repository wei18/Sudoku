// AppComposition — DI composition root (docs/v1/design.md §How.1).
//
// Three factory methods produce a fully-wired `AppComposition` for the
// three environments the App needs to run in:
//
//   - `.live()`    — CloudKit / GameKit / OSLog / AdMob / StoreKit2 wiring.
//   - `.preview()` — SwiftUI Preview fakes (no IO).
//   - `.tests()`   — Unit / snapshot test fakes (no IO).
//
// The App target depends only on this product; `SudokuApp.body` reads
// the bag's properties and hands them to `RootView`.
//
// Stored shape (v2.3.3):
//   - `rootViewModel` + `routeFactory` are what `RootView.init` reads.
//   - The remaining protocol deps (puzzleProvider / persistence / gameCenter
//     / telemetry / adProvider / iapClient / adGate) stay accessible on the
//     bag for callers that need direct references (e.g. App-level boot order
//     in v2.3.7, individual destination views that escape the RouteFactory
//     such as HomeView's Game Center modal callback in v2.3.4-6).

internal import AdsAdMob
internal import Foundation
public import GameCenterClient
public import GameShellUI
public import MonetizationCore
public import MonetizationUI
public import Persistence
public import PuzzleStore
public import SudokuUI
public import SwiftUI
public import Telemetry

@MainActor
public struct AppComposition {
    public let rootViewModel: RootViewModel
    public let routeFactory: any RouteFactory<AppRoute>
    public let puzzleProvider: any PuzzleProviderProtocol
    public let persistence: any PersistenceProtocol
    public let gameCenter: any GameCenterClient
    public let telemetry: Telemetry
    /// M10 (issue #67): unified error funnel. Live wiring constructs a
    /// `LiveErrorReporter` over the shared `Telemetry` actor; `.preview()`
    /// and `.tests()` wire `NoopErrorReporter`. VMs that previously
    /// `try?`-swallowed CloudKit / Persistence errors now route through
    /// this reporter so failures surface in OSLog + telemetry breadcrumbs.
    public let errorReporter: any ErrorReporter
    // v2 monetization deps. v2.3.4-6 read these directly from individual Views
    // (banner slot, IAP CTAs, restore button); v2.3.7 reads them to drive the
    // UMP → ATT → AdMob boot sequence.
    public let adProvider: any AdProvider
    public let iapClient: any IAPClient
    public let adGate: AdGate
    // v2.3.6: the persisted MonetizationState store + the shared @Observable
    // controller derived from it. Settings + HomeView read the controller
    // directly; `monetizationStateStore` stays exposed so future Views
    // (e.g. v2.4 purchase entry from CompletionView) can rebuild a controller
    // without re-routing through Persistence.
    public let monetizationStateStore: any AdGateStateStore
    public let monetizationController: MonetizationStateController
    // v2.4.5: shared toast surface. RootView mounts this as a bottom overlay;
    // MonetizationStateController pushes success / failure toasts on purchase
    // and restore (and on out-of-band `purchaseUpdates()` events).
    public let toastController: ToastController
    // #371 / #195: ATT pre-prompt coordinator. Built in `.live()` (wired to
    // `ATTPresenter`); `nil` in `.preview()` / `.tests()`. RootView forwards it
    // to HomeView's banner slot (the trigger) and binds the priming sheet.
    // Sudoku-only — Minesweeper has no equivalent (it never prompts ATT).
    public let attPrimer: ATTPrimerCoordinator?

    // MARK: - Root view accessor (#244)

    /// Composed root view ready to mount in `@main`'s `WindowGroup`. Wires
    /// `RootView` with this bag's deps and attaches the v2.3.7 monetization
    /// boot `.task`. Mirrors the shape `MinesweeperAppComposition.rootView`
    /// uses in PR #242 — `SudokuApp.body` now reads as one expression.
    public var rootView: some View {
        RootView(
            viewModel: rootViewModel,
            routeFactory: routeFactory,
            adProvider: adProvider,
            adGate: adGate,
            monetizationController: monetizationController,
            toastController: toastController,
            attPrimer: attPrimer
        )
        // #278 Tier-1 Phase 1: the `@Environment(\.theme)` key moved to
        // GameShellUI, whose neutral fallback default is intentionally NOT
        // Sudoku's palette. Inject Sudoku's concrete `DefaultTheme` here at
        // the composition root so every mounted view resolves the sage /
        // warm-paper tokens exactly as before (zero visual change).
        .environment(\.theme, DefaultTheme())
        // #278 Tier-1 Phase 2a: cell tokens are Sudoku-shaped and were pulled
        // out of the generic `Theme` protocol into SudokuUI's `\.sudokuCell`
        // env key. Inject the same concrete cell palette here so board cells
        // render byte-identically. (Minesweeper injects its own in Phase 2b.)
        .environment(\.sudokuCell, DefaultTheme().cell)
        // `.onAppear { Task { … } }` not `.task { … }`: Xcode 26 lowers every
        // `.task` overload to `task(name:…)`, whose opaque descriptor links
        // undefined in the arm64 device Release archive. This boot is one-shot
        // (BannerSlotView is honest about deferred state), so disappear-
        // cancellation isn't needed. See #361.
        .onAppear { Task {
            // v2.3.7: kick the boot sequence concurrent with the first frame.
            // `BannerSlotView` is honest about deferred state (shows `.failed`
            // if AdMob has not yet initialized) so this never blocks UI.
            //
            // #371 / #195: ATT no longer fires here. design.md §How.4 forbids a
            // cold-launch ATT prompt — it must come after Home is seen and at
            // the first ad-relevant moment. Boot now runs UMP (GDPR consent
            // stays early, F4) → AdMob init only; ATT is deferred to the
            // `ATTPrimerCoordinator`, triggered from BannerSlotView when the
            // ad gate opens.
            await bootMonetization()
        } }
        // #510: DEBUG-only near-win hook. When launched with `-uitest-near-win`,
        // present a board that is one digit entry from winning immediately over
        // the normal root — bypasses persistence, GameCenter, and monetization
        // entirely. Compiled out of Release builds by the `#if DEBUG` guard.
        #if DEBUG
        .modifier(SudokuNearWinModifier())
        #endif
    }

    public init(
        rootViewModel: RootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
        puzzleProvider: any PuzzleProviderProtocol,
        persistence: any PersistenceProtocol,
        gameCenter: any GameCenterClient,
        telemetry: Telemetry,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        adProvider: any AdProvider,
        iapClient: any IAPClient,
        adGate: AdGate,
        monetizationStateStore: any AdGateStateStore,
        monetizationController: MonetizationStateController,
        toastController: ToastController,
        attPrimer: ATTPrimerCoordinator? = nil
    ) {
        self.rootViewModel = rootViewModel
        self.routeFactory = routeFactory
        self.puzzleProvider = puzzleProvider
        self.persistence = persistence
        self.gameCenter = gameCenter
        self.telemetry = telemetry
        self.errorReporter = errorReporter
        self.adProvider = adProvider
        self.iapClient = iapClient
        self.adGate = adGate
        self.monetizationStateStore = monetizationStateStore
        self.monetizationController = monetizationController
        self.toastController = toastController
        self.attPrimer = attPrimer
    }

    // MARK: - v2.3.7 boot order

    /// App-launch monetization boot. Runs UMP consent → (ATT no-op) → AdMob
    /// SDK initialize in that order. Each step is attempted independently;
    /// a failing earlier step never blocks later steps (banner gate will
    /// surface `.failed` honestly while AdMob is still un-initialized).
    ///
    /// #371 / #195: the ATT step is intentionally a NO-OP at boot. The
    /// coordinator keeps the 3-slot UMP/ATT/AdMob shape (ordering tests rely on
    /// it) but `MonetizationBootBridges.live` wires the ATT closure to nothing —
    /// the real ATT prompt is driven later by `ATTPrimerCoordinator` (after Home
    /// + first ad-context). UMP (GDPR consent) legitimately stays at cold launch.
    ///
    /// Callable from `.task` on the root scene — the boot runs concurrently
    /// with first-frame rendering, never blocks UI.
    public func bootMonetization() async {
        #if !os(iOS)
        // AdMob + UMP are iOS-only (Google's xcframeworks ship iOS slices
        // only — see PR #101 for the conditional dep wiring). On macOS /
        // other platforms, `NoopAdProvider` is wired in Live.swift and the
        // UMP / ATT bridges always return `.unsupported`, which the
        // coordinator's failure path would otherwise misclassify as a
        // runtime fault and fan into `Telemetry.errorOccurred` (2 spurious
        // breadcrumbs per cold launch). Nothing to initialize here.
        return
        #else
        let bridges = MonetizationBootBridges.live(adProvider: adProvider)
        let telemetryHandle = telemetry
        let coordinator = MonetizationBootCoordinator(
            bridges: bridges,
            log: { outcome in
                // Telemetry's typed catalog does not have an "info"/"trace"
                // case suited to boot-sequence breadcrumbs, so we only fan
                // failures into Telemetry.observe(.errorOccurred(...)); the
                // success path takes the `print` fallback per spec §boot
                // notes. (See impl-notes §未決 — promoting boot events to
                // a first-class TelemetryEvent case is deferred to v2.4.)
                if !outcome.succeeded {
                    Task {
                        await telemetryHandle.observe(
                            .errorOccurred(
                                source: "MonetizationBoot",
                                code: outcome.step.rawValue,
                                message: outcome.errorDescription ?? "unknown"
                            )
                        )
                    }
                } else {
                    print("[MonetizationBoot] step=\(outcome.step.rawValue) succeeded")
                }
            }
        )
        await coordinator.boot()
        #endif
    }

    // MARK: - Resume helpers (#455)

    /// `%d:%02d` elapsed label for the resume pill subtitle. Moved out of the
    /// former `SavedGameSummary`-typed `ResumePill` (now game-agnostic) into a
    /// single shared home so `.live()` and `.preview()` map `SavedGameSummary`
    /// into the game-agnostic `ResumeCandidate` with byte-identical strings.
    static func elapsed(_ totalSeconds: Int) -> String {
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
