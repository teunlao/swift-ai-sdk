import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let completionPrompt: LanguageModelV3Prompt = [
    .user(
        content: [
            .text(LanguageModelV3TextPart(text: "Hello"))
        ],
        providerOptions: nil
    )
]

@Suite("OpenAICompletionLanguageModel")
struct OpenAICompletionLanguageModelTests {
    private func makeConfig(fetch: @escaping FetchFunction) -> OpenAIConfig {
        OpenAIConfig(
            provider: "openai.completion",
            url: { _ in "https://api.openai.com/v1/completions" },
            headers: { ["Authorization": "Bearer test-api-key"] },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_711_363_706) })
        )
    }

    private func makeLogprobsValue() -> JSONValue {
        .object([
            "tokens": .array([
                .string("Hello"),
                .string(","),
                .string(" World!")
            ]),
            "token_logprobs": .array([
                .number(-0.01),
                .number(-0.02),
                .number(-0.03)
            ]),
            "top_logprobs": .array([
                .object(["Hello": .number(-0.01)]),
                .object([",": .number(-0.02)]),
                .object([" World!": .number(-0.03)])
            ])
        ])
    }

    // MARK: - doGenerate Tests

    @Test("should extract text response")
    func testExtractTextResponse() async throws {
        let responseJSON: [String: Any] = [
            "id": "cmpl-96cAM1v77r4jXa4qb2NSmRREV5oWB",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "Hello, World!",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        #expect(result.content.count == 1)
        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract usage")
    func testExtractUsage() async throws {
        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 20,
                "completion_tokens": 5,
                "total_tokens": 25
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 5)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 25)
    }

    @Test("should send request body")
    func testSendRequestBody() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        #expect((json["prompt"] as? String)?.contains("assistant:") == true)
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        } else {
            Issue.record("Missing stop sequences")
        }
    }

    @Test("should send additional response information")
    func testSendAdditionalResponseInfo() async throws {
        let responseJSON: [String: Any] = [
            "id": "test-id",
            "object": "text_completion",
            "created": 123,
            "model": "test-model",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        if let response = result.response {
            #expect(response.id == "test-id")
            #expect(response.modelId == "test-model")
            #expect(response.timestamp == Date(timeIntervalSince1970: 123))
        } else {
            Issue.record("Missing response metadata")
        }
    }

    @Test("should extract logprobs")
    func testExtractLogprobs() async throws {
        let logprobsValue = makeLogprobsValue()

        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "logprobs": try logprobsValue.asJSONObject(),
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                providerOptions: ["openai": ["logprobs": .number(1)]]
            )
        )

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["logprobs"] == logprobsValue)
        } else {
            Issue.record("Missing provider metadata")
        }
    }

    @Test("should extract finish reason")
    func testExtractFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
    }

    @Test("should support unknown finish reason")
    func testSupportUnknownFinishReason() async throws {
        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "eos"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        #expect(result.finishReason.unified == .other)
        #expect(result.finishReason.raw == "eos")
    }

    @Test("should expose the raw response headers")
    func testExposeRawResponseHeaders() async throws {
        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "test-header": "test-value"
            ]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        if let headers = result.response?.headers {
            let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            #expect(normalizedHeaders["content-type"] == "application/json")
            #expect(normalizedHeaders["test-header"] == "test-value")
        } else {
            Issue.record("Missing response headers")
        }
    }

    @Test("should pass the model and the prompt")
    func testPassModelAndPrompt() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(prompt: completionPrompt)
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        } else {
            Issue.record("Missing stop sequences")
        }
    }

    @Test("should pass headers")
    func testPassHeaders() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cmpl-test",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "",
                "index": 0,
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 30,
                "total_tokens": 34
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.completion",
            url: { _ in "https://api.openai.com/v1/completions" },
            headers: {
                [
                    "Authorization": "Bearer test-api-key",
                    "OpenAI-Organization": "test-organization",
                    "OpenAI-Project": "test-project",
                    "Custom-Provider-Header": "provider-header-value"
                ]
            },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_711_363_706) })
        )

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: config
        )

        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })

        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["content-type"] == "application/json")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
        #expect(normalizedHeaders["openai-organization"] == "test-organization")
        #expect(normalizedHeaders["openai-project"] == "test-project")
    }

    @Test("doGenerate maps response, usage and request headers")
    func testDoGenerateMapsResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let logprobsValue = makeLogprobsValue()

        let responseJSON: [String: Any] = [
            "id": "cmpl-123",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": "Hello, World!",
                "index": 0,
                "logprobs": try logprobsValue.asJSONObject(),
                "finish_reason": "stop"
            ]],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10
            ]
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "application/json",
                "X-Test-Header": "response-value"
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let options = LanguageModelV3CallOptions(
            prompt: completionPrompt,
            headers: ["Custom-Request": "request-value"],
            providerOptions: [
                "openai": ["logprobs": .number(1)]
            ]
        )

        let result = try await model.doGenerate(options: options)

        #expect(result.content.count == 1)
        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        #expect(result.usage.inputTokens.total == 4)
        #expect(result.usage.outputTokens.total == 6)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 10)

        if let metadata = result.providerMetadata?["openai"] {
            #expect(metadata["logprobs"] == logprobsValue)
        } else {
            Issue.record("Missing provider metadata")
        }

        if let response = result.response {
            #expect(response.id == "cmpl-123")
            #expect(response.modelId == "gpt-3.5-turbo-instruct")
            #expect(response.timestamp == Date(timeIntervalSince1970: 1_711_363_706))
        } else {
            Issue.record("Missing response metadata")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["custom-request"] == "request-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        } else {
            Issue.record("Missing stop sequences")
        }
    }

    // MARK: - doStream Tests

    @Test("should stream text deltas")
    func testStreamTextDeltas() async throws {
        let logprobsValue = makeLogprobsValue()

        func chunk(_ dictionary: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "Unable to encode chunk")
            }
            return "data: \(string)\n\n"
        }

        let chunks: [String] = [
            try chunk([
                "id": "cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT",
                "object": "text_completion",
                "created": 1_711_363_440,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": "Hello",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": NSNull()
                ]]
            ]),
            try chunk([
                "id": "cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT",
                "object": "text_completion",
                "created": 1_711_363_440,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": ", ",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": NSNull()
                ]]
            ]),
            try chunk([
                "id": "cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT",
                "object": "text_completion",
                "created": 1_711_363_440,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": "World!",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": NSNull()
                ]]
            ]),
            try chunk([
                "id": "cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H",
                "object": "text_completion",
                "created": 1_711_363_310,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": "",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": "stop"
                ]]
            ]),
            try chunk([
                "id": "cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H",
                "object": "text_completion",
                "created": 1_711_363_310,
                "model": "gpt-3.5-turbo-instruct",
                "usage": [
                    "prompt_tokens": 10,
                    "completion_tokens": 362,
                    "total_tokens": 372
                ],
                "choices": []
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count >= 7)

        // stream-start
        if case .streamStart(let warnings) = parts[0] {
            #expect(warnings.isEmpty)
        } else {
            Issue.record("Expected stream-start")
        }

        // response-metadata
        if case .responseMetadata(let id, let modelId, let timestamp) = parts[1] {
            #expect(id == "cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT")
            #expect(modelId == "gpt-3.5-turbo-instruct")
            #expect(timestamp == Date(timeIntervalSince1970: 1_711_363_440))
        } else {
            Issue.record("Expected response-metadata")
        }

        // Verify text deltas
        var textDeltas: [String] = []
        for part in parts {
            if case let .textDelta(_, delta, _) = part {
                textDeltas.append(delta)
            }
        }
        #expect(textDeltas == ["Hello", ", ", "World!"])

        // finish with usage and metadata
        if let last = parts.last {
            if case .finish(let finishReason, let usage, let metadata) = last {
                #expect(finishReason.unified == .stop)
                #expect(finishReason.raw == "stop")
                #expect(usage.inputTokens.total == 10)
                #expect(usage.outputTokens.total == 362)
                #expect((usage.inputTokens.total ?? 0) + (usage.outputTokens.total ?? 0) == 372)
                if let openaiMetadata = metadata?["openai"] {
                    #expect(openaiMetadata["logprobs"] == logprobsValue)
                }
            } else {
                Issue.record("Expected finish part")
            }
        }
    }

    @Test("should send request body for stream")
    func testSendRequestBodyForStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let chunks = ["data: [DONE]\n\n"]
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        #expect((json["prompt"] as? String)?.contains("assistant:") == true)
        #expect(json["stream"] as? Bool == true)
        if let streamOptions = json["stream_options"] as? [String: Any] {
            #expect(streamOptions["include_usage"] as? Bool == true)
        }
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        }
    }

    @Test("should expose the raw response headers for stream")
    func testExposeRawResponseHeadersForStream() async throws {
        let chunks = ["data: [DONE]\n\n"]
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "test-header": "test-value"
            ]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        if let headers = result.response?.headers {
            let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
            #expect(normalizedHeaders["content-type"] == "text/event-stream")
            #expect(normalizedHeaders["test-header"] == "test-value")
        } else {
            Issue.record("Missing response headers")
        }
    }

    @Test("should pass the model and the prompt for stream")
    func testPassModelAndPromptForStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let chunks = ["data: [DONE]\n\n"]
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        if let stop = json["stop"] as? [String] {
            #expect(stop.contains("\nuser:"))
        }
        #expect(json["stream"] as? Bool == true)
        if let streamOptions = json["stream_options"] as? [String: Any] {
            #expect(streamOptions["include_usage"] as? Bool == true)
        }
    }

    @Test("should pass headers for stream")
    func testPassHeadersForStream() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let chunks = ["data: [DONE]\n\n"]
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let config = OpenAIConfig(
            provider: "openai.completion",
            url: { _ in "https://api.openai.com/v1/completions" },
            headers: {
                [
                    "Authorization": "Bearer test-api-key",
                    "OpenAI-Organization": "test-organization",
                    "OpenAI-Project": "test-project",
                    "Custom-Provider-Header": "provider-header-value"
                ]
            },
            fetch: fetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 1_711_363_706) })
        )

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: config
        )

        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })

        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["content-type"] == "application/json")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
        #expect(normalizedHeaders["openai-organization"] == "test-organization")
        #expect(normalizedHeaders["openai-project"] == "test-project")
    }

    @Test("should handle unparsable stream parts")
    func testHandleUnparsableStreamParts() async throws {
        let chunks = [
            "data: {unparsable}\n\n",
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count == 3)
        if parts.count == 3 {
            if case .streamStart = parts[0] {
                // expected
            } else {
                Issue.record("Expected stream-start")
            }

            if case .error = parts[1] {
                // Error can be either string or object containing JSONParseError
                // Just verify it's an error - test passes if we got here
            } else {
                Issue.record("Expected error part")
            }

            if case .finish(let finishReason, _, _) = parts[2] {
                #expect(finishReason == .error)
            } else {
                Issue.record("Expected finish part")
            }
        }
    }

    @Test("doStream emits deltas, usage and provider metadata")
    func testDoStreamEmitsDeltas() async throws {
        actor RequestBodyCapture {
            var data: Data?
            func store(_ body: Data?) { data = body }
            func current() -> Data? { data }
        }

        let capture = RequestBodyCapture()
        let logprobsValue = makeLogprobsValue()

        func chunk(_ dictionary: [String: Any]) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: dictionary)
            guard let string = String(data: data, encoding: .utf8) else {
                throw UnsupportedFunctionalityError(functionality: "Unable to encode chunk")
            }
            return "data: \(string)\n\n"
        }

        let chunks: [String] = [
            try chunk([
                "id": "cmpl-chunk-1",
                "object": "text_completion",
                "created": 1_711_363_706,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": "Hello",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": NSNull()
                ]]
            ]),
            try chunk([
                "id": "cmpl-final",
                "object": "text_completion",
                "created": 1_711_363_708,
                "model": "gpt-3.5-turbo-instruct",
                "choices": [[
                    "text": " World!",
                    "index": 0,
                    "logprobs": try logprobsValue.asJSONObject(),
                    "finish_reason": "stop"
                ]]
            ]),
            try chunk([
                "id": "cmpl-final",
                "object": "text_completion",
                "created": 1_711_363_708,
                "model": "gpt-3.5-turbo-instruct",
                "usage": [
                    "prompt_tokens": 5,
                    "completion_tokens": 7,
                    "total_tokens": 12
                ],
                "choices": []
            ]),
            "data: [DONE]\n\n"
        ]

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": "text/event-stream",
                "Cache-Control": "no-cache"
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request.httpBody)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                for entry in chunks {
                    continuation.yield(Data(entry.utf8))
                }
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false,
                providerOptions: [
                    "openai": ["logprobs": .bool(true)]
                ]
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count >= 6)
        if parts.count >= 1 {
            if case .streamStart(let warnings) = parts[0] {
                #expect(warnings.isEmpty)
            } else {
                Issue.record("Expected stream-start part")
            }
        }

        if parts.count >= 2 {
            if case .responseMetadata(let id, let modelId, let timestamp) = parts[1] {
                #expect(id == "cmpl-chunk-1")
                #expect(modelId == "gpt-3.5-turbo-instruct")
                #expect(timestamp == Date(timeIntervalSince1970: 1_711_363_706))
            } else {
                Issue.record("Expected response-metadata part")
            }
        }

        if let last = parts.last {
            if case .finish(let finishReason, let usage, let metadata) = last {
                #expect(finishReason.unified == .stop)
                #expect(finishReason.raw == "stop")
                #expect(usage.inputTokens.total == 5)
                #expect(usage.outputTokens.total == 7)
                #expect((usage.inputTokens.total ?? 0) + (usage.outputTokens.total ?? 0) == 12)
                if let openaiMetadata = metadata?["openai"] {
                    #expect(openaiMetadata["logprobs"] == logprobsValue)
                } else {
                    Issue.record("Missing provider metadata in finish")
                }
            } else {
                Issue.record("Expected finish part")
            }
        }

        guard let body = await capture.current(),
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing captured stream request")
            return
        }

        #expect(json["stream"] as? Bool == true)
        if let streamOptions = json["stream_options"] as? [String: Any] {
            #expect(streamOptions["include_usage"] as? Bool == true)
        } else {
            Issue.record("Missing stream_options")
        }
    }

    @Test("doStream handles error chunks")
    func testDoStreamHandlesErrorChunk() async throws {
        let errorChunk: String = {
            let value: [String: Any] = [
                "error": [
                    "message": "Server error",
                    "type": "server_error",
                    "param": NSNull(),
                    "code": NSNull()
                ]
            ]
            let data = try! JSONSerialization.data(withJSONObject: value)
            return "data: \(String(data: data, encoding: .utf8)!)\n\n"
        }()

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.openai.com/v1/completions")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                continuation.yield(Data(errorChunk.utf8))
                continuation.yield(Data("data: [DONE]\n\n".utf8))
                continuation.finish()
            }
            return FetchResponse(body: .stream(stream), urlResponse: httpResponse)
        }

        let model = OpenAICompletionLanguageModel(
            modelId: "gpt-3.5-turbo-instruct",
            config: makeConfig(fetch: fetch)
        )

        let result = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: completionPrompt,
                includeRawChunks: false
            )
        )

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.count == 3)
        if parts.count == 3 {
            if case .streamStart = parts[0] {
                // expected
            } else {
                Issue.record("Expected stream-start")
            }

            if case .error(let errorValue) = parts[1] {
                switch errorValue {
                case .object(let obj):
                    if case .object(let nested)? = obj["error"] {
                        #expect(nested["type"] == .string("server_error"))
                    } else {
                        Issue.record("Unexpected error structure")
                    }
                case .string(let message):
                    #expect(message.contains("Server error"))
                default:
                    Issue.record("Unexpected error payload")
                }
            } else {
                Issue.record("Expected error part")
            }

            if case .finish(let finishReason, _, _) = parts[2] {
                #expect(finishReason == .error)
            } else {
                Issue.record("Expected finish part")
            }
        }
    }
}

private extension JSONValue {
    func asJSONObject() throws -> Any {
        switch self {
        case .null:
            return NSNull()
        case .bool(let value):
            return value
        case .number(let value):
            return value
        case .string(let value):
            return value
        case .array(let array):
            return try array.map { try $0.asJSONObject() }
        case .object(let object):
            return try object.mapValues { try $0.asJSONObject() }
        }
    }
}
