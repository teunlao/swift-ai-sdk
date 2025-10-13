import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("Response Handler")
struct ResponseHandlerTests {
    private struct SimplePayload: Codable, Equatable, Sendable {
        let a: Int
    }

    private func makeResponse(
        status: Int = 200,
        statusText: String? = nil,
        headers: [String: String] = [:],
        body: ProviderHTTPResponseBody
    ) -> ProviderHTTPResponse {
        let url = URL(string: "https://example.com")!
        guard let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ) else {
            fatalError("Failed to create HTTPURLResponse")
        }

        return ProviderHTTPResponse(
            url: url,
            httpResponse: httpResponse,
            body: body,
            statusText: statusText
        )
    }

    private func jsonSchemaForSimplePayload() -> FlexibleSchema<SimplePayload> {
        let schema: JSONValue = [
            "type": "object",
            "properties": [
                "a": ["type": "number"]
            ],
            "required": [.string("a")]
        ]

        return FlexibleSchema(
            Schema.codable(
                SimplePayload.self,
                jsonSchema: schema
            )
        )
    }

    private func streamBody(from chunks: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for chunk in chunks {
                continuation.yield(Data(chunk.utf8))
            }
            continuation.finish()
        })
    }

    private func collectStream<T>(
        _ stream: AsyncThrowingStream<ParseJSONResult<T>, Error>
    ) async throws -> [ParseJSONResult<T>] {
        var items: [ParseJSONResult<T>] = []
        for try await item in stream {
            items.append(item)
        }
        return items
    }

    @Test("createJsonStreamResponseHandler yields complete JSON objects")
    func jsonStreamHandlerParsesChunks() async throws {
        let handler = createJsonStreamResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let response = makeResponse(
            body: streamBody(from: [
                "{\"a\":1}\n",
                "{\"a\":2}\n"
            ])
        )

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        let items = try await collectStream(result.value)
        #expect(items.count == 2)

        if case .success(let first, let raw) = items[0] {
            #expect(first == SimplePayload(a: 1))
            #expect((raw as? [String: Any])?["a"] as? Int == 1)
        } else {
            Issue.record("Expected success for first payload")
        }

        if case .success(let second, let raw) = items[1] {
            #expect(second == SimplePayload(a: 2))
            #expect((raw as? [String: Any])?["a"] as? Int == 2)
        } else {
            Issue.record("Expected success for second payload")
        }
    }

    @Test("createJsonStreamResponseHandler handles fragmented JSON chunks")
    func jsonStreamHandlerParsesFragmentedChunks() async throws {
        let handler = createJsonStreamResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let response = makeResponse(
            body: streamBody(from: ["{\"a\":", "1}\n"])
        )

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        let items = try await collectStream(result.value)
        #expect(items.count == 1)

        if case .success(let payload, let raw) = items[0] {
            #expect(payload == SimplePayload(a: 1))
            #expect((raw as? [String: Any])?["a"] as? Int == 1)
        } else {
            Issue.record("Expected success payload")
        }
    }

    @Test("createJsonResponseHandler returns parsed value and rawValue")
    func jsonResponseHandlerReturnsParsedValue() async throws {
        let handler = createJsonResponseHandler(
            responseSchema: jsonSchemaForSimplePayload()
        )

        let body = try JSONEncoder().encode(SimplePayload(a: 42))
        let response = makeResponse(body: .data(body))

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        #expect(result.value == SimplePayload(a: 42))
        #expect((result.rawValue as? [String: Any])?["a"] as? Int == 42)
    }

    @Test("createBinaryResponseHandler returns binary data")
    func binaryResponseHandlerReturnsData() async throws {
        let handler = createBinaryResponseHandler()
        let binary = Data([1, 2, 3, 4])
        let response = makeResponse(body: .data(binary))

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: nil,
                response: response
            )
        )

        #expect(result.value == binary)
    }

    @Test("createBinaryResponseHandler throws when body missing")
    func binaryResponseHandlerThrowsOnMissingBody() async {
        let handler = createBinaryResponseHandler()
        let response = makeResponse(body: .none)

        await #expect(throws: APICallError.self) {
            _ = try await handler(
                ResponseHandlerInput(
                    url: response.url.absoluteString,
                    requestBodyValues: nil,
                    response: response
                )
            )
        }
    }

    @Test("createStatusCodeErrorResponseHandler returns APICallError")
    func statusCodeErrorHandlerReturnsError() async throws {
        let handler = createStatusCodeErrorResponseHandler()
        let response = makeResponse(
            status: 404,
            statusText: "Not Found",
            body: .data(Data("Error".utf8))
        )

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: ["some": "data"],
                response: response
            )
        )

        #expect(result.value.statusCode == 404)
        #expect(result.value.message == "Not Found")
        #expect(result.value.responseBody == "Error")
        #expect(result.value.url == response.url.absoluteString)
    }

    // MARK: - Event Source Response Handler Tests

    @Test("createEventSourceResponseHandler parses SSE events")
    func eventSourceHandlerParsesSSEEvents() async throws {
        let handler = createEventSourceResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let sseData = """
        data: {"a":1}

        data: {"a":2}


        """

        let response = makeResponse(body: .data(Data(sseData.utf8)))

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        let items = try await collectStream(result.value)

        #expect(items.count == 2)

        if case .success(let first, _) = items[0] {
            #expect(first.a == 1)
        } else {
            Issue.record("Expected success for first SSE event")
        }

        if case .success(let second, _) = items[1] {
            #expect(second.a == 2)
        } else {
            Issue.record("Expected success for second SSE event")
        }
    }

    @Test("createEventSourceResponseHandler throws on empty body")
    func eventSourceHandlerThrowsOnEmptyBody() async {
        let handler = createEventSourceResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let response = makeResponse(body: .none)

        await #expect(throws: EmptyResponseBodyError.self) {
            _ = try await handler(
                ResponseHandlerInput(
                    url: response.url.absoluteString,
                    requestBodyValues: [:],
                    response: response
                )
            )
        }
    }

    @Test("createEventSourceResponseHandler ignores [DONE] marker")
    func eventSourceHandlerIgnoresDoneMarker() async throws {
        let handler = createEventSourceResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let sseData = """
        data: {"a":1}

        data: [DONE]

        data: {"a":2}


        """

        let response = makeResponse(body: .data(Data(sseData.utf8)))

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        let items = try await collectStream(result.value)

        // Should only have 2 results (ignoring [DONE])
        #expect(items.count == 2)
    }

    @Test("createEventSourceResponseHandler extracts response headers")
    func eventSourceHandlerExtractsHeaders() async throws {
        let handler = createEventSourceResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let response = makeResponse(
            headers: ["X-Custom-Header": "test-value"],
            body: .data(Data("data: {\"a\":1}\n\n".utf8))
        )

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        // Headers are normalized to lowercase by extractResponseHeaders
        #expect(result.responseHeaders["X-Custom-Header"] == "test-value")
    }

    @Test("createEventSourceResponseHandler handles streaming body")
    func eventSourceHandlerHandlesStreamingBody() async throws {
        let handler = createEventSourceResponseHandler(
            chunkSchema: jsonSchemaForSimplePayload()
        )

        let response = makeResponse(
            body: streamBody(from: [
                "data: {\"a\":1}\n\n",
                "data: {\"a\":2}\n\n"
            ])
        )

        let result = try await handler(
            ResponseHandlerInput(
                url: response.url.absoluteString,
                requestBodyValues: [:],
                response: response
            )
        )

        let items = try await collectStream(result.value)

        #expect(items.count == 2)

        if case .success(let first, _) = items[0] {
            #expect(first.a == 1)
        } else {
            Issue.record("Expected success for first streaming event")
        }

        if case .success(let second, _) = items[1] {
            #expect(second.a == 2)
        } else {
            Issue.record("Expected success for second streaming event")
        }
    }
}
