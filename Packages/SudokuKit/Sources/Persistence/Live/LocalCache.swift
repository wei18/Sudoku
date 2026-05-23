// LocalCache — file-system store inside the App container that survives
// offline / signed-out periods (§How.6.5 Case A/B).
//
// Per docs/v1/design.md §How.6.5 Case A: read paths against the local cache
// continue to work even when CloudKit is unreachable; Case B: the
// in-progress snapshot flushes to the local cache when iCloud goes away
// mid-session.
//
// The on-disk format is a JSON blob per file, namespaced under a single
// directory. Concurrency is serialized through the actor — callers never
// touch FileManager directly.

public import Foundation

public actor LocalCache {

    private let baseURL: URL
    private let fileManager: FileManager

    public init(baseURL: URL, fileManager: FileManager = .default) {
        self.baseURL = baseURL
        self.fileManager = fileManager
    }

    public func ensureReady() async throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    public func load(name: String) async throws -> Data? {
        let url = baseURL.appendingPathComponent(name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try Data(contentsOf: url)
    }

    public func store(name: String, data: Data) async throws {
        try await ensureReady()
        let url = baseURL.appendingPathComponent(name)
        try data.write(to: url, options: .atomic)
    }

    public func remove(name: String) async throws {
        let url = baseURL.appendingPathComponent(name)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    public func wipe() async throws {
        if fileManager.fileExists(atPath: baseURL.path) {
            try fileManager.removeItem(at: baseURL)
        }
    }
}
