import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import DeepInfraProvider

@Suite("DeepInfraChat usage fix", .serialized)
struct DeepInfraChatUsageFixTests {
    private let prompt: LanguageModelV3Prompt = [
        .user(content: [.text(.init(text: "Test prompt"))], providerOptions: nil),
    ]

    private func httpResponse(url: URL) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
    }

    @Test("fixes incorrect completion_tokens when reasoning_tokens > completion_tokens (doGenerate)")
    func fixesUsageForGeminiModelsDoGenerate() async throws {
        let responseBody: [String: Any] = [
            "id": "test-id",
            "object": "chat.completion",
            "created": 1_234_567_890,
            "model": "google/gemma-2-9b-it",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test response",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 19,
                "completion_tokens": 84,
                "total_tokens": 1184,
                "prompt_tokens_details": NSNull(),
                "completion_tokens_details": [
                    "reasoning_tokens": 1081,
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: responseBody)
        let url = URL(string: "https://api.deepinfra.com/v1/openai/chat/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: url))
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "google/gemma-2-9b-it")

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.outputTokens.total == 1165) // 84 + 1081
        #expect(result.usage.outputTokens.text == 84)
        #expect(result.usage.outputTokens.reasoning == 1081)

        // Raw usage should reflect the corrected completion_tokens.
        guard let raw = result.usage.raw, case .object(let dict) = raw else {
            Issue.record("Expected usage.raw object")
            return
        }
        if case .number(let completion)? = dict["completion_tokens"] {
            #expect(Int(completion) == 1165)
        } else {
            Issue.record("Expected corrected completion_tokens in raw usage")
        }
    }

    @Test("does not modify usage when reasoning tokens are absent (doGenerate)")
    func doesNotModifyUsageForNonGeminiModelsDoGenerate() async throws {
        let responseBody: [String: Any] = [
            "id": "test-id",
            "object": "chat.completion",
            "created": 1_234_567_890,
            "model": "mistralai/Mixtral-8x7B-Instruct-v0.1",
            "choices": [[
                "index": 0,
                "message": [
                    "role": "assistant",
                    "content": "Test response",
                ],
                "finish_reason": "stop",
            ]],
            "usage": [
                "prompt_tokens": 18,
                "completion_tokens": 475,
                "total_tokens": 493,
                "prompt_tokens_details": NSNull(),
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: responseBody)
        let url = URL(string: "https://api.deepinfra.com/v1/openai/chat/completions")!
        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(data), urlResponse: self.httpResponse(url: url))
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "mistralai/Mixtral-8x7B-Instruct-v0.1")

        let result = try await model.doGenerate(options: .init(prompt: prompt))

        #expect(result.usage.outputTokens.total == 475)
        #expect(result.usage.outputTokens.text == 475)
        #expect(result.usage.outputTokens.reasoning == 0)
    }

    @Test("fixes incorrect completion_tokens when reasoning_tokens > completion_tokens (doStream finish)")
    func fixesUsageForGeminiModelsDoStreamFinish() async throws {
        let chunks = "data: {\"id\":\"stream-id\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"google/gemma-2-9b-it\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"Hello\"},\"finish_reason\":null}]}\n\n" +
            "data: {\"id\":\"stream-id\",\"object\":\"chat.completion.chunk\",\"created\":1234567890,\"model\":\"google/gemma-2-9b-it\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}],\"usage\":{\"prompt_tokens\":19,\"completion_tokens\":84,\"total_tokens\":1184,\"prompt_tokens_details\":null,\"completion_tokens_details\":{\"reasoning_tokens\":1081}}}\n\n" +
            "data: [DONE]\n\n"

        let url = URL(string: "https://api.deepinfra.com/v1/openai/chat/completions")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!

        let fetch: FetchFunction = { _ in
            FetchResponse(body: .data(Data(chunks.utf8)), urlResponse: httpResponse)
        }

        let provider = createDeepInfra(settings: .init(apiKey: "test-key", fetch: fetch))
        let model = try provider.languageModel(modelId: "google/gemma-2-9b-it")
        let streamResult = try await model.doStream(options: .init(prompt: prompt))

        var finishPart: LanguageModelV3StreamPart?
        for try await part in streamResult.stream {
            if case .finish = part {
                finishPart = part
            }
        }

        guard case let .finish(_, usage, _)? = finishPart else {
            Issue.record("Expected finish part")
            return
        }

        #expect(usage.outputTokens.total == 1165) // 84 + 1081
        #expect(usage.outputTokens.text == 84)
        #expect(usage.outputTokens.reasoning == 1081)
    }
}

