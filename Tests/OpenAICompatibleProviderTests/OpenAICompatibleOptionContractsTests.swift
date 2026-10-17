import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

@Suite("Compatible option validation")
struct OpenAICompatibleOptionContractsTests {
    @Test(arguments: ["chat", "completion", "embedding"])
    func optionalFieldsRejectExplicitNull(kind: String) async throws {
        let provider = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: { _ in throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) {
            switch kind {
            case "chat": _ = try await provider("model").doGenerate(options: .init(prompt: [], providerOptions: ["openaiCompatible": ["user": .null]]))
            case "completion": _ = try await provider.completionModel(modelId: "model").doGenerate(options: .init(prompt: [], providerOptions: ["custom": ["echo": .null]]))
            default: _ = try await provider.embeddingModel(modelId: "model").doEmbed(options: .init(values: ["value"], providerOptions: ["openaiCompatible": ["dimensions": .null]]))
            }
        }
    }
    @Test(arguments: [Double.nan, Double.infinity])
    func nonFiniteDimensionsAreTypedValidationFailures(dimensions: Double) async throws {
        let provider = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: { _ in throw CancellationError() }))
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await provider.embeddingModel(modelId: "model").doEmbed(options: .init(values: ["value"], providerOptions: ["openaiCompatible": ["dimensions": .number(dimensions)]]))
        }
    }
    @Test(arguments: [JSONValue.object(["prompt_tokens": "invalid"]), JSONValue.object(["completion_tokens_details": 3])])
    func malformedUsageIsRejectedInsteadOfReportingZero(usage: JSONValue) async throws {
        let bytes = try JSONEncoder().encode(JSONValue.object(["choices": [["message": ["content": "Answer"], "finish_reason": "stop"]], "usage": usage]))
        let fetch: FetchFunction = { request in FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) }
        let model = createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch))("model")
        await #expect(throws: APICallError.self) { _ = try await model.doGenerate(options: .init(prompt: [])) }
    }
    @Test(arguments: [false, true])
    func embeddingMetadataDistinguishesAbsentFromNull(explicitNull: Bool) async throws {
        var response: [String: JSONValue] = ["data": [["embedding": [1]]], "usage": .null]
        if explicitNull { response["providerMetadata"] = .null }
        let bytes = try JSONEncoder().encode(JSONValue.object(response))
        let fetch: FetchFunction = { request in FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) }
        let model = try createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom", fetch: fetch)).embeddingModel(modelId: "model")
        if explicitNull {
            await #expect(throws: APICallError.self) { _ = try await model.doEmbed(options: .init(values: ["value"])) }
        } else {
            let result = try await model.doEmbed(options: .init(values: ["value"]))
            #expect(result.embeddings == [[1]])
            #expect(result.usage == nil)
        }
    }

    @Test(arguments: [1.5, 1e20])
    func providerDimensionsRequireIntegers(_ dimensions: Double) async throws {
        let model = try createOpenAICompatible(settings: .init(baseURL: "https://api.example.com", name: "custom")).embeddingModel(modelId: "model")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doEmbed(options: .init(values: ["value"], providerOptions: ["custom": ["dimensions": .number(dimensions)]]))
        }
    }
}
