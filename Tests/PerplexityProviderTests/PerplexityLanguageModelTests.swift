import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import PerplexityProvider

@Suite("PerplexityLanguageModel", .serialized)
struct PerplexityLanguageModelTests {
    private static let chatCompletionsURL = "https://api.perplexity.ai/chat/completions"

    private static let defaultPrompt: LanguageModelV3Prompt = [
        .user(content: [.text(.init(text: "Hello"))], providerOptions: nil),
    ]

    private static func headersLowercased(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }

    private static func decodeJSONBody(_ data: Data?) throws -> JSONValue {
        guard let data else { return .null }
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        return try jsonValue(from: json)
    }

    private static func jsonResponse(
        _ json: Any,
        url: String = chatCompletionsURL,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "application/json"]
    ) throws -> FetchResponse {
        let data = try JSONSerialization.data(withJSONObject: json)
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    private static func sseResponse(
        _ sse: String,
        url: String = chatCompletionsURL,
        status: Int = 200,
        headers: [String: String] = ["Content-Type": "text/event-stream"]
    ) -> FetchResponse {
        let data = Data(sse.utf8)
        let response = HTTPURLResponse(
            url: URL(string: url)!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    private static func collectStream(_ stream: AsyncThrowingStream<LanguageModelV3StreamPart, Error>) async throws -> [LanguageModelV3StreamPart] {
        var parts: [LanguageModelV3StreamPart] = []
        for try await part in stream {
            parts.append(part)
        }
        return parts
    }

    private static func makeModel(
        headers: @escaping @Sendable () -> [String: String?] = {
            [
                "authorization": "Bearer test-token",
                "content-type": "application/json",
            ]
        },
        generateId: @escaping @Sendable () -> String = { "id-0" },
        fetch: FetchFunction? = nil
    ) -> PerplexityLanguageModel {
        PerplexityLanguageModel(
            modelId: .sonar,
            config: .init(
                baseURL: "https://api.perplexity.ai",
                headers: headers,
                fetch: fetch,
                generateId: generateId
            )
        )
    }

    // MARK: - doGenerate

    @Test("doGenerate extracts text content")
    func doGenerateExtractsText() async throws {
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == Self.chatCompletionsURL)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "Hello from Perplexity"],
                    "finish_reason": "stop",
                ]],
                "usage": [
                    "prompt_tokens": 11,
                    "completion_tokens": 392,
                    "total_tokens": 403,
                ],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        #expect(result.content == [.text(.init(text: "Hello from Perplexity"))])
        #expect(result.finishReason == .init(unified: .stop, raw: "stop"))
        #expect(result.usage.inputTokens.total == 11)
        #expect(result.usage.outputTokens.total == 392)
        #expect(result.usage.outputTokens.text == 392)
        #expect(result.usage.outputTokens.reasoning == 0)
    }

    @Test("doGenerate extracts citations as source content")
    func doGenerateExtractsCitations() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value: Int = 0

            func next() -> String {
                lock.lock()
                defer { lock.unlock() }
                let id = "id-\(value)"
                value += 1
                return id
            }
        }

        let counter = Counter()
        let generateId: @Sendable () -> String = { counter.next() }

        let fetch: FetchFunction = { _ in
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "Answer"],
                    "finish_reason": "stop",
                ]],
                "citations": [
                    "https://example.com/a",
                    "https://example.com/b",
                ],
            ])
        }

        let model = Self.makeModel(generateId: generateId, fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        #expect(result.content.count == 3)
        #expect(result.content.first == .text(.init(text: "Answer")))
        #expect(Array(result.content.dropFirst()) == [
            .source(.url(id: "id-0", url: "https://example.com/a", title: nil, providerMetadata: nil)),
            .source(.url(id: "id-1", url: "https://example.com/b", title: nil, providerMetadata: nil)),
        ])
    }

    @Test("doGenerate sends correct request body")
    func doGenerateSendsCorrectRequestBody() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        let request = try #require(await capture.value())
        let body = try Self.decodeJSONBody(request.httpBody)
        #expect(body == .object([
            "model": .string("sonar"),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Hello"),
                ]),
            ]),
        ]))
    }

    @Test("doGenerate passes through perplexity provider options")
    func doGeneratePassesProviderOptions() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(
            prompt: Self.defaultPrompt,
            providerOptions: [
                "perplexity": [
                    "search_recency_filter": .string("month"),
                    "return_images": .bool(true),
                ],
            ]
        ))

        let request = try #require(await capture.value())
        let body = try Self.decodeJSONBody(request.httpBody)
        #expect(body == .object([
            "model": .string("sonar"),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Hello"),
                ]),
            ]),
            "search_recency_filter": .string("month"),
            "return_images": .bool(true),
        ]))
    }

    @Test("doGenerate combines provider + request headers")
    func doGeneratePassesHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let model = Self.makeModel(
            headers: {
                [
                    "authorization": "Bearer test-api-key",
                    "Custom-Provider-Header": "provider-header-value",
                ]
            },
            fetch: fetch
        )

        _ = try await model.doGenerate(options: .init(
            prompt: Self.defaultPrompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let request = try #require(await capture.value())
        let headers = Self.headersLowercased(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["content-type"] == "application/json")
    }

    @Test("doGenerate exposes raw response headers")
    func doGenerateExposesRawResponseHeaders() async throws {
        let fetch: FetchFunction = { _ in
            return try Self.jsonResponse(
                [
                    "id": "test-id",
                    "created": 1_680_000_000,
                    "model": "sonar",
                    "choices": [[
                        "message": ["role": "assistant", "content": "ok"],
                        "finish_reason": "stop",
                    ]],
                ],
                headers: [
                    "Content-Type": "application/json",
                    "Content-Length": "123",
                    "Test-Header": "test-value",
                ]
            )
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        let headers = try #require(result.response?.headers)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["content-length"] == "123")
        #expect(headers["test-header"] == "test-value")
    }

    @Test("doGenerate includes response metadata (id, timestamp, modelId)")
    func doGenerateResponseMetadata() async throws {
        let created: Double = 1_230_000_000
        let fetch: FetchFunction = { _ in
            return try Self.jsonResponse([
                "id": "aec30d94-c6a5-4d30-935e-97dbe8de9f85",
                "created": created,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        #expect(result.response?.id == "aec30d94-c6a5-4d30-935e-97dbe8de9f85")
        #expect(result.response?.modelId == "sonar")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: created))
    }

    @Test("doGenerate handles PDF files with base64 encoding")
    func doGenerateHandlesPDFBase64() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this PDF")),
                .file(.init(
                    data: .base64("mock-pdf-data"),
                    mediaType: "application/pdf",
                    filename: "test.pdf"
                )),
            ], providerOptions: nil),
        ]

        let model = Self.makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(prompt: prompt))

        let request = try #require(await capture.value())
        let body = try Self.decodeJSONBody(request.httpBody)
        guard case .object(let dict) = body else {
            Issue.record("Expected request body object")
            return
        }
        guard case .array(let messages)? = dict["messages"] else {
            Issue.record("Expected messages array")
            return
        }
        guard case .object(let first)? = messages.first,
              case .array(let content)? = first["content"] else {
            Issue.record("Expected multipart content array")
            return
        }

        #expect(content == [
            .object([
                "type": .string("text"),
                "text": .string("Analyze this PDF"),
            ]),
            .object([
                "type": .string("file_url"),
                "file_url": .object(["url": .string("mock-pdf-data")]),
                "file_name": .string("test.pdf"),
            ]),
        ])
    }

    @Test("doGenerate handles PDF files with URLs")
    func doGenerateHandlesPDFURL() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": "ok"],
                    "finish_reason": "stop",
                ]],
            ])
        }

        let prompt: LanguageModelV3Prompt = [
            .user(content: [
                .text(.init(text: "Analyze this PDF")),
                .file(.init(
                    data: .url(URL(string: "https://example.com/test.pdf")!),
                    mediaType: "application/pdf",
                    filename: "test.pdf"
                )),
            ], providerOptions: nil),
        ]

        let model = Self.makeModel(fetch: fetch)
        _ = try await model.doGenerate(options: .init(prompt: prompt))

        let request = try #require(await capture.value())
        let body = try Self.decodeJSONBody(request.httpBody)
        guard case .object(let dict) = body else {
            Issue.record("Expected request body object")
            return
        }
        guard case .array(let messages)? = dict["messages"] else {
            Issue.record("Expected messages array")
            return
        }
        guard case .object(let first)? = messages.first,
              case .array(let content)? = first["content"] else {
            Issue.record("Expected multipart content array")
            return
        }

        #expect(content == [
            .object([
                "type": .string("text"),
                "text": .string("Analyze this PDF"),
            ]),
            .object([
                "type": .string("file_url"),
                "file_url": .object(["url": .string("https://example.com/test.pdf")]),
                "file_name": .string("test.pdf"),
            ]),
        ])
    }

    @Test("doGenerate extracts images into providerMetadata")
    func doGenerateExtractsImages() async throws {
        let fetch: FetchFunction = { _ in
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop",
                ]],
                "images": [[
                    "image_url": "https://example.com/image.jpg",
                    "origin_url": "https://example.com/image.jpg",
                    "height": 100,
                    "width": 100,
                ]],
                "usage": [
                    "prompt_tokens": 10,
                    "completion_tokens": 20,
                    "total_tokens": 30,
                ],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        let md = try #require(result.providerMetadata)
        #expect(md == [
            "perplexity": [
                "images": .array([
                    .object([
                        "height": .number(100),
                        "imageUrl": .string("https://example.com/image.jpg"),
                        "originUrl": .string("https://example.com/image.jpg"),
                        "width": .number(100),
                    ]),
                ]),
                "usage": .object([
                    "citationTokens": .null,
                    "numSearchQueries": .null,
                ]),
            ],
        ])
    }

    @Test("doGenerate extracts extended usage and providerMetadata usage")
    func doGenerateExtractsExtendedUsage() async throws {
        let fetch: FetchFunction = { _ in
            return try Self.jsonResponse([
                "id": "test-id",
                "created": 1_680_000_000,
                "model": "sonar",
                "choices": [[
                    "message": ["role": "assistant", "content": ""],
                    "finish_reason": "stop",
                ]],
                "usage": [
                    "prompt_tokens": 10,
                    "completion_tokens": 20,
                    "total_tokens": 30,
                    "citation_tokens": 30,
                    "num_search_queries": 40,
                    "reasoning_tokens": 50,
                ],
            ])
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doGenerate(options: .init(prompt: Self.defaultPrompt))

        #expect(result.usage.inputTokens.total == 10)
        #expect(result.usage.outputTokens.total == 20)
        #expect(result.usage.outputTokens.reasoning == 50)
        #expect(result.usage.outputTokens.text == -30)

        let md = try #require(result.providerMetadata)
        #expect(md["perplexity"]?["images"] == .null)
        #expect(md["perplexity"]?["usage"] == .object([
            "citationTokens": .number(30),
            "numSearchQueries": .number(40),
        ]))
    }

    // MARK: - doStream

    @Test("doStream sends correct request body (stream: true)")
    func doStreamSendsCorrectBody() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let sse = """
        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}

        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}

        data: [DONE]

        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return Self.sseResponse(sse)
        }

        let model = Self.makeModel(fetch: fetch)
        _ = try await model.doStream(options: .init(prompt: Self.defaultPrompt))

        let request = try #require(await capture.value())
        let body = try Self.decodeJSONBody(request.httpBody)
        #expect(body == .object([
            "model": .string("sonar"),
            "messages": .array([
                .object([
                    "role": .string("user"),
                    "content": .string("Hello"),
                ]),
            ]),
            "stream": .bool(true),
        ]))
    }

    @Test("doStream combines provider + request headers")
    func doStreamPassesHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }
        let capture = Capture()

        let sse = """
        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}

        data: [DONE]

        """

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return Self.sseResponse(sse)
        }

        let model = Self.makeModel(
            headers: {
                [
                    "authorization": "Bearer test-api-key",
                    "Custom-Provider-Header": "provider-header-value",
                ]
            },
            fetch: fetch
        )

        _ = try await model.doStream(options: .init(
            prompt: Self.defaultPrompt,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        let request = try #require(await capture.value())
        let headers = Self.headersLowercased(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")
        #expect(headers["content-type"] == "application/json")
    }

    @Test("doStream exposes raw response headers")
    func doStreamExposesRawResponseHeaders() async throws {
        let sse = """
        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}

        data: [DONE]

        """

        let fetch: FetchFunction = { _ in
            Self.sseResponse(
                sse,
                headers: [
                    "Content-Type": "text/event-stream",
                    "Cache-Control": "no-cache",
                    "Connection": "keep-alive",
                    "Test-Header": "test-value",
                ]
            )
        }

        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: Self.defaultPrompt))
        let headers = try #require(result.response?.headers)

        #expect(headers["content-type"] == "text/event-stream")
        #expect(headers["cache-control"] == "no-cache")
        #expect(headers["connection"] == "keep-alive")
        #expect(headers["test-header"] == "test-value")
    }

    @Test("doStream streams images into finish providerMetadata")
    func doStreamStreamsImages() async throws {
        let sse = """
        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"images\":[{\"image_url\":\"https://example.com/image.jpg\",\"origin_url\":\"https://example.com/image.jpg\",\"height\":100,\"width\":100}],\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}

        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":20,\"total_tokens\":30}}

        data: [DONE]

        """

        let fetch: FetchFunction = { _ in Self.sseResponse(sse) }
        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: Self.defaultPrompt))
        let parts = try await Self.collectStream(result.stream)
        let finish = try #require(parts.first { if case .finish = $0 { return true } else { return false } })

        guard case .finish(_, _, let providerMetadata) = finish else {
            Issue.record("Expected finish part")
            return
        }

        let md = try #require(providerMetadata)
        #expect(md["perplexity"]?["images"] != .null)
    }

    @Test("doStream streams extended usage into finish")
    func doStreamStreamsExtendedUsage() async throws {
        let sse = """
        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}

        data: {\"id\":\"stream-id\",\"created\":1680003600,\"model\":\"sonar\",\"choices\":[{\"delta\":{\"role\":\"assistant\",\"content\":\"\"},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":11,\"completion_tokens\":21,\"total_tokens\":32,\"citation_tokens\":30,\"num_search_queries\":40,\"reasoning_tokens\":50}}

        data: [DONE]

        """

        let fetch: FetchFunction = { _ in Self.sseResponse(sse) }
        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: Self.defaultPrompt))
        let parts = try await Self.collectStream(result.stream)
        let finish = try #require(parts.first { if case .finish = $0 { return true } else { return false } })

        guard case let .finish(_, usage, providerMetadata) = finish else {
            Issue.record("Expected finish part")
            return
        }

        #expect(usage.inputTokens.total == 11)
        #expect(usage.outputTokens.total == 21)
        #expect(usage.outputTokens.reasoning == 50)
        #expect(usage.outputTokens.text == -29)

        let md = try #require(providerMetadata)
        #expect(md["perplexity"]?["usage"] == .object([
            "citationTokens": .number(30),
            "numSearchQueries": .number(40),
        ]))
    }

    @Test("doStream includeRawChunks emits raw + error parts for invalid chunks and keeps streaming")
    func doStreamIncludeRawChunks() async throws {
        let sse = """
        data: {\"id\":\"ppl-123\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"sonar\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}],\"citations\":[\"https://example.com\"]}

        data: {\"id\":\"ppl-456\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"sonar\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"},\"finish_reason\":null}]}

        data: {\"id\":\"ppl-789\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"sonar\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":5,\"total_tokens\":15,\"citation_tokens\":2,\"num_search_queries\":1}}

        data: [DONE]

        """

        let fetch: FetchFunction = { _ in Self.sseResponse(sse) }
        let model = Self.makeModel(fetch: fetch)
        let result = try await model.doStream(options: .init(prompt: Self.defaultPrompt, includeRawChunks: true))
        let parts = try await Self.collectStream(result.stream)

        // Must include raw parts and error parts (but should not throw).
        let rawParts = parts.compactMap { part -> JSONValue? in
            if case let .raw(raw) = part { return raw }
            return nil
        }
        let errorParts = parts.compactMap { part -> JSONValue? in
            if case let .error(error) = part { return error }
            return nil
        }

        #expect(rawParts.count == 3)
        #expect(errorParts.count == 2)

        // Still should finish cleanly.
        #expect(parts.contains { if case .finish = $0 { return true } else { return false } })

        // First chunk should produce response metadata + citation + text start/delta.
        #expect(parts.contains { if case .responseMetadata(let id, _, _) = $0 { return id == "ppl-123" } else { return false } })
        #expect(parts.contains { if case .source(.url(_, let url, _, _)) = $0 { return url == "https://example.com" } else { return false } })
        #expect(parts.contains { if case .textDelta(_, let delta, _) = $0 { return delta == "Hello" } else { return false } })

        // Error strings should mention type validation / decoding.
        for error in errorParts {
            if case let .string(message) = error {
                #expect(message.lowercased().contains("type") || message.lowercased().contains("decode") || message.lowercased().contains("validation"))
            } else {
                Issue.record("Expected error to be a string JSON value")
            }
        }
    }
}
