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
internal import Persistence
internal import SudokuEngine

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

    public init(
        viewModel: RootViewModel,
        routeFactory: any RouteFactory<AppRoute>,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil,
        monetizationController: MonetizationStateController? = nil,
        toastController: ToastController? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.routeFactory = routeFactory
        self.adProvider = adProvider
        self.adGate = adGate
        self.monetizationController = monetizationController
        self.toastController = toastController
    }

    public var body: some View {
        RootShellView(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            title: "Sudoku",
            sidebarItems: sidebarItems,
            routeFactory: routeFactory,
            rootContent: { rootContent }
        )
        // Use `.onAppear { Task { … } }` instead of `.task { … }`: Xcode 26's
        // SwiftUI lowers EVERY `.task` overload to `task(name:priority:file:line:_:)`,
        // whose opaque-type descriptor links undefined in the arm64 device Release
        // archive (sim/macOS/Debug fine). bootstrap() is a one-shot boot with its
        // own idempotency guard, so `.task`'s disappear-cancellation isn't needed. #361
        .onAppear { Task { await viewModel.bootstrap() } }
        .toastOverlay(
            toastController,
            successTint: theme.status.success.resolved,
            failureTint: theme.status.error.resolved
        )
    }

    // Sidebar mirrors HomeView's mode list. Daily / Practice / Settings push
    // an `AppRoute`; Leaderboard is a side effect — it presents Apple's
    // native Game Center dashboard modally (issue #49, 2026-05-20) rather
    // than pushing onto the stack.
    private var sidebarItems: [SidebarItem<AppRoute>] {
        [
            SidebarItem(
                id: "daily",
                titleKey: "Daily",
                systemImage: "calendar",
                onTap: { viewModel.path.append(.daily) }
            ),
            SidebarItem(
                id: "practice",
                titleKey: "Practice",
                systemImage: "dice",
                onTap: { viewModel.path.append(.practice) }
            ),
            SidebarItem(
                id: "leaderboard",
                titleKey: "Leaderboard",
                systemImage: "trophy.fill",
                onTap: { GameCenterDashboard.present() }
            ),
            SidebarItem(
                id: "settings",
                titleKey: "Settings",
                systemImage: "gear",
                onTap: { viewModel.path.append(.settings) }
            ),
        ]
    }

    @ViewBuilder
    private var rootContent: some View {
        // #387: the ResumePill is threaded into HomeView's scroll region via
        // its `header` slot so it scrolls WITH the mode cards instead of being
        // pinned above HomeView's own ScrollView. RootView still owns the
        // resume candidate + tap wiring; only the placement moved.
        HomeView(
            viewModel: HomeViewModel(
                path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 })
            ),
            adProvider: adProvider,
            adGate: adGate,
            monetizationController: monetizationController
        ) {
            if let candidate = viewModel.resumeCandidate {
                ResumePill(candidate: candidate) {
                    viewModel.resumeTapped()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
        }
        .background(theme.surface.background.resolved)
    }
}

// MARK: - Resume pill

struct ResumePill: View {
    let candidate: SavedGameSummary
    let onTap: () -> Void
    @Environment(\.theme) private var theme

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.clockwise")
                    .foregroundStyle(theme.accent.primary.resolved)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(candidate.difficulty.rawValue.capitalized)")
                        .font(.body.weight(.medium))
                        .foregroundStyle(theme.text.primary.resolved)
                    Text(elapsedLabel)
                        .font(.caption)
                        .foregroundStyle(theme.text.secondary.resolved)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(theme.text.tertiary.resolved)
            }
            .padding(12)
            .background(theme.surface.primary.resolved, in: .rect(cornerRadius: 14))
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
        }
        .buttonStyle(.plain)
    }

    private var elapsedLabel: String {
        let total = candidate.elapsedSeconds
        let minutes = total / 60
        let seconds = total % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
