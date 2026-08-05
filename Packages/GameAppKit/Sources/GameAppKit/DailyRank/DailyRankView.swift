// DailyRankView — shared Daily Rank screen (#983).
//
// Pushed route content (never a modal): difficulty tabs (segmented) × World/
// Friends scope (segmented) over a per-(tab,scope) result list, plus a
// persistent "Open Game Center" secondary affordance so Apple's full
// dashboard stays reachable (per §How: "A secondary 'Open Game Center'
// affordance keeps Apple's full dashboard reachable").
//
// #536/#761 pattern: the view model is built by the caller (each app's
// `LiveRouteFactory.view(for:)`) and stored via `@State` (first-value-wins),
// NOT `@Bindable` on a passed-in `let` — `.navigationDestination` closures
// re-invoke on every ancestor re-render, and a `@Bindable` reference would
// silently swap in a fresh `.idle` instance, losing all loaded state
// (swiftui-interaction-footguns: "View-model built inside a
// navigationDestination / factory closure").

public import SwiftUI

public struct DailyRankView: View {
    @State private var viewModel: DailyRankViewModel
    @Environment(\.theme) private var theme

    public init(viewModel: DailyRankViewModel) {
        _viewModel = State(wrappedValue: viewModel)
    }

    public var body: some View {
        VStack(spacing: 0) {
            Picker("Difficulty", selection: tabBinding) {
                ForEach(viewModel.tabs) { tab in
                    Text(tab.titleKey).tag(tab.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(theme.accent.primary.resolved)
            .padding(.horizontal, theme.spacing.medium)
            .padding(.top, theme.spacing.small)
            .accessibilityIdentifier("dailyRank.tabPicker")

            Picker("Scope", selection: scopeBinding) {
                ForEach(DailyRankScope.allCases) { scope in
                    Text(scope.titleKey).tag(scope)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .tint(theme.accent.primary.resolved)
            .padding(.horizontal, theme.spacing.medium)
            .padding(.top, theme.spacing.small)
            .accessibilityIdentifier("dailyRank.scopePicker")

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            Button {
                viewModel.openGameCenter()
            } label: {
                Text("Open Game Center")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(theme.accent.primary.resolved)
            .padding(theme.spacing.medium)
            .accessibilityIdentifier("dailyRank.openGameCenter")
        }
        .background(theme.surface.background.resolved)
        .navigationTitle("Daily Rank")
        .task { await viewModel.onAppear() }
        .accessibilityIdentifier("dailyRank.root")
    }

    private var tabBinding: Binding<String> {
        Binding(get: { viewModel.selectedTabId }, set: { viewModel.selectTab($0) })
    }

    private var scopeBinding: Binding<DailyRankScope> {
        Binding(get: { viewModel.selectedScope }, set: { viewModel.selectScope($0) })
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.state {
        case .idle, .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loaded(let result):
            DailyRankResultView(result: result, scope: viewModel.selectedScope)
        case .failed(.notSignedIn):
            DailyRankExplainerView(
                systemImage: "person.crop.circle.badge.exclamationmark",
                titleKey: "Sign in to Game Center",
                messageKey: "Sign in to Game Center to compare with others.",
                actionTitleKey: "Sign In",
                accessibilityId: "dailyRank.signIn",
                action: { await viewModel.signIn() }
            )
        case .failed(.friendsNotAuthorized):
            DailyRankExplainerView(
                systemImage: "person.2.circle",
                titleKey: "Connect with Friends",
                messageKey: "Allow Game Center to see your friends list to compare daily times with people you know.",
                actionTitleKey: "Allow Friends Access",
                accessibilityId: "dailyRank.allowFriends",
                action: { await viewModel.requestFriendsAccess() }
            )
        case .failed(.network):
            DailyRankExplainerView(
                systemImage: "wifi.exclamationmark",
                titleKey: "Couldn't Load Rankings",
                messageKey: "Check your connection and try again.",
                actionTitleKey: "Retry",
                accessibilityId: "dailyRank.retry",
                action: { await viewModel.retry() }
            )
        }
    }
}
