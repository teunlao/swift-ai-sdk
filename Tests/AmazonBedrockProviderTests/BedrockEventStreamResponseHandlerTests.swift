import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AmazonBedrockProvider

@Suite("BedrockEventStreamResponseHandler")
struct BedrockEventStreamResponseHandlerTests {
    private func makeHTTPResponse(
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://example.com/test"))
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeProviderResponse(
        body: ProviderHTTPResponseBody,
        headers: [String: String] = [:]
    ) throws -> ProviderHTTPResponse {
        let http = try makeHTTPResponse(headers: headers)
        let url = try #require(http.url)
        return ProviderHTTPResponse(url: url, httpResponse: http, body: body, statusText: nil)
    }

    private func makeSchemaRequiringChunkContent() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "chunk": .object([
                            "type": .string("object"),
                            "properties": .object([
                                "content": .object(["type": .string("string")])
                            ]),
                            "required": .array([.string("content")]),
                            "additionalProperties": .bool(false),
                        ])
                    ]),
                    "required": .array([.string("chunk")]),
                    "additionalProperties": .bool(false),
                ])
            )
        )
    }

    @Test("throws EmptyResponseBodyError when response body is none")
    func throwsOnEmptyBody() async throws {
        let handler = createBedrockEventStreamResponseHandler(chunkSchema: makeSchemaRequiringChunkContent())
        let providerResponse = try makeProviderResponse(body: .none)
        let input = ResponseHandlerInput(url: "https://example.com/test", requestBodyValues: nil, response: providerResponse)

        await #expect(throws: EmptyResponseBodyError.self) {
            _ = try await handler(input)
        }
    }

    @Test("successfully processes a valid event stream message")
    func processesValidMessage() async throws {
        let handler = createBedrockEventStreamResponseHandler(chunkSchema: makeSchemaRequiringChunkContent())

        let frame = try BedrockTestEventStream.jsonMessage(
            eventType: "chunk",
            payload: ["content": "test message"]
        )

        let providerResponse = try makeProviderResponse(body: .stream(BedrockTestEventStream.makeStream([frame])))
        let input = ResponseHandlerInput(url: "https://example.com/test", requestBodyValues: nil, response: providerResponse)
        let result = try await handler(input)

        let chunks = try await convertReadableStreamToArray(result.value)
        #expect(chunks.count == 1)

        switch chunks.first {
        case .success(let value, _):
            #expect(value == .object(["chunk": .object(["content": .string("test message")])]))
        case .failure(let error, _):
            Issue.record("Expected success, got failure: \(String(describing: error))")
        case .none:
            Issue.record("Expected one chunk")
        }
    }

    @Test("yields a failure for invalid JSON payloads")
    func yieldsFailureOnInvalidJSON() async throws {
        let handler = createBedrockEventStreamResponseHandler(chunkSchema: makeSchemaRequiringChunkContent())

        let invalidBody = Data("invalid json".utf8)
        let frame = BedrockTestEventStream.frame(
            headers: [
                ":message-type": "event",
                ":event-type": "chunk",
            ],
            body: invalidBody
        )

        let providerResponse = try makeProviderResponse(body: .stream(BedrockTestEventStream.makeStream([frame])))
        let input = ResponseHandlerInput(url: "https://example.com/test", requestBodyValues: nil, response: providerResponse)
        let result = try await handler(input)

        let chunks = try await convertReadableStreamToArray(result.value)
        #expect(chunks.count == 1)

        switch chunks.first {
        case .failure:
            #expect(true)
        case .success(let value, _):
            Issue.record("Expected failure, got success: \(value)")
        case .none:
            Issue.record("Expected one chunk")
        }
    }

    @Test("yields a failure for schema validation errors")
    func yieldsFailureOnSchemaMismatch() async throws {
        let handler = createBedrockEventStreamResponseHandler(chunkSchema: makeSchemaRequiringChunkContent())

        let frame = try BedrockTestEventStream.jsonMessage(
            eventType: "chunk",
            payload: ["invalid": "data"]
        )

        let providerResponse = try makeProviderResponse(body: .stream(BedrockTestEventStream.makeStream([frame])))
        let input = ResponseHandlerInput(url: "https://example.com/test", requestBodyValues: nil, response: providerResponse)
        let result = try await handler(input)

        let chunks = try await convertReadableStreamToArray(result.value)
        #expect(chunks.count == 1)

        switch chunks.first {
        case .failure:
            #expect(true)
        case .success(let value, _):
            Issue.record("Expected failure, got success: \(value)")
        case .none:
            Issue.record("Expected one chunk")
        }
    }

    @Test("buffers partial frames and emits only when complete")
    func buffersPartialFrames() async throws {
        let handler = createBedrockEventStreamResponseHandler(chunkSchema: makeSchemaRequiringChunkContent())

        let frame = try BedrockTestEventStream.jsonMessage(
            eventType: "chunk",
            payload: ["content": "complete message"]
        )

        let splitIndex = max(1, frame.count / 2)
        let first = frame.prefix(splitIndex)
        let second = frame.dropFirst(splitIndex)

        let providerResponse = try makeProviderResponse(body: .stream(BedrockTestEventStream.makeStream([Data(first), Data(second)])))
        let input = ResponseHandlerInput(url: "https://example.com/test", requestBodyValues: nil, response: providerResponse)
        let result = try await handler(input)

        let chunks = try await convertReadableStreamToArray(result.value)
        #expect(chunks.count == 1)

        switch chunks.first {
        case .success(let value, _):
            #expect(value == .object(["chunk": .object(["content": .string("complete message")])]))
        case .failure(let error, _):
            Issue.record("Expected success, got failure: \(String(describing: error))")
        case .none:
            Issue.record("Expected one chunk")
        }
    }
}

