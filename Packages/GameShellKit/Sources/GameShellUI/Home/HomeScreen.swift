// HomeScreen — the shared Home scaffold + mode-card grid BODY (#410).
//
// Extracted from SudokuUI.HomeView + MinesweeperUI.MinesweeperHomeView, whose
// `ScrollView { header ; LazyVGrid(mode cards + RemoveAds) ; banner }` body and
// `ModeCard` rendering were byte-identical save for per-app strings and an
// accessibility identifier set on the Button wrapper. This is the shared
// *body* + the single source of truth for the 4 common modes
// (Daily / Practice / Leaderboard / Settings).
//
// Everything app-specific is INJECTED:
//   - the header slot (Sudoku's ResumePill / Minesweeper's nothing),
//   - the RemoveAds card slot — kept app-side so MonetizationUI never leaks
//     into GameShellUI (the shell stays game- and commerce-agnostic),
//   - the banner slot — likewise app-side (AdProvider / AdGate live in each Kit),
//   - the per-mode `onTap` (Daily/Practice/Settings push the app's AppRoute;
//     Leaderboard is an injected GC-dashboard side-effect),
//   - the per-mode subtitle as a `LocalizedStringKey` resolved from each app's
//     own `Localizable.xcstrings` (Bundle.main), exactly as the prior literals.
//
// The mode CARD is one shared view driven by the model — the two apps' cards
// were identical, so no per-app tint/appearance injection is needed.
//
// Themed via `@Environment(\.theme)` — the host injects its concrete palette.

public import SwiftUI

// MARK: - HomeMode (single source of truth for the 4 common modes)

/// The four modes both games share, in render order. Single source of truth in
/// GameShellUI: each app maps each mode to its OWN route/action via an injected
/// closure and supplies its OWN subtitle, while the canonical id / title /
/// SF Symbol live here so the Home cards and the sidebar derive from one list.
///
/// The titles ("Daily" / "Practice" / "Leaderboard" / "Settings") are byte-for-byte
/// identical across both apps' catalogs, so they live here as the canonical
/// `titleKey`; only subtitles + tap actions diverge and are injected per app.
public enum HomeMode: String, Sendable, Equatable, Hashable, CaseIterable, Identifiable {
    case daily
    case practice
    case leaderboard
    case settings

    public var id: String { rawValue }

    /// Canonical localized title. Rendered with `Text(_:)`, which resolves
    /// against `Bundle.main` (the app), so each app's catalog supplies the
    /// translation — GameShellUI ships no string catalog of its own.
    public var titleKey: LocalizedStringKey {
        switch self {
        case .daily: "Daily"
        case .practice: "Practice"
        case .leaderboard: "Leaderboard"
        case .settings: "Settings"
        }
    }

    /// Canonical SF Symbol, identical across both apps.
    public var symbolName: String {
        switch self {
        case .daily: "calendar"
        case .practice: "dice"
        case .leaderboard: "trophy.fill"
        case .settings: "gear"
        }
    }
}

// MARK: - HomeModeItem (mode + app-supplied subtitle + action)

/// A `HomeMode` bound to its app-specific subtitle and tap action. The shared
/// list of these is the single source for BOTH the Home card grid and the
/// `RootShellView` sidebar — `sidebarItems(from:)` derives the latter so the
/// two surfaces can never drift.
public struct HomeModeItem: Identifiable {
    public let mode: HomeMode
    /// App-supplied subtitle, resolved from the app's own catalog (Bundle.main).
    public let subtitleKey: LocalizedStringKey
    /// Tap handler. Daily/Practice/Settings push the app's route; Leaderboard
    /// fires the app's GC-dashboard side-effect. Closure (not enum) so the
    /// shell stays unaware of route-push vs. side-effect — mirrors `SidebarItem`.
    public let onTap: @MainActor () -> Void

    public var id: String { mode.id }

    public init(
        mode: HomeMode,
        subtitleKey: LocalizedStringKey,
        onTap: @escaping @MainActor () -> Void
    ) {
        self.mode = mode
        self.subtitleKey = subtitleKey
        self.onTap = onTap
    }
}

public extension HomeModeItem {
    /// Derive the matching `[SidebarItem<Route>]` from the SAME shared list, so
    /// the Home cards and the sidebar come from one source of truth. The
    /// `Route` is phantom here — each item carries its own `onTap`, so the
    /// shell never names a concrete route — but the array must be typed for
    /// `RootShellView<Route, _>`.
    static func sidebarItems<Route: Hashable>(
        from items: [HomeModeItem],
        as _: Route.Type = Route.self
    ) -> [SidebarItem<Route>] {
        items.map { item in
            SidebarItem(
                id: item.mode.id,
                titleKey: item.mode.titleKey,
                systemImage: item.mode.symbolName,
                onTap: item.onTap
            )
        }
    }
}

// MARK: - HomeScreen scaffold

/// The shared Home scaffold: `ScrollView { header ; LazyVGrid(mode cards +
/// RemoveAds slot) ; banner slot }`, plus the sizeClass column logic and the
/// themed background. Renders the shared mode cards from `items`.
///
/// Layout is preserved byte-for-byte from the prior per-app bodies: padding 16
/// on the grid, spacing 12, single-column compact / two-column regular,
/// order header → grid → banner.
public struct HomeScreen<Header: View, RemoveAds: View, Banner: View>: View {
    private let items: [HomeModeItem]
    /// Accessibility-identifier builder for each mode's Button, app-supplied so
    /// each app keeps its own namespace (Sudoku had none; MS used
    /// "MinesweeperHomeView.<mode>Card"). Returns `nil` to set no identifier.
    private let cardAccessibilityIdentifier: (HomeMode) -> String?
    private let header: Header
    private let removeAdsCard: RemoveAds
    private let banner: Banner

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    public init(
        items: [HomeModeItem],
        cardAccessibilityIdentifier: @escaping (HomeMode) -> String? = { _ in nil },
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder removeAdsCard: () -> RemoveAds = { EmptyView() },
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.items = items
        self.cardAccessibilityIdentifier = cardAccessibilityIdentifier
        self.header = header()
        self.removeAdsCard = removeAdsCard()
        self.banner = banner()
    }

    public var body: some View {
        ScrollView {
            header

            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(items) { item in
                    Button {
                        item.onTap()
                    } label: {
                        HomeModeCard(mode: item.mode, subtitleKey: item.subtitleKey)
                    }
                    .buttonStyle(.plain)
                    .modifier(OptionalAccessibilityIdentifier(cardAccessibilityIdentifier(item.mode)))
                }

                removeAdsCard
            }
            .padding(16)

            banner
        }
        .background(theme.surface.background.resolved)
    }

    private var columns: [GridItem] {
        if sizeClass == .regular {
            return [GridItem(.flexible()), GridItem(.flexible())]
        }
        return [GridItem(.flexible())]
    }
}

// MARK: - Shared mode card

/// One shared mode card driven by the model. The two apps' cards were
/// byte-identical (same HStack/symbol/title/subtitle/chevron, same padding 16,
/// minHeight 72, glass corner radius 16, same theme tokens), so there is no
/// per-app tint/appearance to inject — only the data differs.
public struct HomeModeCard: View {
    let mode: HomeMode
    let subtitleKey: LocalizedStringKey
    @Environment(\.theme) private var theme

    public init(mode: HomeMode, subtitleKey: LocalizedStringKey) {
        self.mode = mode
        self.subtitleKey = subtitleKey
    }

    public var body: some View {
        HStack(spacing: 14) {
            Image(systemName: mode.symbolName)
                .font(.title2)
                .foregroundStyle(theme.accent.primary.resolved)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.titleKey)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Text(subtitleKey)
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(theme.text.tertiary.resolved)
        }
        .padding(16)
        .frame(minHeight: 72)
        .contentShape(Rectangle())
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - OptionalAccessibilityIdentifier

/// Applies `.accessibilityIdentifier` only when the app supplied one. Sudoku's
/// cards had no identifier (kept byte-identical), MS namespaced each one.
private struct OptionalAccessibilityIdentifier: ViewModifier {
    let identifier: String?

    init(_ identifier: String?) { self.identifier = identifier }

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
