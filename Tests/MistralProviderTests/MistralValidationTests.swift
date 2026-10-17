import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import MistralProvider

@Suite("Mistral validation boundaries")
struct MistralValidationTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "Hello"))], providerOptions: nil)]

    private func provider(response: JSONValue, status: Int = 200) -> MistralProvider {
        createMistral(settings: .init(apiKey: "key", fetch: { request in
            FetchResponse(
                body: .data(try JSONEncoder().encode(response)),
                urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
            )
        }))
    }

    private func chatResponse(usage: JSONObject) -> JSONValue {
        .object([
            "object": .string("chat.completion"),
            "choices": .array([.object([
                "index": .number(0),
                "message": .object(["role": .string("assistant"), "content": .string("Hello")]),
                "finish_reason": .string("stop")
            ])]),
            "usage": .object(usage)
        ])
    }

    @Test("large raw-only usage fields preserve finite numbers without integer conversion")
    func largeRawUsage() async throws {
        let usage: JSONObject = [
            "prompt_tokens": .number(10), "completion_tokens": .number(4), "total_tokens": .number(1e100),
            "prompt_audio_seconds": .number(1e100), "request_count": .number(1e100), "num_cached_tokens": .number(2),
            "prompt_tokens_details": .object(["cached_tokens": .number(1e100), "audio_tokens": .number(1e100)]),
            "completion_tokens_details": .object(["reasoning_tokens": .number(1e100)])
        ]
        let result = try await provider(response: chatResponse(usage: usage)).chat(modelId: .mistralSmallLatest).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.text(.init(text: "Hello"))])
        #expect(result.usage.inputTokens.total == 10)
        #expect(result.usage.inputTokens.cacheRead == 2)
        #expect(result.usage.inputTokens.noCache == 8)
        #expect(result.usage.outputTokens.total == 4)
        #expect(result.usage.raw == .object(usage))
    }

    @Test("unrepresentable normalized token counts reject as typed API errors", arguments: [
        ["prompt_tokens": JSONValue.number(1e100), "completion_tokens": .number(4), "total_tokens": .number(4)],
        ["prompt_tokens": .number(10), "completion_tokens": .number(1e100), "total_tokens": .number(10)],
        ["prompt_tokens": .number(10), "completion_tokens": .number(4), "total_tokens": .number(14), "num_cached_tokens": .number(1e100)],
        ["prompt_tokens": .number(-9e18), "completion_tokens": .number(4), "total_tokens": .number(4), "num_cached_tokens": .number(9e18)]
    ])
    func invalidTokenCounts(usage: JSONObject) async throws {
        do {
            _ = try await provider(response: chatResponse(usage: usage)).chat(modelId: .mistralSmallLatest).doGenerate(options: .init(prompt: prompt))
            Issue.record("Expected token count validation failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.message == "Invalid JSON response")
            #expect(error.cause is TypeValidationError)
        }
    }

    @Test("explicit null chat options reject as invalid arguments")
    func nullChatOption() async throws {
        let model = provider(response: .null).chat(modelId: .mistralSmallLatest)
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: prompt, providerOptions: ["mistral": ["reasoningEffort": .null]]))
        }
    }

    @Test("explicit null embedding dimensions do not fall back to top-level dimensions")
    func nullEmbeddingOption() async throws {
        let model = provider(response: .null).embedding(.mistralEmbed)
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doEmbed(options: .init(values: ["Hello"], dimensions: 2, providerOptions: ["mistral": ["outputDimension": .null]]))
        }
    }

    @Test("malformed provider errors fall back to HTTP status", arguments: [
        ["object": JSONValue.string("other"), "message": .string("Provider message"), "type": .string("invalid_request_error"), "param": .null, "code": .null],
        ["object": .string("error"), "message": .string("Provider message"), "type": .string("invalid_request_error"), "code": .null],
        ["object": .string("error"), "message": .string("Provider message"), "type": .string("invalid_request_error"), "param": .null]
    ])
    func malformedError(payload: JSONObject) async throws {
        let httpResponse = HTTPURLResponse(url: HTTPTestHelpers.chatURL, statusCode: 400, httpVersion: nil, headerFields: nil)!
        let expectedMessage = ProviderHTTPResponse(url: HTTPTestHelpers.chatURL, httpResponse: httpResponse, body: .none).statusText
        do {
            _ = try await provider(response: .object(payload), status: 400).chat(modelId: .mistralSmallLatest).doGenerate(options: .init(prompt: prompt))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message == expectedMessage)
            #expect(error.data == nil)
        }
    }

    @Test("required nullable error fields preserve the provider message and data")
    func nullableError() async throws {
        let payload: JSONObject = ["object": .string("error"), "message": .string("Provider message"), "type": .string("invalid_request_error"), "param": .null, "code": .null]
        do {
            _ = try await provider(response: .object(payload), status: 400).embedding(.mistralEmbed).doEmbed(options: .init(values: ["Hello"]))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message == "Provider message")
            let data = try #require(error.data as? MistralErrorData)
            #expect(data.object == "error")
            #expect(data.param == nil)
            #expect(data.code == nil)
            let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(data))
            #expect(encoded == .object(payload))
        }
    }
}
