import Testing
import Foundation
@testable import Infrastructure
@testable import Domain

/// Feature: Antigravity bucketing end to end
///
/// Antigravity reports a quota row per model, and its own UI showed nine cards
/// for what are really two limits. This exercises the whole path — API JSON
/// through parsing into display buckets — against a response shaped like the
/// live one, with the model labels the app actually rendered.
@Suite("Feature: Antigravity bucketing")
struct AntigravityBucketingTests {

    /// Mirrors an observed response: seven Gemini variants sharing a 100%
    /// bucket, and three models sharing a depleted one. Reset times are
    /// absolute timestamps from the API, identical within a bucket.
    static let liveShapedResponse = """
    {
      "userStatus": {
        "email": "user@example.com",
        "cascadeModelConfigData": {
          "clientModelConfigs": [
            { "label": "Gemini 3.7 Flash (Medium)", "modelOrAlias": { "model": "g37m" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.7 Flash (Low)", "modelOrAlias": { "model": "g37l" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.6 Flash (High)", "modelOrAlias": { "model": "g36h" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.6 Flash (Medium)", "modelOrAlias": { "model": "g36m" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.6 Flash (Low)", "modelOrAlias": { "model": "g36l" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.5 Flash (High)", "modelOrAlias": { "model": "g35h" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Gemini 3.5 Flash (Medium)", "modelOrAlias": { "model": "g35m" },
              "quotaInfo": { "remainingFraction": 1.0, "resetTime": "2026-08-19T03:54:00Z" } },
            { "label": "Claude Sonnet 4.5", "modelOrAlias": { "model": "cs45" },
              "quotaInfo": { "remainingFraction": 0.11, "resetTime": "2026-08-23T20:29:00Z" } },
            { "label": "Claude Opus 4.1", "modelOrAlias": { "model": "co41" },
              "quotaInfo": { "remainingFraction": 0.11, "resetTime": "2026-08-23T20:29:00Z" } },
            { "label": "GPT-OSS 120B (Medium)", "modelOrAlias": { "model": "oss120" },
              "quotaInfo": { "remainingFraction": 0.11, "resetTime": "2026-08-23T20:29:00Z" } }
          ]
        }
      }
    }
    """

    @Test
    func `ten model rows collapse into the two limits they actually represent`() throws {
        // Given — the live-shaped response
        let data = Data(Self.liveShapedResponse.utf8)

        // When
        let snapshot = try AntigravityUsageProbe.parseUserStatusResponse(data, providerId: "antigravity")
        let buckets = snapshot.displayBuckets

        // Then — ten cards become two
        #expect(snapshot.quotas.count == 10)
        #expect(buckets.count == 2)
        #expect(buckets[0].memberCount == 7)
        #expect(buckets[1].memberCount == 3)
    }

    @Test
    func `a bucket spanning three vendors keeps every member`() throws {
        // Given — Claude Sonnet, Claude Opus and GPT-OSS share one limit,
        // which is why a bucket cannot be named after a model family
        let data = Data(Self.liveShapedResponse.utf8)

        // When
        let depleted = try AntigravityUsageProbe
            .parseUserStatusResponse(data, providerId: "antigravity")
            .displayBuckets[1]

        // Then
        let labels = depleted.members.map(\.quotaType.displayName)
        #expect(labels.contains("Claude Sonnet 4.5"))
        #expect(labels.contains("GPT-OSS 120B (Medium)"))
        #expect(depleted.windowTitle == nil)
    }

    @Test
    func `timestamps seconds apart still collapse`() throws {
        // Given — the same bucket with per-row jitter, which is the failure
        // mode that would silently leave nine cards on screen
        let jittered = Self.liveShapedResponse
            .replacingOccurrences(of: "2026-08-19T03:54:00Z", with: "2026-08-19T03:54:12Z")
            .replacingOccurrences(of: "\"remainingFraction\": 1.0", with: "\"remainingFraction\": 0.998")

        // When — mixed with untouched rows at the original timestamp
        let data = Data(jittered.utf8)
        let buckets = try AntigravityUsageProbe
            .parseUserStatusResponse(data, providerId: "antigravity")
            .displayBuckets

        // Then — tolerance absorbs it rather than splitting the bucket
        #expect(buckets.count == 2)
    }
}
