import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepSeekProvider

@Suite("DeepSeek schema contracts")
struct DeepSeekValidationContractsTests {
    @Test(arguments: ["model", "message", "file", "upload"])
    func optionalOptionsRejectExplicitNull(scope: String) async throws {
        let provider = createDeepSeek(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) {
            switch scope {
            case "model": _ = try await provider("deepseek-v4-flash").doGenerate(options: .init(prompt: [], providerOptions: ["deepseek": ["thinking": .null]]))
            case "message": _ = try await provider("deepseek-v4-flash").doGenerate(options: .init(prompt: [.system(content: "System", providerOptions: ["deepseek": ["name": .null]])]))
            case "file": _ = try await provider("deepseek-v4-flash").doGenerate(options: .init(prompt: [.user(content: [.file(.init(data: .data(Data([1])), mediaType: "image/png", providerOptions: ["deepseek": ["imageDetail": .null]]))], providerOptions: nil)]))
            default: _ = try await provider.files().uploadFile(options: .init(data: .data(Data([1])), mediaType: "image/png", providerOptions: ["deepseek": ["expiresAfter": .null]]))
            }
        }
    }

    @Test(arguments: [
        JSONValue.object(["object": "other", "choices": [["message": ["content": "Answer"], "finish_reason": "stop"]]]),
        JSONValue.object(["choices": [["message": ["role": "user", "content": "Answer"], "finish_reason": "stop"]]]),
        JSONValue.object(["choices": [["message": ["tool_calls": [["type": "other", "function": ["name": "lookup", "arguments": "{}"]]]], "finish_reason": "tool_calls"]]])
    ])
    func responseDiscriminatorsAreValidated(response: JSONValue) async throws {
        let provider = createDeepSeek(settings: .init(apiKey: "key", fetch: try DeepSeekProviderTests.fetch(response)))
        await #expect(throws: APICallError.self) { _ = try await provider("deepseek-v4-pro").doGenerate(options: .init(prompt: [])) }
    }

    @Test func logprobsPreserveNullableBytesAndStripUnmodeledFields() async throws {
        let expected: JSONValue = ["content": [["token": "A", "logprob": -1, "bytes": .null, "top_logprobs": [["token": "B", "logprob": -2, "bytes": .null]]]]]
        let response: JSONValue = ["choices": [["message": ["content": "A"], "finish_reason": "stop", "logprobs": ["extension": "ignored", "content": [["token": "A", "logprob": -1, "bytes": .null, "extension": "ignored", "top_logprobs": [["token": "B", "logprob": -2, "bytes": .null, "extension": "ignored"]]]]]]]]
        let model = createDeepSeek(settings: .init(apiKey: "key", fetch: try DeepSeekProviderTests.fetch(response)))("deepseek-v4-pro")
        let result = try await model.doGenerate(options: .init(prompt: []))
        #expect(result.providerMetadata?["deepseek"]?["logprobs"] == expected)
    }

    @Test(arguments: [429.0, 429.1, 1e100])
    func numericStreamErrorCodesRetainValueWithoutIntegerCoercion(code: Double) async throws {
        let json: JSONValue = ["error": ["message": "Error", "code": .number(code)]]
        let bytes = Data(("data: " + String(decoding: try JSONEncoder().encode(json), as: UTF8.self) + "\n\ndata: [DONE]\n\n").utf8)
        let fetch: FetchFunction = { request in FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!) }
        let stream = try await createDeepSeek(settings: .init(apiKey: "key", fetch: fetch))("deepseek-v4-pro").doStream(options: .init(prompt: [])).stream
        var errors: [ProviderStreamError] = []
        for try await part in stream { if case .error(.providerStreamError(let error)) = part { errors.append(error) } }
        let error = try #require(errors.first)
        #expect(errors.count == 1)
        #expect(error.code == .number(code))
        #expect(error.statusCode == (code == 429 ? 429 : nil))
        #expect(error.isRetryable == (code == 429 ? true : nil))
    }
}
