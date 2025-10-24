import Testing
import Foundation
@testable import AISDKJSONSchema
import AISDKProvider
import AISDKProviderUtils

@Test("FlexibleSchema.auto() decodes ISO8601 with fractional seconds")
func iso8601WithFractionalSeconds() async throws {
    struct Event: Codable, Sendable {
        let name: String
        let timestamp: Date
        let updated: Date?
    }

    let schema = FlexibleSchema.auto(Event.self)

    // Test with fractional seconds (.000Z)
    let jsonWithMillis: [String: Any] = [
        "name": "Test Event",
        "timestamp": "2025-10-24T14:30:00.000Z",
        "updated": "2025-10-24T15:45:30.123Z"
    ]

    let resolved = schema.resolve()
    let result = try await resolved.validate(jsonWithMillis)

    guard case .success(let event) = result else {
        Issue.record("Failed to decode ISO8601 with fractional seconds")
        return
    }

    #expect(event.name == "Test Event")

    // Check timestamp parsed correctly
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let expectedTimestamp = formatter.date(from: "2025-10-24T14:30:00.000Z")!
    let expectedUpdated = formatter.date(from: "2025-10-24T15:45:30.123Z")!

    #expect(abs(event.timestamp.timeIntervalSince(expectedTimestamp)) < 0.001)
    #expect(event.updated != nil)
    #expect(abs(event.updated!.timeIntervalSince(expectedUpdated)) < 0.001)
}

@Test("FlexibleSchema.auto() decodes ISO8601 without fractional seconds")
func iso8601WithoutFractionalSeconds() async throws {
    struct Event: Codable, Sendable {
        let name: String
        let createdAt: Date
    }

    let schema = FlexibleSchema.auto(Event.self)

    // Test without fractional seconds (fallback)
    let json: [String: Any] = [
        "name": "Legacy Event",
        "createdAt": "2025-10-24T14:30:00Z"
    ]

    let resolved = schema.resolve()
    let result = try await resolved.validate(json)

    guard case .success(let event) = result else {
        Issue.record("Failed to decode ISO8601 without fractional seconds")
        return
    }

    #expect(event.name == "Legacy Event")

    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    let expected = formatter.date(from: "2025-10-24T14:30:00Z")!

    #expect(abs(event.createdAt.timeIntervalSince(expected)) < 0.001)
}

@Test("FlexibleSchema.auto() rejects invalid date format")
func invalidDateFormat() async throws {
    struct Event: Codable, Sendable {
        let timestamp: Date
    }

    let schema = FlexibleSchema.auto(Event.self)

    // Invalid date format
    let json: [String: Any] = [
        "timestamp": "2025-10-24"  // Not ISO8601 datetime
    ]

    let resolved = schema.resolve()
    let result = try await resolved.validate(json)

    guard case .failure = result else {
        Issue.record("Should fail with invalid date format")
        return
    }

    // Success - correctly rejected invalid format
}

@Test("FlexibleSchema.auto() handles mixed Date formats in nested objects")
func mixedDateFormats() async throws {
    struct Author: Codable, Sendable {
        let name: String
        let registeredAt: Date
    }

    struct Post: Codable, Sendable {
        let title: String
        let author: Author
        let publishedAt: Date
        let updatedAt: Date?
    }

    let schema = FlexibleSchema.auto(Post.self)

    let json: [String: Any] = [
        "title": "Test Post",
        "author": [
            "name": "John",
            "registeredAt": "2024-01-01T00:00:00Z"  // Without millis
        ],
        "publishedAt": "2025-10-24T10:00:00.000Z",  // With millis
        "updatedAt": "2025-10-24T11:30:45.567Z"      // With millis
    ]

    let resolved = schema.resolve()
    let result = try await resolved.validate(json)

    guard case .success(let post) = result else {
        Issue.record("Failed to decode mixed Date formats")
        return
    }

    #expect(post.title == "Test Post")
    #expect(post.author.name == "John")
    #expect(post.updatedAt != nil)
}
