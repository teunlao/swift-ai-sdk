import Foundation
import Testing
@testable import OpenAICompatibleProvider
import AISDKProvider
import AISDKProviderUtils

private let parityTestPrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello"))], providerOptions: nil)
]

private actor RequestCapture {
    private var request: URLRequest?
    func store(_ request: URLRequest) { self.request = request }
    func current() -> URLRequest? { request }
}

private func makeHTTPResponse(url: URL, contentType: String = "application/json") -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: 200,
        httpVersion: "HTTP/1.1",
        headerFields: ["Content-Type": contentType]
    )!
}

private func makeMinimalChatResponseData(usage: [String: Any]) throws -> Data {
    let response: [String: Any] = [
        "id": "chatcmpl-test",
        "created": 1_700_000_000,
        "model": "grok-beta",
        "choices": [[
            "message": ["content": "Hi"],
            "finish_reason": "stop"
        ]],
        "usage": usage
    ]
    return try JSONSerialization.data(withJSONObject: response)
}

@Suite("OpenAICompatible chat providerOptions parity", .serialized)
struct OpenAICompatibleChatProviderOptionsParityTests {
    @Test("supports openaiCompatible key without deprecation warning")
    func supportsOpenAICompatibleKeyWithoutWarning() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!
        let responseData = try makeMinimalChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: .init(rawValue: "grok-beta"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in url.absoluteString },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: parityTestPrompt,
            providerOptions: [
                "openaiCompatible": ["user": .string("user-from-openaiCompatible")]
            ]
        ))

        #expect(result.warnings.contains(where: { warning in
            if case .other(let message) = warning {
                return message.contains("openai-compatible") && message.contains("deprecated")
            }
            return false
        }) == false)

        let captured = await capture.current()
        let bodyData = try #require(captured?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["user"] == .string("user-from-openaiCompatible"))
    }

    @Test("deprecated openai-compatible key emits warning")
    func deprecatedKeyEmitsWarning() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!
        let responseData = try makeMinimalChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: .init(rawValue: "grok-beta"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in url.absoluteString },
                fetch: fetch
            )
        )

        let result = try await model.doGenerate(options: .init(
            prompt: parityTestPrompt,
            providerOptions: [
                "openai-compatible": ["user": .string("user-from-deprecated-key")]
            ]
        ))

        #expect(result.warnings.contains(.other(
            message: "The 'openai-compatible' key in providerOptions is deprecated. Use 'openaiCompatible' instead."
        )) == true)

        let captured = await capture.current()
        let bodyData = try #require(captured?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)
        #expect(body["user"] == .string("user-from-deprecated-key"))
    }

    @Test("strictJsonSchema is forwarded into response_format.json_schema.strict")
    func strictJsonSchemaIsForwarded() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!
        let responseData = try makeMinimalChatResponseData(usage: [
            "prompt_tokens": 1,
            "completion_tokens": 1,
            "total_tokens": 2,
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let model = OpenAICompatibleChatLanguageModel(
            modelId: .init(rawValue: "grok-beta"),
            config: OpenAICompatibleChatConfig(
                provider: "test-provider",
                headers: { [:] },
                url: { _ in url.absoluteString },
                fetch: fetch,
                supportsStructuredOutputs: true
            )
        )

        let schema: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(["value": .object(["type": .string("string")])]),
            "required": .array([.string("value")]),
            "additionalProperties": .bool(false),
        ]

        _ = try await model.doGenerate(options: .init(
            prompt: parityTestPrompt,
            responseFormat: .json(schema: .object(schema), name: nil, description: nil),
            providerOptions: [
                "openaiCompatible": ["strictJsonSchema": .bool(false)]
            ]
        ))

        let captured = await capture.current()
        let bodyData = try #require(captured?.httpBody)
        let body = try JSONDecoder().decode([String: JSONValue].self, from: bodyData)

        guard case .object(let responseFormat)? = body["response_format"] else {
            Issue.record("Expected response_format object")
            return
        }
        #expect(responseFormat["type"] == .string("json_schema"))

        guard case .object(let jsonSchema)? = responseFormat["json_schema"] else {
            Issue.record("Expected json_schema object")
            return
        }
        #expect(jsonSchema["strict"] == .bool(false))
        #expect(body["strictJsonSchema"] == nil)
    }

    @Test("usage.raw preserves unknown usage keys in non-streaming")
    func usageRawPreservesUnknownKeysNonStreaming() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!
        let responseData = try makeMinimalChatResponseData(usage: [
            "prompt_tokens": 20,
            "completion_tokens": 30,
            "total_tokens": 50,
            "cached_tokens": 7,
            "prompt_tokens_details": ["cached_tokens": 5],
            "completion_tokens_details": ["reasoning_tokens": 10],
        ])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: makeHTTPResponse(url: url))
        }

        let provider = createOpenAICompatibleProvider(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        let result = try await model.doGenerate(options: .init(prompt: parityTestPrompt))

        #expect(result.usage.inputTokens.cacheRead == 5) // still derived from prompt_tokens_details
        guard let raw = result.usage.raw, case .object(let dict) = raw else {
            Issue.record("Expected usage.raw object")
            return
        }
        #expect(dict["cached_tokens"] == .number(7))
    }

    @Test("usage.raw preserves unknown usage keys in streaming finish part")
    func usageRawPreservesUnknownKeysStreaming() async throws {
        let capture = RequestCapture()
        let url = URL(string: "https://api.example.com/v1/chat/completions")!

        let sse = """
        data: {\"id\":\"chatcmpl-1\",\"created\":1712000000,\"model\":\"grok-beta\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}

        data: {\"id\":\"chatcmpl-1\",\"created\":1712000000,\"model\":\"grok-beta\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":20,\"completion_tokens\":30,\"total_tokens\":50,\"cached_tokens\":7,\"prompt_tokens_details\":{\"cached_tokens\":5},\"completion_tokens_details\":{\"reasoning_tokens\":10}}}

        data: [DONE]

        """
        let data = Data(sse.utf8)

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: makeHTTPResponse(url: url, contentType: "text/event-stream"))
        }

        let provider = createOpenAICompatibleProvider(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "test-provider",
            headers: ["Authorization": "Bearer test-api-key"],
            fetch: fetch,
            includeUsage: true
        ))

        let model = try provider.chatModel(modelId: "grok-beta")
        let streamResult = try await model.doStream(options: .init(prompt: parityTestPrompt))

        var finish: (LanguageModelV3FinishReason, LanguageModelV3Usage)?
        for try await part in streamResult.stream {
            if case let .finish(finishReason: finishReason, usage: usage, providerMetadata: _) = part {
                finish = (finishReason, usage)
            }
        }

        guard let finish else {
            Issue.record("Missing finish part")
            return
        }

        #expect(finish.0.unified == .stop)
        #expect(finish.1.inputTokens.cacheRead == 5)
        guard let raw = finish.1.raw, case .object(let dict) = raw else {
            Issue.record("Expected usage.raw object in finish")
            return
        }
        #expect(dict["cached_tokens"] == .number(7))
    }
}

