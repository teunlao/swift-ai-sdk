import Foundation
import Testing
import EventSourceParser
@testable import SwiftAISDK

@Suite("ParseJsonEventStream")
struct ParseJsonEventStreamTests {
    private struct TestPayload: Codable, Equatable, Sendable {
        let a: Int
    }

    private func makeSchema() -> FlexibleSchema<TestPayload> {
        let jsonSchema: JSONValue = [
            "type": "object",
            "properties": [
                "a": ["type": "number"]
            ],
            "required": [.string("a")]
        ]

        return FlexibleSchema(
            Schema.codable(TestPayload.self, jsonSchema: jsonSchema)
        )
    }

    private func makeSSEStream(events: [String]) -> AsyncThrowingStream<Data, Error> {
        AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data(event.utf8))
            }
            continuation.finish()
        }
    }

    private func collectResults<T>(
        _ stream: AsyncThrowingStream<ParseJSONResult<T>, Error>
    ) async throws -> [ParseJSONResult<T>] {
        var results: [ParseJSONResult<T>] = []
        for try await result in stream {
            results.append(result)
        }
        return results
    }

    @Test("parses valid SSE events")
    func parsesValidSSEEvents() async throws {
        let stream = makeSSEStream(events: [
            "data: {\"a\":1}\n\n",
            "data: {\"a\":2}\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 2)

        if case .success(let first, _) = results[0] {
            #expect(first.a == 1)
        } else {
            Issue.record("Expected success for first event")
        }

        if case .success(let second, _) = results[1] {
            #expect(second.a == 2)
        } else {
            Issue.record("Expected success for second event")
        }
    }

    @Test("ignores [DONE] marker")
    func ignoresDoneMarker() async throws {
        let stream = makeSSEStream(events: [
            "data: {\"a\":1}\n\n",
            "data: [DONE]\n\n",
            "data: {\"a\":2}\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        // Should only have 2 results (ignoring [DONE])
        #expect(results.count == 2)

        if case .success(let first, _) = results[0] {
            #expect(first.a == 1)
        } else {
            Issue.record("Expected success for first event")
        }

        if case .success(let second, _) = results[1] {
            #expect(second.a == 2)
        } else {
            Issue.record("Expected success for second event")
        }
    }

    @Test("handles multiline SSE data")
    func handlesMultilineSSEData() async throws {
        let stream = makeSSEStream(events: [
            "data: {\"a\":\n",
            "data: 42}\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 1)

        if case .success(let payload, _) = results[0] {
            #expect(payload.a == 42)
        } else {
            Issue.record("Expected success for multiline event")
        }
    }

    @Test("handles invalid JSON with failure result")
    func handlesInvalidJSON() async throws {
        let stream = makeSSEStream(events: [
            "data: {invalid json}\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 1)

        if case .failure(let error, _) = results[0] {
            #expect(error is JSONParseError)
        } else {
            Issue.record("Expected failure for invalid JSON")
        }
    }

    @Test("handles schema validation failure")
    func handlesSchemaValidationFailure() async throws {
        let stream = makeSSEStream(events: [
            "data: {\"b\":99}\n\n"  // Missing required field 'a'
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 1)

        if case .failure(let error, _) = results[0] {
            #expect(error is TypeValidationError || error is DecodingError)
        } else {
            Issue.record("Expected failure for validation error")
        }
    }

    @Test("handles empty stream")
    func handlesEmptyStream() async throws {
        let stream = makeSSEStream(events: [])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 0)
    }

    @Test("handles stream with only [DONE]")
    func handlesOnlyDoneMarker() async throws {
        let stream = makeSSEStream(events: [
            "data: [DONE]\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 0)
    }

    @Test("handles fragmented SSE chunks")
    func handlesFragmentedChunks() async throws {
        // Simulate network-level chunking where SSE event is split across multiple Data chunks
        let stream = makeSSEStream(events: [
            "data: {\"a",  // Fragment 1
            "\":1}\n\n"    // Fragment 2
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 1)

        if case .success(let payload, _) = results[0] {
            #expect(payload.a == 1)
        } else {
            Issue.record("Expected success for fragmented event")
        }
    }

    @Test("handles events with custom event types")
    func handlesCustomEventTypes() async throws {
        let stream = makeSSEStream(events: [
            "event: custom\n",
            "data: {\"a\":100}\n\n"
        ])

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 1)

        if case .success(let payload, _) = results[0] {
            #expect(payload.a == 100)
        } else {
            Issue.record("Expected success for custom event type")
        }
    }

    @Test("processes multiple events in rapid succession")
    func processesRapidEvents() async throws {
        let events = (1...10).map { "data: {\"a\":\($0)}\n\n" }
        let stream = makeSSEStream(events: events)

        let resultStream = parseJsonEventStream(
            stream: stream,
            schema: makeSchema()
        )

        let results = try await collectResults(resultStream)

        #expect(results.count == 10)

        for (index, result) in results.enumerated() {
            if case .success(let payload, _) = result {
                #expect(payload.a == index + 1)
            } else {
                Issue.record("Expected success for event \(index + 1)")
            }
        }
    }
}
