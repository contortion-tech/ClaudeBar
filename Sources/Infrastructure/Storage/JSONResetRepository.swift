import Foundation
import Domain

/// File-backed `ResetRepository`.
///
/// Lives beside the settings store at `~/.claudebar/resets.json`. Kept separate
/// from settings because these records are derived state that can be deleted
/// without losing user configuration — the app simply relearns them on the next
/// successful refresh.
public final class JSONResetRepository: ResetRepository, @unchecked Sendable {

    public static let shared = JSONResetRepository()

    private let fileURL: URL
    private let lock = NSLock()
    private var cache: [String: StoredReset]?

    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
    }

    public static func defaultFileURL() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claudebar/resets.json")
    }

    // MARK: - ResetRepository

    public func storedReset(providerId: String, quotaKey: String) -> StoredReset? {
        lock.lock()
        defer { lock.unlock() }
        return load()[Self.key(providerId: providerId, quotaKey: quotaKey)]
    }

    public func record(_ reset: StoredReset, providerId: String, quotaKey: String) {
        lock.lock()
        defer { lock.unlock() }
        var records = load()
        records[Self.key(providerId: providerId, quotaKey: quotaKey)] = reset
        save(records)
    }

    public func clear(providerId: String, quotaKey: String) {
        lock.lock()
        defer { lock.unlock() }
        var records = load()
        records.removeValue(forKey: Self.key(providerId: providerId, quotaKey: quotaKey))
        save(records)
    }

    // MARK: - Storage

    /// Provider is part of the key because `quotaKey` is only unique within a
    /// provider — "model:gemini" exists under both Gemini and Antigravity.
    private static func key(providerId: String, quotaKey: String) -> String {
        "\(providerId)/\(quotaKey)"
    }

    /// Must be called while holding the lock.
    private func load() -> [String: StoredReset] {
        if let cache { return cache }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: StoredReset].self, from: data) else {
            cache = [:]
            return [:]
        }
        cache = decoded
        return decoded
    }

    /// Must be called while holding the lock.
    private func save(_ records: [String: StoredReset]) {
        cache = records
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(records) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
