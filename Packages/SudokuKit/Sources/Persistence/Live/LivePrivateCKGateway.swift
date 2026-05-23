// LivePrivateCKGateway — production CloudKit Private DB adapter.
//
// COMPILE-ONLY in Phase 5; live behavior is validated in Phase 10
// (plan.md). All unit tests run against `FakePrivateCKGateway`.
//
// Per docs/v1/design.md §How.2:
//   - custom zone `com.wei18.sudoku.userZone`
//   - single `CKDatabaseSubscription` named `com.wei18.sudoku.userZone.changes`
//   - record types `SavedGame` / `PersonalRecord`
//
// CloudKit is the ONLY place CloudKit is imported in the package — it is
// kept inside this `Live/` subfolder so accidental imports from other
// modules are easy to spot in review.

internal import CloudKit
internal import Foundation

internal actor LivePrivateCKGateway: PrivateCKGateway {

    private let container: CKContainer
    private let database: CKDatabase
    internal let zoneID: CKRecordZone.ID

    private var zoneProvisioned: Bool = false
    private var subscriptionInstalled: Bool = false

    init(container: CKContainer = .default()) {
        self.container = container
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(
            zoneName: PrivateCKConstants.zoneName,
            ownerName: CKCurrentUserDefaultName
        )
    }

    func provisionZone() async throws {
        guard !zoneProvisioned else { return }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
        zoneProvisioned = true
    }

    func installSubscriptionIfNeeded() async throws {
        guard !subscriptionInstalled else { return }
        let subscription = CKDatabaseSubscription(subscriptionID: PrivateCKConstants.subscriptionID)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true
        subscription.notificationInfo = notificationInfo
        _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
        subscriptionInstalled = true
    }

    func fetch(recordName: String) async throws -> RecordPayload? {
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        do {
            let record = try await database.record(for: id)
            return Self.payload(from: record)
        } catch let ckError as CKError where ckError.code == .unknownItem {
            return nil
        }
    }

    func save(_ payload: RecordPayload) async throws {
        let record = Self.record(from: payload, zoneID: zoneID)
        _ = try await database.save(record)
    }

    func delete(recordName: String) async throws {
        let id = CKRecord.ID(recordName: recordName, zoneID: zoneID)
        _ = try await database.deleteRecord(withID: id)
    }

    func query(_ predicate: RecordPredicate) async throws -> [RecordPayload] {
        let (recordType, nsPredicate) = Self.translate(predicate)
        let query = CKQuery(recordType: recordType, predicate: nsPredicate)
        let (matches, _) = try await database.records(matching: query, inZoneWith: zoneID)
        var results: [RecordPayload] = []
        for (_, result) in matches {
            switch result {
            case .success(let record):
                results.append(Self.payload(from: record))
            case .failure:
                continue
            }
        }
        return results
    }

    // MARK: - CKRecord <-> RecordPayload

    private static func record(from payload: RecordPayload, zoneID: CKRecordZone.ID) -> CKRecord {
        let id = CKRecord.ID(recordName: payload.recordName, zoneID: zoneID)
        let record = CKRecord(recordType: payload.recordType, recordID: id)
        for (key, value) in payload.fields {
            switch value {
            case .string(let string):
                record[key] = string as any CKRecordValue
            case .int(let int):
                record[key] = NSNumber(value: int) as any CKRecordValue
            case .date(let date):
                record[key] = date as any CKRecordValue
            case .data(let data):
                record[key] = data as any CKRecordValue
            case .stringSet(let strings):
                record[key] = strings as any CKRecordValue
            }
        }
        return record
    }

    private static func payload(from record: CKRecord) -> RecordPayload {
        var fields: [String: RecordValue] = [:]
        for key in record.allKeys() {
            guard let raw = record[key] else { continue }
            if let string = raw as? String {
                fields[key] = .string(string)
            } else if let date = raw as? Date {
                fields[key] = .date(date)
            } else if let data = raw as? Data {
                fields[key] = .data(data)
            } else if let strings = raw as? [String] {
                fields[key] = .stringSet(strings)
            } else if let number = raw as? NSNumber {
                fields[key] = .int(number.intValue)
            }
        }
        return RecordPayload(
            recordType: record.recordType,
            recordName: record.recordID.recordName,
            fields: fields
        )
    }

    private static func translate(_ predicate: RecordPredicate) -> (String, NSPredicate) {
        switch predicate {
        case .all(let type):
            return (type, NSPredicate(value: true))
        case let .statusEquals(type, status):
            return (type, NSPredicate(format: "status == %@", status))
        case .dailyCompletedOn(let dayPrefix):
            let predicate = NSPredicate(
                format: "mode == %@ AND status == %@ AND puzzleId BEGINSWITH %@",
                "daily", "completed", dayPrefix
            )
            return (PrivateCKConstants.savedGameRecordType, predicate)
        }
    }
}
