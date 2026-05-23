// SettingsViewModel — read-only status surface + clear-cache action.
//
// Per docs/designs/08-settings.md. Synchronous reads + memoized snapshots;
// no loading state. `clearCache()` deletes the active in-progress saved
// game (if any) via Persistence — the closest "session cache" hook on the
// PersistenceProtocol surface today.
//
// v2.4.6: clear-cache success surfaces via `ToastController` (bottom-center
// capsule mounted on `RootView`) instead of an inline `Label` row in the
// Form. `clearCacheConfirmation` stays as the VoiceOver / test source of
// truth — toasts are transient and not reliably announced by VoiceOver.

public import Foundation
public import Persistence
public import SudokuEngine

@MainActor
@Observable
public final class SettingsViewModel {

    public let generatorVersion: GeneratorVersion
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
    private let toastController: ToastController?

    public init(
        generatorVersion: GeneratorVersion = .v1,
        appVersion: String = "1.0.0",
        persistence: any PersistenceProtocol,
        toastController: ToastController? = nil
    ) {
        self.generatorVersion = generatorVersion
        self.appVersion = appVersion
        self.persistence = persistence
        self.toastController = toastController
    }

    public func bootstrap() async {
        self.resumeCandidate = try? await persistence.latestInProgress()
    }

    /// Confirm + execute "Clear cache": deletes the active in-progress
    /// record if one exists. No-op when nothing is cached.
    public func clearCache() async {
        if let candidate = resumeCandidate {
            try? await persistence.deleteAbandoned(recordName: candidate.recordName)
            self.resumeCandidate = nil
        }
        let message = "Cache cleared"
        self.clearCacheConfirmation = message
        toastController?.show(Toast(style: .success, message: message))
    }
}
