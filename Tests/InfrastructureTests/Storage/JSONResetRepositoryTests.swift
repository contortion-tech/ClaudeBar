import Testing
import Foundation
@testable import Domain
@testable import Infrastructure

/// Feature: Reset Persistence
///
/// Reset times survive app restarts so a provider that reports one only
/// occasionally still shows a running countdown.
@Suite("Feature: Reset Persistence")
struct JSONResetRepositoryTests {

    private static func makeRepository() -> (JSONResetRepository, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("claudebar-tests-\(UUID().uuidString)")
            .appendingPathComponent("resets.json")
        return (JSONResetRepository(fileURL: url), url)
    }

    @Test
    func `a recorded reset can be read back`() {
        // Given
        let (repository, url) = Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reset = StoredReset(date: Date(timeIntervalSince1970: 1_000_000), source: .probe, recordedAt: Date())

        // When
        repository.record(reset, providerId: "antigravity", quotaKey: "model:gemini")

        // Then
        #expect(repository.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == reset)
    }

    @Test
    func `records survive a new repository over the same file`() {
        // Given — a record written by one instance
        let (repository, url) = Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reset = StoredReset(date: Date(timeIntervalSince1970: 1_000_000), source: .manual, recordedAt: Date())
        repository.record(reset, providerId: "antigravity", quotaKey: "model:gemini")

        // When — the app restarts
        let reopened = JSONResetRepository(fileURL: url)

        // Then — the countdown resumes instead of starting blank
        #expect(reopened.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == reset)
    }

    @Test
    func `the same quota key under two providers stays separate`() {
        // Given — "model:gemini" exists under both Gemini and Antigravity
        let (repository, url) = Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let first = StoredReset(date: Date(timeIntervalSince1970: 1_000), source: .probe, recordedAt: Date())
        let second = StoredReset(date: Date(timeIntervalSince1970: 2_000), source: .probe, recordedAt: Date())

        // When
        repository.record(first, providerId: "antigravity", quotaKey: "model:gemini")
        repository.record(second, providerId: "gemini", quotaKey: "model:gemini")

        // Then
        #expect(repository.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == first)
        #expect(repository.storedReset(providerId: "gemini", quotaKey: "model:gemini") == second)
    }

    @Test
    func `clearing removes a manual entry`() {
        // Given
        let (repository, url) = Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let reset = StoredReset(date: Date(), source: .manual, recordedAt: Date())
        repository.record(reset, providerId: "antigravity", quotaKey: "model:gemini")

        // When
        repository.clear(providerId: "antigravity", quotaKey: "model:gemini")

        // Then
        #expect(repository.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == nil)
    }

    @Test
    func `a missing file reads as empty rather than failing`() {
        // Given — first launch, no file yet
        let (repository, _) = Self.makeRepository()

        // Then
        #expect(repository.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == nil)
    }

    @Test
    func `recording twice keeps the newer value`() {
        // Given — a provider reporting a fresh reset over a remembered one
        let (repository, url) = Self.makeRepository()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let old = StoredReset(date: Date(timeIntervalSince1970: 1_000), source: .probe, recordedAt: Date())
        let new = StoredReset(date: Date(timeIntervalSince1970: 9_000), source: .probe, recordedAt: Date())

        // When
        repository.record(old, providerId: "antigravity", quotaKey: "model:gemini")
        repository.record(new, providerId: "antigravity", quotaKey: "model:gemini")

        // Then
        #expect(repository.storedReset(providerId: "antigravity", quotaKey: "model:gemini") == new)
    }
}
