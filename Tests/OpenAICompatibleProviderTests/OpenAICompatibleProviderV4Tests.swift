import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAICompatibleProvider

private let v4ChatPrompt: LanguageModelV4Prompt = [
    .user(
        content: [.text(LanguageModelV4TextPart(text: "Hello"))],
        providerOptions: nil
    )
]

@Suite("OpenAICompatibleProvider V4")
struct OpenAICompatibleProviderV4Tests {
    actor RequestCapture {
        private(set) var request: URLRequest?

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
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    private func makeStreamBody(from events: [String]) -> ProviderHTTPResponseBody {
        .stream(AsyncThrowingStream { continuation in
            for event in events {
                continuation.yield(Data("data: \(event)\n\n".utf8))
            }
            continuation.finish()
        })
    }

    @Test("factory exposes V4 provider and model surfaces")
    func factoryExposesV4Surfaces() throws {
        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example"
        ))

        #expect(provider.specificationVersion == "v4")

        let languageModel = try provider.languageModel(modelId: "gpt-oss")
        #expect(languageModel.specificationVersion == "v4")
        #expect(languageModel.provider == "example.chat")
        #expect(languageModel.modelId == "gpt-oss")

        let chatModel = try provider.chatModel(modelId: "gpt-oss")
        #expect(chatModel.specificationVersion == "v4")
        #expect(chatModel.provider == "example.chat")

        let completionModel = try provider.completionModel(modelId: "gpt-3.5-instruct")
        #expect(completionModel.specificationVersion == "v4")
        #expect(completionModel.provider == "example.completion")

        let embeddingModel = try provider.embeddingModel(modelId: "text-embedding-3-large")
        #expect(embeddingModel.specificationVersion == "v4")
        #expect(embeddingModel.provider == "example.embedding")

        let textEmbeddingModel = try provider.textEmbeddingModel(modelId: "text-embedding-3-small")
        #expect(textEmbeddingModel.specificationVersion == "v4")
        #expect(textEmbeddingModel.provider == "example.embedding")

        let imageModel = try provider.imageModel(modelId: "dall-e-3")
        #expect(imageModel.specificationVersion == "v4")
        #expect(imageModel.provider == "example.image")
        #expect(imageModel is OpenAICompatibleImageModelV4)
    }

    @Test("language model forwards supportedUrls")
    func languageModelSupportedUrls() async throws {
        let urlPattern = try NSRegularExpression(pattern: #"^https://files\.example/"#)
        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            supportedUrls: { ["image/*": [urlPattern]] }
        ))

        let model = try provider.languageModel(modelId: "gpt-oss")
        let supportedUrls = try await model.supportedUrls

        #expect(supportedUrls["image/*"]?.first?.pattern == #"^https://files\.example/"#)
    }

    @Test("language doGenerate forwards V4 options and maps V4 result")
    func languageDoGenerateUsesV4Surface() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-v4",
            "created": 1_712_000_000,
            "model": "gpt-oss",
            "choices": [
                [
                    "message": ["content": "Hello from V4"],
                    "finish_reason": "stop"
                ]
            ],
            "usage": [
                "prompt_tokens": 4,
                "completion_tokens": 6,
                "total_tokens": 10
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions?trace=1")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "application/json", "X-Response": "ok"]
        )

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1/",
            name: "example",
            apiKey: "secret",
            headers: ["Custom-Header": "provider"],
            queryParams: ["trace": "1"],
            fetch: fetch
        ))
        let model = try provider.languageModel(modelId: "gpt-oss")

        let result = try await model.doGenerate(options: LanguageModelV4CallOptions(
            prompt: v4ChatPrompt,
            temperature: 0.25,
            headers: ["Per-Request": "request"],
            providerOptions: [
                "openai-compatible": ["user": .string("base-user")],
                "example": ["user": .string("override-user")]
            ]
        ))

        #expect(result.finishReason.unified == .stop)
        #expect(result.finishReason.raw == "stop")
        #expect((result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0) == 10)
        #expect(result.response?.headers?["x-response"] == "ok")

        if case .text(let text) = result.content.first {
            #expect(text.text == "Hello from V4")
        } else {
            Issue.record("Expected V4 text content")
        }

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(request.url?.absoluteString == targetURL.absoluteString)
        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = headers.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        #expect(normalizedHeaders["authorization"] == "Bearer secret")
        #expect(normalizedHeaders["custom-header"] == "provider")
        #expect(normalizedHeaders["per-request"] == "request")
        #expect(json["model"] as? String == "gpt-oss")
        #expect(json["temperature"] as? Double == 0.25)
        #expect(json["user"] as? String == "override-user")
    }

    @Test("language doStream maps V4 text delta and finish")
    func languageDoStreamUsesV4Surface() async throws {
        let events = [
            "{\"id\":\"chatcmpl-v4\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{\"content\":\"Hello\"},\"finish_reason\":null}]}",
            "{\"id\":\"chatcmpl-v4\",\"created\":1712000000,\"model\":\"gpt-oss\",\"choices\":[{\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":1,\"completion_tokens\":1,\"total_tokens\":2}}"
        ]
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "text/event-stream"]
        )

        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch,
            includeUsage: true
        ))
        let model = try provider.languageModel(modelId: "gpt-oss")
        let result = try await model.doStream(options: LanguageModelV4CallOptions(prompt: v4ChatPrompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        if case .textDelta(_, let delta, _) = parts.first(where: { if case .textDelta = $0 { true } else { false } }) {
            #expect(delta == "Hello")
        } else {
            Issue.record("Missing V4 text delta")
        }

        if case let .finish(finishReason, usage, _) = parts.last {
            #expect(finishReason.unified == .stop)
            #expect((usage.inputTokens.total ?? 0) + (usage.outputTokens.total ?? 0) == 2)
        } else {
            Issue.record("Missing V4 finish")
        }
    }

    @Test("native V4 chat forwards reasoning tools and camel-case provider options")
    func nativeV4ChatForwardsV4RequestContracts() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "choices": [[
                "message": ["content": "done"],
                "finish_reason": "stop"
            ]]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "application/json"]
        )
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "example-provider",
            fetch: fetch
        ))
        let model = try provider.languageModel(modelId: "reasoning-model")

        #expect(model is OpenAICompatibleChatLanguageModelV4)

        let result = try await model.doGenerate(options: .init(
            prompt: v4ChatPrompt,
            tools: [
                .function(.init(
                    name: "lookup",
                    inputSchema: .object(["type": .string("object")]),
                    strict: true
                ))
            ],
            toolChoice: .tool(toolName: "lookup"),
            reasoning: .high,
            providerOptions: [
                "example-provider": [
                    "user": .string("raw-user"),
                    "routing": .string("raw")
                ],
                "exampleProvider": [
                    "user": .string("camel-user"),
                    "routing": .string("camel")
                ]
            ]
        ))

        #expect(result.warnings.contains(.deprecated(
            setting: "providerOptions key 'example-provider'",
            message: "Use 'exampleProvider' instead."
        )))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let tools = json["tools"] as? [[String: Any]],
              let tool = tools.first,
              let function = tool["function"] as? [String: Any],
              let toolChoice = json["tool_choice"] as? [String: Any],
              let selectedFunction = toolChoice["function"] as? [String: Any] else {
            Issue.record("Expected native V4 request body")
            return
        }

        #expect(json["reasoning_effort"] as? String == "high")
        #expect(json["user"] as? String == "camel-user")
        #expect(json["routing"] as? String == "camel")
        #expect(function["name"] as? String == "lookup")
        #expect(function["strict"] as? Bool == true)
        #expect(selectedFunction["name"] as? String == "lookup")
    }

    @Test("native V4 generate preserves reasoning thought signatures and custom usage")
    func nativeV4GeneratePreservesResponseContracts() async throws {
        let responseJSON: [String: Any] = [
            "id": "chatcmpl-native-v4",
            "created": 1_712_000_000,
            "model": "reasoning-model",
            "choices": [[
                "message": [
                    "content": "answer",
                    "reasoning": "fallback reasoning",
                    "tool_calls": [[
                        "id": "call-1",
                        "type": "function",
                        "function": [
                            "name": "lookup",
                            "arguments": #"{"id":1}"#
                        ],
                        "extra_content": [
                            "google": ["thought_signature": "signature-1"]
                        ]
                    ]]
                ],
                "finish_reason": "tool_calls"
            ]],
            "usage": [
                "prompt_tokens": 5,
                "completion_tokens": 7,
                "total_tokens": 12,
                "provider_input_tokens": 812
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "application/json"]
        )
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "example-provider",
            fetch: fetch,
            convertUsage: { usage in
                let providerInputTokens: Int?
                if case .object(let raw)? = usage?.raw,
                   case .number(let value)? = raw["provider_input_tokens"] {
                    providerInputTokens = Int(value)
                } else {
                    providerInputTokens = nil
                }
                return LanguageModelV4Usage(
                    inputTokens: .init(total: providerInputTokens),
                    outputTokens: .init(total: 900)
                )
            }
        ))
        let model = try provider.languageModel(modelId: "reasoning-model")

        let result = try await model.doGenerate(options: .init(prompt: v4ChatPrompt))

        #expect(result.finishReason.unified == .toolCalls)
        #expect(result.usage.inputTokens.total == 812)
        #expect(result.usage.outputTokens.total == 900)
        #expect(result.content.count == 3)

        guard case .reasoning(let reasoning) = result.content[1],
              case .toolCall(let toolCall) = result.content[2] else {
            Issue.record("Expected reasoning followed by a tool call")
            return
        }

        #expect(reasoning.text == "fallback reasoning")
        #expect(toolCall.toolCallId == "call-1")
        #expect(toolCall.toolName == "lookup")
        #expect(toolCall.input == #"{"id":1}"#)
        #expect(toolCall.providerMetadata == [
            "example-provider": ["thoughtSignature": .string("signature-1")]
        ])
    }

    @Test("native V4 stream orders reasoning text and supports late-name and indexless tool calls")
    func nativeV4StreamPreservesOrderingAndBufferedToolCalls() async throws {
        let eventObjects: [[String: Any]] = [
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": ["reasoning": "think"],
                    "finish_reason": NSNull()
                ]]
            ],
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": ["content": "answer"],
                    "finish_reason": NSNull()
                ]]
            ],
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "id": "call-1",
                            "type": "function",
                            "function": ["arguments": #"{"city":"#],
                            "extra_content": [
                                "google": ["thought_signature": "signature-1"]
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ],
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "index": 0,
                            "function": [
                                "name": "weather",
                                "arguments": "\"Paris\"}"
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ],
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": [
                        "tool_calls": [[
                            "id": "call-2",
                            "function": [
                                "name": "clock",
                                "arguments": "{}"
                            ]
                        ]]
                    ],
                    "finish_reason": NSNull()
                ]]
            ],
            [
                "id": "chatcmpl-stream-v4",
                "created": 1_712_000_000,
                "model": "reasoning-model",
                "choices": [[
                    "delta": [:],
                    "finish_reason": "tool_calls"
                ]],
                "usage": [
                    "prompt_tokens": 2,
                    "completion_tokens": 3,
                    "total_tokens": 5,
                    "provider_output_tokens": 901
                ]
            ]
        ]
        let events = try eventObjects.map {
            String(decoding: try JSONSerialization.data(withJSONObject: $0), as: UTF8.self)
        }
        let targetURL = URL(string: "https://api.example.com/v1/chat/completions")!
        let httpResponse = makeHTTPResponse(
            url: targetURL,
            headers: ["Content-Type": "text/event-stream"]
        )
        let fetch: FetchFunction = { _ in
            FetchResponse(body: makeStreamBody(from: events), urlResponse: httpResponse)
        }
        let provider = createOpenAICompatible(settings: .init(
            baseURL: "https://api.example.com/v1",
            name: "example-provider",
            fetch: fetch,
            includeUsage: true,
            convertUsage: { usage in
                let providerOutputTokens: Int?
                if case .object(let raw)? = usage?.raw,
                   case .number(let value)? = raw["provider_output_tokens"] {
                    providerOutputTokens = Int(value)
                } else {
                    providerOutputTokens = nil
                }
                return LanguageModelV4Usage(
                    inputTokens: .init(total: usage?.totalTokens),
                    outputTokens: .init(total: providerOutputTokens)
                )
            }
        ))
        let model = try provider.languageModel(modelId: "reasoning-model")
        let result = try await model.doStream(options: .init(prompt: v4ChatPrompt))

        var parts: [LanguageModelV4StreamPart] = []
        for try await part in result.stream {
            parts.append(part)
        }

        guard let reasoningEndIndex = parts.firstIndex(where: {
            if case .reasoningEnd(id: "reasoning-0", providerMetadata: nil) = $0 { return true }
            return false
        }),
        let textStartIndex = parts.firstIndex(where: {
            if case .textStart(id: "txt-0", providerMetadata: nil) = $0 { return true }
            return false
        }),
        let textEndIndex = parts.firstIndex(where: {
            if case .textEnd(id: "txt-0", providerMetadata: nil) = $0 { return true }
            return false
        }),
        let toolCallIndex = parts.firstIndex(where: {
            if case .toolCall = $0 { return true }
            return false
        }) else {
            Issue.record("Expected reasoning text and tool-call lifecycle events")
            return
        }

        #expect(reasoningEndIndex < textStartIndex)
        #expect(textEndIndex < toolCallIndex)

        guard case .toolCall(let toolCall) = parts[toolCallIndex],
              case let .finish(finishReason, usage, _) = parts.last else {
            Issue.record("Expected finalized tool call and finish")
            return
        }

        #expect(toolCall.toolCallId == "call-1")
        #expect(toolCall.toolName == "weather")
        #expect(toolCall.input == #"{"city":"Paris"}"#)
        #expect(toolCall.providerMetadata == [
            "example-provider": ["thoughtSignature": .string("signature-1")]
        ])

        let completedToolCalls = parts.compactMap { part -> LanguageModelV4ToolCall? in
            guard case .toolCall(let value) = part else { return nil }
            return value
        }
        #expect(completedToolCalls.count == 2)
        let indexlessToolCall = completedToolCalls.first { $0.toolCallId == "call-2" }
        #expect(indexlessToolCall?.toolName == "clock")
        #expect(indexlessToolCall?.input == "{}")
        #expect(finishReason.unified == .toolCalls)
        #expect(usage.inputTokens.total == 5)
        #expect(usage.outputTokens.total == 901)
    }

    @Test("embedding doEmbed maps V4 result metadata and usage")
    func embeddingDoEmbedUsesV4Surface() async throws {
        let responseJSON: [String: Any] = [
            "data": [
                ["embedding": [0.1, 0.2]],
                ["embedding": [0.3, 0.4]]
            ],
            "usage": [
                "prompt_tokens": 8,
                "total_tokens": 8
            ],
            "providerMetadata": [
                "example": ["trace": "ok"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/embeddings")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["X-Embedding": "ok"])

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))
        let model = try provider.embeddingModel(modelId: "text-embedding-3-large")

        let result = try await model.doEmbed(options: EmbeddingModelV4CallOptions(values: ["one", "two"]))

        #expect(result.embeddings == [[0.1, 0.2], [0.3, 0.4]])
        #expect(result.usage?.tokens == 8)
        #expect(result.response?.headers?["x-embedding"] == "ok")
        if case .string(let trace) = result.providerMetadata?["example"]?["trace"] {
            #expect(trace == "ok")
        } else {
            Issue.record("Expected V4 embedding provider metadata")
        }
    }

    @Test("native image doGenerate maps V4 base64 images warnings and response")
    func imageDoGenerateUsesV4Surface() async throws {
        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "data": [
                ["b64_json": "image-1"],
                ["b64_json": "image-2"]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: responseJSON)
        let targetURL = URL(string: "https://api.example.com/v1/images/generations")!
        let httpResponse = makeHTTPResponse(url: targetURL, headers: ["X-Image": "ok"])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: httpResponse)
        }

        let provider = createOpenAICompatible(settings: OpenAICompatibleProviderSettings(
            baseURL: "https://api.example.com/v1",
            name: "example",
            fetch: fetch
        ))
        let model = try provider.imageModel(modelId: "dall-e-3")
        #expect(model is OpenAICompatibleImageModelV4)

        let result = try await model.doGenerate(options: ImageModelV4CallOptions(
            prompt: "A geometric city",
            n: 2,
            size: "1024x1024",
            aspectRatio: "1:1",
            seed: 42,
            providerOptions: ["example": ["quality": .string("hd")]]
        ))

        if case .base64(let images) = result.images {
            #expect(images == ["image-1", "image-2"])
        } else {
            Issue.record("Expected V4 base64 images")
        }

        #expect(result.warnings.count == 2)
        #expect(result.response.modelId == "dall-e-3")
        #expect(result.response.headers?["x-image"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing captured request")
            return
        }

        #expect(json["model"] as? String == "dall-e-3")
        #expect(json["prompt"] as? String == "A geometric city")
        #expect(json["n"] as? Double == 2)
        #expect(json["size"] as? String == "1024x1024")
        #expect(json["quality"] as? String == "hd")
        #expect(json["response_format"] as? String == "b64_json")
    }
}
