// HomeScreen — the shared Home scaffold + mode-card grid BODY (#410).
//
// Extracted from SudokuUI.HomeView + MinesweeperUI.MinesweeperHomeView, whose
// `ScrollView { header ; LazyVGrid(mode cards) ; banner }` body and
// `ModeCard` rendering were byte-identical save for per-app strings and an
// accessibility identifier set on the Button wrapper. This is the shared
// *body* + the single source of truth for the 4 common modes
// (Daily / Practice / Leaderboard / Settings).
//
// Everything app-specific is INJECTED:
//   - the header slot (Sudoku's ResumePill / Minesweeper's nothing),
//   - the removeAdsCard slot — retained for API stability (apps stopped
//     injecting it in SDD-003 Epic 7; defaults to EmptyView) so MonetizationUI never leaks
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
        case .leaderboard: "trophy"
        case .settings: "gear"
        }
    }

    /// The card's trailing glyph. Every mode uses the push-navigation chevron
    /// EXCEPT Leaderboard, which presents the system Game Center modal (not a
    /// stack push, see `GameHomeViewModel.swift:118-126`) — H1: an outward-jump
    /// glyph tells the user before they tap that this row won't drill down
    /// in-app like the other four.
    public var trailingSymbolName: String {
        switch self {
        case .leaderboard: "arrow.up.forward"
        case .daily, .practice, .settings: "chevron.right"
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
public struct HomeScreen<Header: View, RemoveAds: View, SecondaryLink: View, Banner: View>: View {
    private let items: [HomeModeItem]
    /// Accessibility-identifier builder for each mode's Button, app-supplied so
    /// each app keeps its own namespace (Sudoku had none; MS used
    /// "MinesweeperHomeView.<mode>Card"). Returns `nil` to set no identifier.
    private let cardAccessibilityIdentifier: (HomeMode) -> String?
    private let header: Header
    private let removeAdsCard: RemoveAds
    /// #773 / #844: an entry rendered below the mode-card grid — e.g. the
    /// Statistics card. Deliberately NOT a `HomeMode` case: `HomeMode` is the
    /// co-equal 4-card set that also drives the sidebar, and this slot exists
    /// so a new entry can be added without joining that sidebar-generating
    /// set. #844 owner override: the entry rendered here now reuses the SAME
    /// `HomeModeCard` visual format as the four modes (was a lighter-weight
    /// flat row under #773's original secondary-weight adjudication) — only
    /// its POSITION stays separate, not its visual weight. Defaults to
    /// `EmptyView` so games with nothing to inject here render byte-identically.
    private let secondaryLink: SecondaryLink
    private let banner: Banner

    @Environment(\.theme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass

    // Card-to-card grid gap (#762 PR1 two-tier spacing contract). Structural
    // (owner adjudication explicitly lists "card outer gaps" as structural,
    // so it's fixed, not Dynamic-Type-scaled) — 12pt predates the 5-tier
    // `SpacingTokens` scale (design-system.md lists 12 as a "common pairing"
    // with no matching field), so it's routed through a named constant
    // instead of `theme.spacing.*`.
    private let cardGridGap: CGFloat = 12

    public init(
        items: [HomeModeItem],
        cardAccessibilityIdentifier: @escaping (HomeMode) -> String? = { _ in nil },
        @ViewBuilder header: () -> Header = { EmptyView() },
        @ViewBuilder removeAdsCard: () -> RemoveAds = { EmptyView() },
        @ViewBuilder secondaryLink: () -> SecondaryLink = { EmptyView() },
        @ViewBuilder banner: () -> Banner = { EmptyView() }
    ) {
        self.items = items
        self.cardAccessibilityIdentifier = cardAccessibilityIdentifier
        self.header = header()
        self.removeAdsCard = removeAdsCard()
        self.secondaryLink = secondaryLink()
        self.banner = banner()
    }

    public var body: some View {
        ScrollView {
            header

            LazyVGrid(columns: columns, spacing: cardGridGap) {
                ForEach(items) { item in
                    Button {
                        item.onTap()
                    } label: {
                        HomeModeCard(
                            symbolName: item.mode.symbolName,
                            titleKey: item.mode.titleKey,
                            subtitleKey: item.subtitleKey,
                            trailingSymbolName: item.mode.trailingSymbolName
                        )
                    }
                    .buttonStyle(.plain)
                    .modifier(OptionalAccessibilityIdentifier(cardAccessibilityIdentifier(item.mode)))
                }

                removeAdsCard
            }
            .padding(theme.spacing.medium)

            secondaryLink

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

/// One shared mode card driven by explicit content (icon/title/subtitle), not
/// tied to the fixed `HomeMode` case set — #844 reuses it for the Statistics
/// entry, which is deliberately NOT a `HomeMode` (see `secondaryLink` doc).
/// The two apps' four mode cards were byte-identical (same
/// HStack/symbol/title/subtitle/chevron, same padding 16, minHeight 72, glass
/// corner radius 16, same theme tokens), so there is no per-app tint/
/// appearance to inject — only the data differs.
public struct HomeModeCard: View {
    let symbolName: String
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    /// The trailing glyph — "chevron.right" for push-navigation rows,
    /// "arrow.up.forward" for Leaderboard's outward jump to the system Game
    /// Center modal (H1). Defaults to the chevron so the #844 Statistics
    /// call site (which doesn't push either, but IS an in-app destination)
    /// renders byte-identically without opting in.
    let trailingSymbolName: String
    @Environment(\.theme) private var theme
    // Card internal padding (#762 PR1 two-tier spacing contract) — content
    // tier, wraps the icon/title/subtitle/chevron row, scales with Dynamic
    // Type.
    @ScaledSpacing(.medium) private var cardPadding

    public init(
        symbolName: String,
        titleKey: LocalizedStringKey,
        subtitleKey: LocalizedStringKey,
        trailingSymbolName: String = "chevron.right"
    ) {
        self.symbolName = symbolName
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.trailingSymbolName = trailingSymbolName
    }

    public var body: some View {
        // spacing-exempt: 14pt (icon-to-text gap) predates the 5-tier
        // `SpacingTokens` scale — no matching tier without snapping and
        // changing this card's existing layout/snapshot (#762).
        HStack(spacing: 14) {
            Image(systemName: symbolName)
                .font(.title2)
                .foregroundStyle(theme.accent.primary.resolved)
                .frame(width: 36, height: 36)
            // spacing-exempt: 2pt (title-to-subtitle gap) predates the
            // 5-tier `SpacingTokens` scale — same rationale as above (#762).
            VStack(alignment: .leading, spacing: 2) {
                Text(titleKey)
                    .font(.title3.weight(.medium))
                    .foregroundStyle(theme.text.primary.resolved)
                Text(subtitleKey)
                    .font(.caption)
                    .foregroundStyle(theme.text.secondary.resolved)
            }
            Spacer()
            Image(systemName: trailingSymbolName)
                .foregroundStyle(theme.text.tertiary.resolved)
        }
        .padding(cardPadding)
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
