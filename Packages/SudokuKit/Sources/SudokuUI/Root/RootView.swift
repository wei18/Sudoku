// RootView — Sudoku-specific app entry container.
//
// Thin wrapper over `GameShellUI.RootShellView` (PR X3 extraction). The
// generic shell owns the NavigationStackHost shape + sidebar list rendering;
// RootView keeps the Sudoku-specific bits: the ResumePill on top of the
// root content, HomeView mount (with ad / monetization deps), themed
// background, `.task { bootstrap() }`, and the toast overlay. Sidebar items
// are declared inline as a `[SidebarItem<AppRoute>]` literal.
//
// Per plan.md v2.3.3 (Wave 3 audit close-out): all destination construction
// goes through `RouteFactory`. RootView's init still only takes a
// `RootViewModel` and a `routeFactory` (+ monetization wiring for HomeView);
// no protocol-dep leakage, so future feature growth does not bloat this
// signature.

public import MonetizationCore
public import MonetizationUI
public import SwiftUI
public import GameShellUI
// #448 step 3: `GameRoot` (shared Root shell + onAppear-bootstrap + toast) and
// `ResumePill` (moved out of this file) now live in GameAppKit. Public because
// the `RootView` init's `RootViewModel` is a typealias over `GameRootViewModel`.
public import GameAppKit

public struct RootView: View {
    @State private var viewModel: RootViewModel
    @Environment(\.theme) private var theme

    private let routeFactory: any RouteFactory<AppRoute>
    // v2.3.4: forwarded to HomeView for its `BannerSlotView` mount. The
    // route factory already holds these privately for destination views;
    // HomeView is the root content (not a destination), so RootView still
    // has to thread them in directly. Two extra deps, not eight — the
    // RouteFactory absorbs the rest.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?
    // v2.3.6: shared monetization controller; reaches HomeView for the 5th
    // "Remove Ads" card and the route factory hands the same instance to
    // SettingsView so both surfaces observe the same `hasPurchasedRemoveAds`.
    private let monetizationController: MonetizationStateController?
    // v2.4.5: bottom-anchored transient surface for purchase / restore results.
    // Wired via `.toastOverlay(...)` below.
    private let toastController: ToastController?
    // #371 / #195: ATT pre-prompt coordinator. Forwarded to HomeView's banner
    // slot (the trigger) and bound to the priming `.sheet` mounted here at the
    // root so the sheet presents above the whole app, not from a 50pt slot.
    @State private var attPrimer: ATTPrimerCoordinator?

    public init(
        viewModel: RootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        monetizationController: MonetizationStateController? = nil,
        toastController: ToastController? = nil,
        attPrimer: ATTPrimerCoordinator? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.routeFactory = routeFactory
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationController = monetizationController
        self.toastController = toastController
        self._attPrimer = State(initialValue: attPrimer)
    }

    // #410: one `HomeViewModel` drives BOTH the Home cards and the sidebar, so
    // the mode list (Daily / Practice / Leaderboard / Settings) + their tap
    // actions come from a single source. Bound to RootViewModel's path so the
    // sidebar, the Home cards, and `RootShellView`'s NavigationStack all share
    // one navigation array.
    // #513: `authState` forwarded so the leaderboard card can gate on it.
    private var homeViewModel: HomeViewModel {
        HomeViewModel(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            authState: viewModel.authState
        )
    }

    public var body: some View {
        // #448 step 3: the common Root shape (RootShellView + onAppear-bootstrap
        // + toast overlay, including the `.task`→`.onAppear` arm64-Release-link
        // workaround, #361) now lives in `GameAppKit.GameRoot`. Sudoku layers on
        // its app-specific bits: the ATT priming sheet and the ResumePill inside
        // `rootContent`.
        GameRoot(
            viewModel: viewModel,
            title: "Sudoku",
            sidebarItems: HomeModeItem.sidebarItems(from: homeViewModel.modeItems),
            routeFactory: routeFactory,
            toastController: toastController,
            successTint: theme.status.success.resolved,
            failureTint: theme.status.error.resolved
        ) {
            rootContent
        }
        .attPrimerSheet(attPrimer)
    }

    @ViewBuilder
    private var rootContent: some View {
        // #387: the ResumePill is threaded into HomeView's scroll region via
        // its `header` slot so it scrolls WITH the mode cards instead of being
        // pinned above HomeView's own ScrollView. RootView still owns the
        // resume candidate + tap wiring; only the placement moved.
        HomeView(
            viewModel: homeViewModel,
            adProvider: adProvider,
            adGate: adGate,
            monetizationController: monetizationController,
            attPrimer: attPrimer
        ) {
            if let candidate = viewModel.resumeCandidate {
                ResumePill(title: candidate.title, subtitle: candidate.subtitle) {
                    viewModel.resumeTapped()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(theme.surface.background.resolved)
    }
}
