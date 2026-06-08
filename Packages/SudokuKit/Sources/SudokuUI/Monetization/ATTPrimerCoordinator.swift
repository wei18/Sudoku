// ATTPrimerCoordinator — Sudoku ATT pre-prompt (priming) flow (#371 / #195).
//
// design.md §How.4: the ATT system dialog must NOT fire at cold launch. It must
// appear after the user has seen Home AND at the first moment a personalized ad
// would actually matter (lazy / contextual). The trigger seam is the Sudoku
// `BannerSlotView` load path (gate open == an ad is about to load == the first
// ad-relevant moment), which calls `maybePresentOnAdContext()`.
//
// Path-B framing (docs/marketing/appstore-copy/path-b-copy-correction.md): the
// priming sheet explains "ads stay relevant, not a profile; decline still works,
// or remove ads", THEN "Continue" leads into the system ATT dialog. "Not now"
// dismisses without requesting.
//
// Isolation: SudokuUI must NOT import AdsAdMob (foundations.md §9.1 — only
// `MonetizationCore`). The two ATT touch points (read status / present prompt)
// are injected as closures; `AppComposition` (which depends on AdsAdMob) wires
// them to `ATTPresenter`. Mirrors `ReminderPrimerCoordinator`'s closure-injected
// telemetry seam.

public import SwiftUI

@MainActor
@Observable
public final class ATTPrimerCoordinator {

    /// Drives the `ATTPrimerSheet` presentation. The ad-context trigger flips
    /// this to `true`; Continue / Not now flip it back.
    public var isPrimerPresented = false

    /// Returns `true` only while the system has not yet asked for ATT. Injected
    /// so SudokuUI never imports AppTrackingTransparency / AdsAdMob.
    @ObservationIgnored private let isNotDetermined: @Sendable () async -> Bool

    /// Presents the system ATT dialog (no-op on any non-`.notDetermined` state).
    /// Injected from the AdsAdMob layer via `ATTPresenter.requestIfNeeded`.
    @ObservationIgnored private let requestSystemPrompt: @Sendable () async -> Void

    /// One-offer-per-launch latch. Once we've shown the priming sheet (or
    /// resolved that ATT is already determined), we never re-offer in this
    /// session — keeps the trigger idempotent against `.task` re-fire / repeated
    /// gate re-polls (swiftui-interaction-footguns: `.task` re-fires on remount).
    @ObservationIgnored private var hasOffered = false

    public init(
        isNotDetermined: @escaping @Sendable () async -> Bool,
        requestSystemPrompt: @escaping @Sendable () async -> Void
    ) {
        self.isNotDetermined = isNotDetermined
        self.requestSystemPrompt = requestSystemPrompt
    }

    /// Called from the ad-relevant context (BannerSlotView, gate open). Presents
    /// the priming sheet exactly once per launch, and only while ATT is still
    /// `.notDetermined`. If ATT is already authorized / denied / restricted /
    /// unsupported, this is a no-op — the system dialog has already happened (or
    /// can't), so re-offering would be noise.
    public func maybePresentOnAdContext() async {
        guard !hasOffered else { return }
        guard await isNotDetermined() else {
            // Already determined (or unsupported). Latch so we don't re-check on
            // every banner re-poll, but never present.
            hasOffered = true
            return
        }
        hasOffered = true
        isPrimerPresented = true
    }

    /// User tapped "Continue" — leads into the system ATT dialog. Dismisses the
    /// sheet first so the system alert is the only modal on screen.
    public func continueToSystemPrompt() async {
        isPrimerPresented = false
        await requestSystemPrompt()
    }

    /// User tapped "Not now" — dismiss without requesting. ATT stays
    /// `.notDetermined`; the latch keeps us from re-offering this session.
    public func declinePrimer() {
        isPrimerPresented = false
    }
}
