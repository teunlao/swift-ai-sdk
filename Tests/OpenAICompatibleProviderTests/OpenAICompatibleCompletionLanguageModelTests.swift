import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

/**
 Tests for OpenAICompatibleCompletionLanguageModel.

 Port of `@ai-sdk/openai-compatible/src/completion/openai-compatible-completion-language-model.test.ts`.
 */

@Suite("OpenAICompatibleCompletionLanguageModel")
struct OpenAICompatibleCompletionLanguageModelTests {
    private let testPrompt: LanguageModelV3Prompt = [
        .user(content: [.text(LanguageModelV3TextPart(text: "Hello"))], providerOptions: nil)
    ]

    // MARK: - Config Tests

    @Test("should extract base name from provider string")
    func extractBaseNameFromProviderString() throws {
        let model = OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleCompletionConfig(
                provider: "anthropic.beta",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        // Access private property for testing
        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "anthropic")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    @Test("should handle provider without dot notation")
    func handleProviderWithoutDotNotation() throws {
        let model = OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleCompletionConfig(
                provider: "openai",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "openai")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    @Test("should return empty for empty provider")
    func returnEmptyForEmptyProvider() throws {
        let model = OpenAICompatibleCompletionLanguageModel(
            modelId: OpenAICompatibleCompletionModelId(rawValue: "gpt-4"),
            config: OpenAICompatibleCompletionConfig(
                provider: "",
                headers: { [:] },
                url: { _ in "" }
            )
        )

        let mirror = Mirror(reflecting: model)
        if let providerOptionsName = mirror.children.first(where: { $0.label == "providerOptionsName" })?.value as? String {
            #expect(providerOptionsName == "")
        } else {
            Issue.record("Could not access providerOptionsName")
        }
    }

    // MARK: - doGenerate Tests

    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func makeHTTPResponse(url: URL, statusCode: Int = 200, headers: [String: String] = [:]) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeCompletionResponse(
        id: String = "cmpl-96cAM1v77r4jXa4qb2NSmRREV5oWB",
        created: Double = 1711363706,
        model: String = "gpt-3.5-turbo-instruct",
        text: String = "",
        finishReason: String = "stop",
        usage: [String: Int] = ["prompt_tokens": 4, "total_tokens": 34, "completion_tokens": 30]
    ) -> [String: Any] {
        return [
            "id": id,
            "object": "text_completion",
            "created": created,
            "model": model,
            "choices": [
                [
                    "text": text,
                    "index": 0,
                    "finish_reason": finishReason
                ]
            ],
            "usage": usage
        ]
    }

    @Test("should extract text response")
    func extractTextResponse() async throws {
        let responseJSON = makeCompletionResponse(text: "Hello, World!")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.content.count == 1)
        if case .text(let textPart) = result.content.first {
            #expect(textPart.text == "Hello, World!")
        } else {
            Issue.record("Expected text content")
        }
    }

    @Test("should extract usage")
    func extractUsage() async throws {
        let responseJSON = makeCompletionResponse(
            usage: ["prompt_tokens": 20, "total_tokens": 25, "completion_tokens": 5]
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.usage.inputTokens.total == 20)
        #expect(result.usage.outputTokens.total == 5)
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 25)
    }

    @Test("should send request body")
    func sendRequestBody() async throws {
        let capture = RequestCapture()
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.request != nil)
        guard let requestBody = result.request?.body as? [String: JSONValue] else {
            Issue.record("Expected request body")
            return
        }

        #expect(requestBody["model"] == .string("gpt-3.5-turbo-instruct"))
        if case .string(let prompt) = requestBody["prompt"] {
            #expect(prompt.contains("Hello"))
        } else {
            Issue.record("Expected prompt string")
        }
    }

    @Test("should send additional response information")
    func sendAdditionalResponseInformation() async throws {
        let responseJSON = makeCompletionResponse(
            id: "test-id",
            created: 123,
            model: "test-model"
        )
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.response?.id == "test-id")
        #expect(result.response?.modelId == "test-model")
        #expect(result.response?.timestamp == Date(timeIntervalSince1970: 123))
    }

    @Test("should extract finish reason")
    func extractFinishReason() async throws {
        let responseJSON = makeCompletionResponse(finishReason: "stop")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
    }

    @Test("should support unknown finish reason")
    func supportUnknownFinishReason() async throws {
        let responseJSON = makeCompletionResponse(finishReason: "eos")
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.finishReason.unified == .other)
        #expect(result.finishReason.raw == "eos")
    }

    @Test("should expose the raw response headers")
    func exposeRawResponseHeaders() async throws {
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["test-header": "test-value"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let result = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(result.response?.headers?["test-header"] == "test-value")
    }

    @Test("should pass the model and the prompt")
    func passModelAndPrompt() async throws {
        let capture = RequestCapture()
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doGenerate(options: LanguageModelV3CallOptions(prompt: testPrompt))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        if let prompt = json["prompt"] as? String {
            #expect(prompt.contains("Hello"))
        } else {
            Issue.record("Expected prompt")
        }
    }

    @Test("should pass headers")
    func passHeaders() async throws {
        let capture = RequestCapture()
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: [
                "Authorization": "Bearer test-api-key",
                "Custom-Provider-Header": "provider-header-value"
            ],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(normalizedHeaders["authorization"] == "Bearer test-api-key")
        #expect(normalizedHeaders["custom-provider-header"] == "provider-header-value")
        #expect(normalizedHeaders["custom-request-header"] == "request-header-value")
    }

    @Test("should include provider-specific options")
    func includeProviderSpecificOptions() async throws {
        let capture = RequestCapture()
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] as? String == "test-value")
    }

    @Test("should not include provider-specific options for different provider")
    func notIncludeOptionsForDifferentProvider() async throws {
        let capture = RequestCapture()
        let responseJSON = makeCompletionResponse()
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doGenerate(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "notThisProviderName": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] == nil)
    }

    // MARK: - doStream Tests

    private func makeStreamBody(from events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                let payload = "data: \(event)\n\n"
                continuation.yield(Data(payload.utf8))
            }
            continuation.yield(Data("data: [DONE]\n\n".utf8))
            continuation.finish()
        })
    }

    @Test("should stream text deltas")
    func streamTextDeltas() async throws {
        let events = [
            "{\"id\":\"cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT\",\"object\":\"text_completion\",\"created\":1711363440,\"model\":\"gpt-3.5-turbo-instruct\",\"choices\":[{\"text\":\"Hello\",\"index\":0,\"finish_reason\":null}]}",
            "{\"id\":\"cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT\",\"object\":\"text_completion\",\"created\":1711363440,\"model\":\"gpt-3.5-turbo-instruct\",\"choices\":[{\"text\":\",\",\"index\":0,\"finish_reason\":null}]}",
            "{\"id\":\"cmpl-96c64EdfhOw8pjFFgVpLuT8k2MtdT\",\"object\":\"text_completion\",\"created\":1711363440,\"model\":\"gpt-3.5-turbo-instruct\",\"choices\":[{\"text\":\" World!\",\"index\":0,\"finish_reason\":null}]}",
            "{\"id\":\"cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H\",\"object\":\"text_completion\",\"created\":1711363310,\"model\":\"gpt-3.5-turbo-instruct\",\"choices\":[{\"text\":\"\",\"index\":0,\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-96c3yLQE1TtZCd6n6OILVmzev8M8H\",\"object\":\"text_completion\",\"created\":1711363310,\"model\":\"gpt-3.5-turbo-instruct\",\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":362,\"total_tokens\":372},\"choices\":[]}"
        ]

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        // Verify stream has text deltas
        let textDeltas = parts.compactMap { part -> String? in
            if case .textDelta(_, let delta, _) = part { return delta } else { return nil }
        }
        #expect(textDeltas.contains("Hello"))
        #expect(textDeltas.contains(","))
        #expect(textDeltas.contains(" World!"))

        // Verify finish
        if case let .finish(finishReason: finishReason, usage: usage, providerMetadata: _) = parts.last {
            #expect(finishReason.unified == .stop)
            #expect((usage.inputTokens.total ?? 0) + (usage.outputTokens.total ?? 0) == 372)
        } else {
            Issue.record("Missing finish part")
        }
    }

    @Test("should handle error stream parts")
    func handleErrorStreamParts() async throws {
        let events = [
            "{\"error\":{\"message\":\"Test error\",\"type\":\"invalid_request_error\",\"param\":null,\"code\":null}}"
        ]

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        var parts: [LanguageModelV3StreamPart] = []
        for try await part in streamResult.stream {
            parts.append(part)
        }

        // Verify error part exists
        let hasError = parts.contains { part in
            if case .error = part { return true } else { return false }
        }
        #expect(hasError)
    }

    @Test("should send request body (streaming)")
    func sendRequestBodyStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(streamResult.request != nil)
        guard let requestBody = streamResult.request?.body as? [String: JSONValue] else {
            Issue.record("Expected request body")
            return
        }

        #expect(requestBody["model"] == .string("gpt-3.5-turbo-instruct"))
        #expect(requestBody["stream"] == .bool(true))
        if case .string(let prompt) = requestBody["prompt"] {
            #expect(prompt.contains("Hello"))
        } else {
            Issue.record("Expected prompt string")
        }
    }

    @Test("should expose the raw response headers (streaming)")
    func exposeRawResponseHeadersStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "text/event-stream", "test-header": "test-value"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        let streamResult = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        #expect(streamResult.response?.headers?["test-header"] == "test-value")
        #expect(streamResult.response?.headers?["content-type"] == "text/event-stream")
    }

    @Test("should pass the model and the prompt (streaming)")
    func passModelAndPromptStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]
        let capture = RequestCapture()

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doStream(options: LanguageModelV3CallOptions(prompt: testPrompt))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "gpt-3.5-turbo-instruct")
        #expect((json["prompt"] as? String)?.contains("Hello") == true)
        #expect(json["stream"] as? Bool == true)
    }

    @Test("should pass headers (streaming)")
    func passHeadersStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]
        let capture = RequestCapture()

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: [
                "Authorization": "Bearer test-api-key",
                "Custom-Provider-Header": "provider-header-value"
            ],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                headers: ["Custom-Request-Header": "request-header-value"]
            )
        )

        guard let request = await capture.current() else {
            Issue.record("Missing captured request")
            return
        }

        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
        #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-header-value")
        #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-header-value")
    }

    @Test("should include provider-specific options (streaming)")
    func includeProviderSpecificOptionsStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]
        let capture = RequestCapture()

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "test-provider": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] as? String == "test-value")
    }

    @Test("should not include provider-specific options for different provider (streaming)")
    func notIncludeProviderSpecificOptionsForDifferentProviderStreaming() async throws {
        let events = [
            "{\"id\":\"cmpl-...\",\"choices\":[{\"text\":\"\",\"finish_reason\":\"stop\"}]}",
            "{\"id\":\"cmpl-...\",\"usage\":{\"total_tokens\":10},\"choices\":[]}"
        ]
        let capture = RequestCapture()

        let targetURL = URL(string: "https://my.api.com/v1/completions")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["Content-Type": "text/event-stream"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatibleProvider(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://my.api.com/v1/",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.completionModel(modelId: "gpt-3.5-turbo-instruct")
        _ = try await model.doStream(
            options: LanguageModelV3CallOptions(
                prompt: testPrompt,
                providerOptions: [
                    "notThisProviderName": ["someCustomOption": .string("test-value")]
                ]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["someCustomOption"] == nil)
    }
}
