import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

@Suite("OpenAICompatibleCompletionLanguageModelV4")
struct OpenAICompatibleCompletionLanguageModelV4Tests {
    private let prompt: LanguageModelV4Prompt = [
        .user(
            content: [.text(LanguageModelV4TextPart(text: "Hello"))],
            providerOptions: nil
        )
    ]

    actor RequestCapture {
        private var request: URLRequest?

        func store(_ request: URLRequest) {
            self.request = request
        }

        func current() -> URLRequest? {
            request
        }
    }

    private func makeHTTPResponse(
        url: URL,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func makeCompletionResponse(
        text: String = "Hello from V4",
        finishReason: String = "stop",
        usage: [String: Int] = [
            "prompt_tokens": 20,
            "completion_tokens": 5,
            "total_tokens": 25
        ]
    ) -> [String: Any] {
        [
            "id": "cmpl-v4",
            "object": "text_completion",
            "created": 1_711_363_706,
            "model": "gpt-3.5-turbo-instruct",
            "choices": [[
                "text": text,
                "index": 0,
                "finish_reason": finishReason
            ]],
            "usage": usage
        ]
    }

    private func makeStreamBody(from events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data("data: \(event)\n\n".utf8))
            }
            continuation.yield(Data("data: [DONE]\n\n".utf8))
            continuation.finish()
        })
    }

    @Test("generate uses V4 provider option precedence and warnings")
    func generateUsesV4ProviderOptionPrecedenceAndWarnings() async throws {
        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeCompletionResponse())
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "application/json", "X-Response": "ok"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            maxOutputTokens: 16,
            topK: 10,
            responseFormat: .json(schema: nil, name: nil, description: nil),
            tools: [
                .function(.init(
                    name: "lookup",
                    inputSchema: .object(["type": .string("object")])
                ))
            ],
            toolChoice: .auto,
            providerOptions: [
                "test-provider": [
                    "someCustomOption": .string("raw-value"),
                    "user": .string("raw-user"),
                    "model": .string("raw-model"),
                    "prompt": .string("raw-prompt"),
                    "stop": .array([.string("raw-stop")]),
                    "max_tokens": .number(32)
                ],
                "testProvider": [
                    "someCustomOption": .string("camel-value"),
                    "user": .string("camel-user"),
                    "model": .string("camel-model"),
                    "prompt": .string("camel-prompt"),
                    "stop": .array([.string("camel-stop")]),
                    "max_tokens": .number(64)
                ]
            ]
        ))

        #expect(result.warnings == [
            .deprecated(
                setting: "providerOptions key 'test-provider'",
                message: "Use 'testProvider' instead."
            ),
            .unsupported(feature: "topK", details: nil),
            .unsupported(feature: "tools", details: nil),
            .unsupported(feature: "toolChoice", details: nil),
            .unsupported(
                feature: "responseFormat",
                details: "JSON response format is not supported."
            )
        ])
        #expect(result.content == [
            .text(LanguageModelV4Text(text: "Hello from V4"))
        ])
        #expect(result.finishReason == .init(unified: .stop, raw: "stop"))
        #expect(result.usage == LanguageModelV4Usage(
            inputTokens: .init(total: 20, noCache: 20),
            outputTokens: .init(total: 5, text: 5),
            raw: .object([
                "prompt_tokens": .number(20),
                "completion_tokens": .number(5),
                "total_tokens": .number(25)
            ])
        ))
        #expect(result.response?.headers?["x-response"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured V4 completion request")
            return
        }

        #expect(json["someCustomOption"] as? String == "camel-value")
        #expect(json["user"] as? String == "camel-user")
        #expect(json["model"] as? String == "camel-model")
        #expect((json["max_tokens"] as? NSNumber)?.intValue == 64)
        #expect(json["prompt"] as? String == "user:\nHello\n\nassistant:\n")
        #expect(json["stop"] as? [String] == ["\nuser:"])
    }

    @Test("camel-case provider options and empty tools do not warn")
    func camelCaseProviderOptionsAndEmptyToolsDoNotWarn() async throws {
        let capture = RequestCapture()
        let responseData = try JSONSerialization.data(withJSONObject: makeCompletionResponse())
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(
                body: .data(responseData),
                urlResponse: makeHTTPResponse(url: targetURL)
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")

        let result = try await model.doGenerate(options: .init(
            prompt: prompt,
            tools: [],
            providerOptions: [
                "testProvider": ["someCustomOption": .string("camel-value")]
            ]
        ))

        #expect(result.warnings.isEmpty)
        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing camel-case provider options request")
            return
        }
        #expect(json["someCustomOption"] as? String == "camel-value")
    }

    @Test("generate rejects responses that violate the upstream completion schema")
    func generateRejectsMalformedCompletionResponses() async throws {
        let malformedResponses: [(label: String, response: [String: Any])] = [
            (
                "missing text",
                [
                    "choices": [["finish_reason": "stop"]]
                ]
            ),
            (
                "missing finish reason",
                [
                    "choices": [["text": "response"]]
                ]
            ),
            (
                "partial usage",
                [
                    "choices": [["text": "response", "finish_reason": "stop"]],
                    "usage": ["prompt_tokens": 1]
                ]
            )
        ]
        let targetURL = URL(string: "https://my.api.com/v1/completions")!

        for malformed in malformedResponses {
            let responseData = try JSONSerialization.data(withJSONObject: malformed.response)
            let fetch: FetchFunction = { _ in
                FetchResponse(
                    body: .data(responseData),
                    urlResponse: makeHTTPResponse(url: targetURL)
                )
            }
            let provider = createOpenAICompatible(settings: .init(
                baseURL: "https://my.api.com/v1",
                name: "test-provider",
                fetch: fetch
            ))
            let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")

            do {
                _ = try await model.doGenerate(options: .init(prompt: prompt))
                Issue.record("Expected validation failure for \(malformed.label)")
            } catch let error as APICallError {
                #expect(error.message == "Invalid JSON response")
                _ = try #require(error.cause as? TypeValidationError)
            } catch {
                Issue.record("Expected APICallError for \(malformed.label), got \(error)")
            }
        }
    }

    @Test("stream rejects malformed chunks and continues with subsequent valid data")
    func streamRejectsMalformedCompletionChunks() async throws {
        let events = [
            #"{"id":"cmpl-v4","choices":[{"text":"missing index","finish_reason":null}]}"#,
            #"{"id":"cmpl-v4","choices":[{"index":0,"finish_reason":null}]}"#,
            #"{"id":"cmpl-v4","choices":[],"usage":{"prompt_tokens":1}}"#,
            #"{"id":"cmpl-v4","choices":[{"text":"valid","index":0,"finish_reason":"stop"}],"error":{"message":"ignored extra field"}}"#
        ]
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(from: events),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "text/event-stream"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.filter {
            if case .error = $0 { return true }
            return false
        }.count == 3)
        let textDeltas = parts.compactMap { part -> String? in
            if case let .textDelta(_, delta, _) = part { return delta }
            return nil
        }
        #expect(textDeltas == ["valid"])
        guard case let .finish(finishReason, usage, _) = parts.last else {
            Issue.record("Expected finish after the valid trailing chunk")
            return
        }
        #expect(finishReason == .init(unified: .stop, raw: "stop"))
        #expect(usage == LanguageModelV4Usage())
    }

    @Test("stream emits the native V4 text lifecycle and usage")
    func streamEmitsNativeV4TextLifecycleAndUsage() async throws {
        let events = [
            #"{"id":"cmpl-v4","created":1711363440,"model":"gpt-3.5-turbo-instruct","choices":[{"text":"Hello","index":0,"finish_reason":null}]}"#,
            #"{"id":"cmpl-v4","created":1711363440,"model":"gpt-3.5-turbo-instruct","choices":[{"text":", World!","index":0,"finish_reason":null}]}"#,
            #"{"id":"cmpl-v4","created":1711363440,"model":"gpt-3.5-turbo-instruct","choices":[{"text":"","index":0,"finish_reason":"stop"}]}"#,
            #"{"id":"cmpl-v4","created":1711363440,"model":"gpt-3.5-turbo-instruct","usage":{"prompt_tokens":10,"completion_tokens":362,"total_tokens":372},"choices":[]}"#
        ]
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(from: events),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "text/event-stream"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch,
            includeUsage: true
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts == [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "cmpl-v4",
                modelId: "gpt-3.5-turbo-instruct",
                timestamp: Date(timeIntervalSince1970: 1_711_363_440)
            ),
            .textStart(id: "0", providerMetadata: nil),
            .textDelta(id: "0", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "0", delta: ", World!", providerMetadata: nil),
            .textDelta(id: "0", delta: "", providerMetadata: nil),
            .textEnd(id: "0", providerMetadata: nil),
            .finish(
                finishReason: .init(unified: .stop, raw: "stop"),
                usage: LanguageModelV4Usage(
                    inputTokens: .init(total: 10, noCache: 10),
                    outputTokens: .init(total: 362, text: 362),
                    raw: .object([
                        "prompt_tokens": .number(10),
                        "completion_tokens": .number(362),
                        "total_tokens": .number(372)
                    ])
                ),
                providerMetadata: nil
            )
        ])

        guard let requestBody = result.request?.body as? [String: JSONValue] else {
            Issue.record("Missing V4 stream request body")
            return
        }
        #expect(requestBody["stream"] == .bool(true))
        #expect(requestBody["stream_options"] == .object(["include_usage": .bool(true)]))
    }

    @Test("stream preserves raw chunks and the inner provider error")
    func streamPreservesRawChunksAndInnerProviderError() async throws {
        let errorEvent = #"{"error":{"message":"Test error","type":"server_error","param":null,"code":null}}"#
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(from: [errorEvent]),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "text/event-stream"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doStream(options: .init(
            prompt: prompt,
            includeRawChunks: true
        ))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.first == .streamStart(warnings: []))
        #expect(parts.dropFirst().first == .raw(rawValue: .object([
            "error": .object([
                "message": .string("Test error"),
                "type": .string("server_error"),
                "param": .null,
                "code": .null
            ])
        ])))
        #expect(parts.dropFirst(2).first == .error(error: .object([
            "message": .string("Test error"),
            "type": .string("server_error"),
            "param": .null,
            "code": .null
        ])))

        guard case let .finish(finishReason, usage, providerMetadata) = parts.last else {
            Issue.record("Missing V4 error finish")
            return
        }
        #expect(finishReason == .init(unified: .error, raw: nil))
        #expect(usage == LanguageModelV4Usage())
        #expect(providerMetadata == nil)
    }

    @Test("unparsable stream chunks produce an error finish")
    func unparsableStreamChunksProduceErrorFinish() async throws {
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(
                body: makeStreamBody(from: ["{unparsable}"]),
                urlResponse: makeHTTPResponse(
                    url: targetURL,
                    headers: ["Content-Type": "text/event-stream"]
                )
            )
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://my.api.com/v1",
            name: "test-provider",
            fetch: fetch
        ))
        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doStream(options: .init(prompt: prompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        #expect(parts.contains { part in
            if case .error = part { return true }
            return false
        })
        guard case let .finish(finishReason, usage, _) = parts.last else {
            Issue.record("Missing finish after an unparsable chunk")
            return
        }
        #expect(finishReason == .init(unified: .error, raw: nil))
        #expect(usage == LanguageModelV4Usage())
    }

    @Test("direct V4 completion model exposes configured supported URLs")
    func directV4CompletionModelExposesSupportedUrls() async throws {
        let pattern = try NSRegularExpression(pattern: #"^https://files\.example/"#)
        let model = OpenAICompatibleCompletionLanguageModelV4(
            modelId: .init(rawValue: "gpt-3.5-turbo-instruct"),
            config: .init(
                provider: "test-provider.completion",
                headers: { [:] },
                url: { _ in "https://my.api.com/v1/completions" },
                supportedUrls: { ["text/*": [pattern]] }
            )
        )

        let supportedUrls = try await model.supportedUrls

        #expect(supportedUrls["text/*"]?.first?.pattern == #"^https://files\.example/"#)
    }
}
