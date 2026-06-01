// RootView — app entry container.
//
// Owns the NavigationStackHost shape, mounts HomeView as the root content,
// and renders the (optional) Resume pill at the top per design 01-root.md.
// Per plan.md v2.3.3 (Wave 3 audit close-out): all destination construction
// moved to `RouteFactory`. RootView's init now only takes a `RootViewModel`
// and a `routeFactory`; no protocol-dep leakage, so future feature growth
// does not bloat this signature.

public import MonetizationCore
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
        NavigationStackHost(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            sidebar: { sidebarPlaceholder },
            content: { rootContent },
            // Destination VMs (Daily/Practice) are intentionally re-constructed
            // per push: state that must outlive the push lives in
            // `RootViewModel.path` + Persistence, NOT in the destination VM. The
            // path binding is threaded in so the VMs' navigation actions land in
            // the same path the outer NavigationStack observes. (Issue #197/#199
            // follow-up — without this, Daily/Practice taps were silently
            // mutating disconnected internal paths.)
            destination: { route in
                routeFactory.view(
                    for: route,
                    path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 })
                )
            }
        )
        .task { await viewModel.bootstrap() }
        .toastOverlay(toastController)
    }

    @ViewBuilder
    private var rootContent: some View {
        VStack(spacing: 0) {
            if let candidate = viewModel.resumeCandidate {
                ResumePill(candidate: candidate) {
                    viewModel.resumeTapped()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            HomeView(
                viewModel: HomeViewModel(
                    path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 })
                ),
                adProvider: adProvider,
                adGate: adGate,
                monetizationController: monetizationController
            )
        }
        .background(theme.surface.background.resolved)
    }

    @ViewBuilder
    private var sidebarPlaceholder: some View {
        // Sidebar mirrors HomeView's mode list. Daily / Practice / Settings push
        // an `AppRoute`; Leaderboard is a side effect — it presents Apple's
        // native Game Center dashboard modally (issue #49, 2026-05-20) rather
        // than pushing onto the stack.
        //
        // 2026-05-23: switched away from value-based `NavigationLink(value:)`.
        // The `.navigationDestination(for: AppRoute.self)` lives inside the
        // detail pane's NavigationStack (see NavigationStackHost), which on
        // macOS NavigationSplitView is a separate scope from the sidebar's
        // List. SwiftUI's value-link lookup walks ancestors for a matching
        // destination, and the cross-pane scope made the push fire
        // inconsistently. Mirroring HomeView's pattern — direct
        // `viewModel.path.append(...)` — keeps mutation inside the same
        // scope as the destination registry, so the push is deterministic.
        List {
            sidebarRow("Daily", systemImage: "calendar") {
                viewModel.path.append(.daily)
            }
            sidebarRow("Practice", systemImage: "dice") {
                viewModel.path.append(.practice)
            }
            sidebarRow("Leaderboard", systemImage: "trophy.fill") {
                GameCenterDashboard.present()
            }
            sidebarRow("Settings", systemImage: "gear") {
                viewModel.path.append(.settings)
            }
        }
        .navigationTitle("Sudoku")
    }

    private func sidebarRow(
        _ title: LocalizedStringKey,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
        }
        .buttonStyle(.plain)
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
