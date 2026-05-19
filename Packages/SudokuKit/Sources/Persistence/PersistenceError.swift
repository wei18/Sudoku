// PersistenceError — taxonomy for the Persistence module.
//
// Per design.md §How.6.5 (account cases) + §How.6.7 (sync conflict) +
// §How.6.8 (schema version) + §How.6.2 (general error surface).
//
// `underlying` carries an erased description so the Persistence target does
// NOT need to import CloudKit at the surface — CloudKit-specific NSError
// payloads are projected into this case at the live-impl seam.

import Foundation

public enum PersistenceError: Error, Sendable, Equatable {
    case iCloudNotSignedIn
    case iCloudSignedOutDuringSession
    case iCloudAccountChanged
    case quotaExceeded
    case zoneNotProvisioned
    case syncConflict(recordName: String)
    case schemaVersionTooNew(expected: Int, found: Int)
    case underlying(domain: String, code: Int, description: String)
}
