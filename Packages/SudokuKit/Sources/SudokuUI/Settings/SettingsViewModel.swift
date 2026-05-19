// SettingsViewModel — read-only status surface + clear-cache action.
//
// Per docs/designs/08-settings.md. Synchronous reads + memoized snapshots;
// no loading state. `clearCache()` deletes the active in-progress saved
// game (if any) via Persistence — the closest "session cache" hook on the
// PersistenceProtocol surface today.

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

    /// Set by `clearCache()` after the persistence write completes.
    public private(set) var clearCacheConfirmation: String?

    private let persistence: any PersistenceProtocol

    public init(
        generatorVersion: GeneratorVersion = .v1,
        appVersion: String = "1.0.0",
        persistence: any PersistenceProtocol
    ) {
        self.generatorVersion = generatorVersion
        self.appVersion = appVersion
        self.persistence = persistence
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
        self.clearCacheConfirmation = "Cache cleared"
    }
}
