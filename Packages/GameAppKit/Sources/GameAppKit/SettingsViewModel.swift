// SettingsViewModel — read-only status surface + clear-cache action.
//
// #832: unified from `SudokuUI.SettingsViewModel` (Minesweeper had no
// equivalent — its wrapper took primitive `version:`/`clearCache:` closures
// and duplicated this exact bootstrap/clear-cache logic as a free function on
// `LiveRouteFactory`). Lives in GameAppKit — the "shared composition, deps
// allowed" layer — because it needs `Persistence`/`Telemetry`, which the
// zero-dep GameShellKit must never import.
//
// `persistence: any PersistenceProtocol` is the game-agnostic CloudKit seam
// both apps' composition roots already wire from the SAME `LivePersistence`
// (see `MakeGameApp.swift`) for exactly this "in-progress saved game"
// resume/clear-cache flow — it is not Sudoku-exclusive despite `SavedGameSummary`
// living in the `Persistence` module. `clearCache()` deletes the active
// in-progress record (if any) via that seam — the closest "session cache" hook
// on `PersistenceProtocol` today.
//
// Toast/confirmation behavior (v2.4.6 era): success/failure surfaces via
// `ToastController` (bottom-center capsule mounted on the app's RootView);
// `clearCacheConfirmation` stays the VoiceOver / test source of truth since
// toasts are transient and not reliably announced by VoiceOver.

public import Foundation
public import MonetizationUI
public import Persistence
public import Telemetry

@MainActor
@Observable
public final class SettingsViewModel {

    /// #832: replaces Sudoku-only `GeneratorVersion` (a `SudokuEngine` type
    /// GameAppKit must not depend on) with a plain label. `nil` (Minesweeper)
    /// hides the About section's extra "Generator" row entirely; Sudoku's
    /// composition root passes `GeneratorVersion.v1.rawValue`.
    public let generatorVersionLabel: String?
    public let appVersion: String

    /// Most-recent in-progress record, captured once at bootstrap; consumed
    /// by `clearCache()` when the user confirms the destructive action.
    public private(set) var resumeCandidate: SavedGameSummary?

    /// Set by `clearCache()` after the persistence write completes. Kept as
    /// the VoiceOver / test source of truth even though the visual surface
    /// moved to `ToastController` in v2.4.6.
    public private(set) var clearCacheConfirmation: String?

    @ObservationIgnored
    private let persistence: any PersistenceProtocol
    @ObservationIgnored
    private let errorReporter: any ErrorReporter
    @ObservationIgnored
    private let toastController: ToastController?

    public init(
        generatorVersionLabel: String? = nil,
        appVersion: String = "1.0.0",
        persistence: any PersistenceProtocol,
        errorReporter: any ErrorReporter = NoopErrorReporter(),
        toastController: ToastController? = nil
    ) {
        self.generatorVersionLabel = generatorVersionLabel
        self.appVersion = appVersion
        self.persistence = persistence
        self.errorReporter = errorReporter
        self.toastController = toastController
    }

    public func bootstrap() async {
        // M10 (issue #67): nil candidate is still legal (no in-progress
        // game). Catch + report the *failure* path so a CloudKit fetch
        // throw doesn't silently mask the Settings resume row.
        do {
            self.resumeCandidate = try await persistence.latestInProgress()
        } catch {
            self.resumeCandidate = nil
            await errorReporter.report(
                UserFacingError.classify(error),
                underlying: error,
                source: "SettingsViewModel.bootstrap"
            )
        }
    }

    /// Confirm + execute "Clear cache": deletes the active in-progress
    /// record if one exists. No-op when nothing is cached.
    public func clearCache() async {
        if let candidate = resumeCandidate {
            // M10 (issue #67): delete failure surfaces through the funnel
            // but we still optimistically clear local resumeCandidate — the
            // user explicitly asked to clear. #687: a thrown delete now also
            // fails loud via a failure toast instead of claiming success.
            do {
                try await persistence.deleteAbandoned(recordName: candidate.recordName)
            } catch {
                await errorReporter.report(
                    UserFacingError.classify(error),
                    underlying: error,
                    source: "SettingsViewModel.clearCache"
                )
                self.resumeCandidate = nil
                let message = String(localized: "Couldn't clear cache", bundle: .main)
                self.clearCacheConfirmation = message
                toastController?.show(Toast(style: .failure, message: message))
                return
            }
            self.resumeCandidate = nil
        }
        let message = String(localized: "Cache cleared", bundle: .main)
        self.clearCacheConfirmation = message
        toastController?.show(Toast(style: .success, message: message))
    }
}
