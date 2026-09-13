// MakeGameApp+BannerSession — the banner session wiring `makeGameAppCore`
// uses (#1058), kept out of MakeGameApp.swift (400-line ceiling) and callable
// from GameAppKit tests, since `makeGameAppCore` itself wires live seams.

internal import MonetizationCore
internal import MonetizationUI

/// Builds the session's one banner model over the SAME `adProvider` instance
/// `bootMonetization` initializes, so the readiness it waits on is the one
/// boot opens. The ATT primer is its ad-context hook (C-33).
@MainActor
func makeBannerSession(
    adProvider: any AdProvider,
    adGate: AdGate,
    attPrimer: ATTPrimerCoordinator
) -> BannerSessionModel {
    BannerSessionModel(
        adProvider: adProvider,
        adGate: adGate,
        onAdContext: { [attPrimer] in await attPrimer.maybePresentOnAdContext() }
    )
}

/// The hook `MonetizationStateController` runs at the end of every
/// `markPurchased()`: the session re-resolves the now-closed gate and
/// collapses every slot.
@MainActor
func makeEntitlementChangedHook(bannerSession: BannerSessionModel) -> @MainActor () async -> Void {
    { [bannerSession] in await bannerSession.refreshGate() }
}
