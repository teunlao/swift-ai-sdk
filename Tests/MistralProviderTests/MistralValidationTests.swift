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

    struct CountCase: Sendable {
        let prompt: Double
        let completion: Double
        let cached: Double
        let input: Int?
        let output: Int?
        let read: Int?
        let noCache: Int?
    }

    @Test("source-valid numeric usage preserves raw and projects representable fields independently", arguments: [
        CountCase(prompt: 1e100, completion: 4, cached: 0, input: nil, output: 4, read: nil, noCache: nil),
        CountCase(prompt: 10, completion: 1e100, cached: 0, input: 10, output: nil, read: nil, noCache: 10),
        CountCase(prompt: 10, completion: 4, cached: 1e100, input: 10, output: 4, read: nil, noCache: nil),
        CountCase(prompt: -9e18, completion: 4, cached: 9e18, input: -9_000_000_000_000_000_000, output: 4, read: 9_000_000_000_000_000_000, noCache: nil),
        CountCase(prompt: 1.5, completion: 4, cached: 0.5, input: nil, output: 4, read: nil, noCache: 1),
        CountCase(prompt: 1e100, completion: 4, cached: 1e100, input: nil, output: 4, read: nil, noCache: 0)
    ])
    func numericUsage(value: CountCase) async throws {
        let usage: JSONObject = ["prompt_tokens": .number(value.prompt), "completion_tokens": .number(value.completion), "total_tokens": 4, "num_cached_tokens": .number(value.cached)]
        let result = try await provider(response: chatResponse(usage: usage)).chat(modelId: .mistralSmallLatest).doGenerate(options: .init(prompt: prompt))
        #expect(result.content == [.text(.init(text: "Hello"))])
        #expect(result.usage.inputTokens.total == value.input)
        #expect(result.usage.inputTokens.cacheRead == value.read)
        #expect(result.usage.inputTokens.noCache == value.noCache)
        #expect(result.usage.outputTokens.total == value.output)
        #expect(result.usage.raw == .object(usage))
    }

    @Test("embedding output survives unrepresentable usage while raw usage remains available")
    func numericEmbeddingUsage() async throws {
        let response: JSONValue = ["data": [["embedding": [1.0]]], "usage": ["prompt_tokens": .number(1e100)]]
        let result = try await provider(response: response).embedding(.mistralEmbed).doEmbed(options: .init(values: ["text"]))
        #expect(result.embeddings == [[1]])
        #expect(result.usage == nil)
        #expect(try jsonValue(from: #require(result.response?.body)) == response)
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
