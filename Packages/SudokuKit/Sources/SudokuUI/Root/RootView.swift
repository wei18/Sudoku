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
internal import Persistence

public struct RootView: View {
    @State private var viewModel: RootViewModel
    @Environment(\.theme) private var theme

    private let routeFactory: any RouteFactory
    // v2.3.4: forwarded to HomeView for its `BannerSlotView` mount. The
    // route factory already holds these privately for destination views;
    // HomeView is the root content (not a destination), so RootView still
    // has to thread them in directly. Two extra deps, not eight — the
    // RouteFactory absorbs the rest.
    private let adProvider: (any AdProvider)?
    private let adGate: AdGate?

    public init(
        viewModel: RootViewModel,
        routeFactory: any RouteFactory,
        adProvider: (any AdProvider)? = nil,
        adGate: AdGate? = nil
    ) {
        self._viewModel = State(initialValue: viewModel)
        self.routeFactory = routeFactory
        self.adProvider = adProvider
        self.adGate = adGate
    }

    public var body: some View {
        NavigationStackHost(
            path: Binding(get: { viewModel.path }, set: { viewModel.path = $0 }),
            sidebar: { sidebarPlaceholder },
            content: { rootContent },
            destination: { route in routeFactory.view(for: route) }
        )
        .task { await viewModel.bootstrap() }
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
                adGate: adGate
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
        List {
            NavigationLink(value: AppRoute.daily) {
                Label("Daily", systemImage: "calendar")
            }
            NavigationLink(value: AppRoute.practice) {
                Label("Practice", systemImage: "dice")
            }
            Button {
                GameCenterDashboard.present()
            } label: {
                Label("Leaderboard", systemImage: "trophy.fill")
            }
            .buttonStyle(.plain)
            NavigationLink(value: AppRoute.settings) {
                Label("Settings", systemImage: "gear")
            }
        }
        .navigationTitle("Sudoku")
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
                    Text("Resume \(candidate.difficulty.capitalized)")
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
