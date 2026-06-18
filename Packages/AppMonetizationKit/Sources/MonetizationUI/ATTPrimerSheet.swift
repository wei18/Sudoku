// ATTPrimerSheet — the ATT pre-prompt (priming) screen (#195, #557).
//
// Moved from SudokuUI into MonetizationUI (#557 SDD-005 Pillar C) so
// GameAppKit can apply the universal `.attPrimerSheet(deps.attPrimer)` without
// a SudokuUI → GameAppKit → SudokuUI module cycle.
//
// Shown BEFORE the system ATT dialog, at the first ad-relevant moment (see
// ATTPrimerCoordinator). Path-B copy: relevance not a profile; decline still
// works; or remove ads. "Continue" leads into the system dialog; "Not now"
// dismisses without requesting.
//
// Strings are `LocalizedStringKey`s resolved against `Bundle.main` (the running
// app) — each game ships the att.primer.* keys in its own Localizable.xcstrings.
//
// Theme: MonetizationUI intentionally does NOT depend on GameShellKit, so it
// cannot read `\.theme` directly. Instead the four theme colors the sheet needs
// (accent / primary-text / secondary-text / surface-background) are INJECTED as
// `Color` params — the same pattern `BannerSlotView` / `ToastView` use. The
// composition root (`makeGameApp`) passes the game's resolved `\.theme` tokens
// so the sheet stays on-theme (Sudoku sage-green, not system blue). Defaults are
// system styles so hosts that don't inject (previews) still render sensibly.

public import SwiftUI

@MainActor
public struct ATTPrimerSheet: View {
    @Bindable public var coordinator: ATTPrimerCoordinator

    private let accentColor: Color
    private let primaryTextColor: Color
    private let secondaryTextColor: Color
    private let backgroundColor: Color

    public init(
        coordinator: ATTPrimerCoordinator,
        accentColor: Color = .accentColor,
        primaryTextColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        backgroundColor: Color = Color(.clear)
    ) {
        self.coordinator = coordinator
        self.accentColor = accentColor
        self.primaryTextColor = primaryTextColor
        self.secondaryTextColor = secondaryTextColor
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 12)

            Image(systemName: "hand.raised.circle")
                .font(.system(size: 56))
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 12) {
                Text("att.primer.title")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(primaryTextColor)

                Text("att.primer.body")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(secondaryTextColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)

            Spacer(minLength: 12)

            VStack(spacing: 12) {
                Button {
                    Task { await coordinator.continueToSystemPrompt() }
                } label: {
                    Text("att.primer.continue")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(accentColor)

                Button {
                    coordinator.declinePrimer()
                } label: {
                    Text("att.primer.notNow")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .controlSize(.large)
                .foregroundStyle(secondaryTextColor)
            }
        }
        .padding(24)
        .background(backgroundColor)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

public extension View {
    /// Mounts the ATT priming sheet, presented when the coordinator's
    /// `isPrimerPresented` flips true. No-op when `coordinator` is nil (hosts
    /// that don't drive ATT, e.g. previews / Minesweeper before its migration).
    ///
    /// The four theme colors are injected by the composition root so the sheet
    /// stays on-theme without MonetizationUI depending on GameShellKit. Defaults
    /// are system styles for hosts that don't thread theme tokens.
    @MainActor
    @ViewBuilder
    func attPrimerSheet(
        _ coordinator: ATTPrimerCoordinator?,
        accentColor: Color = .accentColor,
        primaryTextColor: Color = .primary,
        secondaryTextColor: Color = .secondary,
        backgroundColor: Color = Color(.clear)
    ) -> some View {
        if let coordinator {
            self.modifier(ATTPrimerSheetModifier(
                coordinator: coordinator,
                accentColor: accentColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                backgroundColor: backgroundColor
            ))
        } else {
            self
        }
    }
}

private struct ATTPrimerSheetModifier: ViewModifier {
    @Bindable var coordinator: ATTPrimerCoordinator
    let accentColor: Color
    let primaryTextColor: Color
    let secondaryTextColor: Color
    let backgroundColor: Color

    func body(content: Content) -> some View {
        content.sheet(isPresented: $coordinator.isPrimerPresented) {
            ATTPrimerSheet(
                coordinator: coordinator,
                accentColor: accentColor,
                primaryTextColor: primaryTextColor,
                secondaryTextColor: secondaryTextColor,
                backgroundColor: backgroundColor
            )
        }
    }
}
