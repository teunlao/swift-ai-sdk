import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import BasetenProvider

@Suite("Baseten embedding contracts")
struct BasetenEmbeddingContractsTests {
    actor Capture {
        var request: URLRequest?
        func store(_ value: URLRequest) { request = value }
        func value() -> URLRequest? { request }
    }
    @Test func defaultHTTPEmbeddingsUseSyncV1AndEnforceBatchLimit() async throws {
        let capture = Capture()
        let data = Data(#"{"data":[{"embedding":[1,2]}],"usage":{"prompt_tokens":3}}"#.utf8)
        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        let provider = createBaseten(settings: .init(apiKey: "key", modelURL: "https://deployment.example.com/sync", fetch: fetch))
        let model = try provider.embeddingModel(.init(rawValue: "custom-model"))
        let result = try await model.doEmbed(options: .init(values: ["hello"]))
        #expect(result.embeddings == [[1, 2]])
        #expect(result.usage?.tokens == 3)
        let request = try #require(await capture.value())
        #expect(request.url?.absoluteString == "https://deployment.example.com/sync/v1/embeddings")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
        let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
        #expect(body == ["model": "custom-model", "input": ["hello"], "encoding_format": "float"])
        await #expect(throws: TooManyEmbeddingValuesForCallError.self) {
            _ = try await model.doEmbed(options: .init(values: Array(repeating: "value", count: 129)))
        }
    }

    struct NativeClient: BasetenPerformanceClient {
        func embed(input: [String], model: String) async throws -> BasetenPerformanceResponse {
            .init(data: input.map { _ in .init(embedding: [3, 4]) })
        }
    }
    @Test func optInNativeClientOwnsLargeBatchesAndMissingUsage() async throws {
        let provider = createBaseten(settings: .init(apiKey: "key", modelURL: "https://deployment.example.com/sync/v1", performanceClient: { _, _ in NativeClient() }))
        let model = try provider.embeddingModel()
        let result = try await model.doEmbed(options: .init(values: Array(repeating: "value", count: 129)))
        #expect(result.embeddings == Array(repeating: [3, 4], count: 129))
        #expect(result.usage == nil)
        #expect(try await model.maxEmbeddingsPerCall == nil)
    }
    @Test(arguments: [JSONValue.string("Rejected"), JSONValue.object(["message": "Rejected", "type": "not_found", "code": 404])])
    func errorEnvelopesRetainProviderMessage(error: JSONValue) async throws {
        let bytes = try JSONEncoder().encode(JSONValue.object(["error": error]))
        let fetch: FetchFunction = { request in FetchResponse(body: .data(bytes), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!) }
        do {
            _ = try await createBaseten(settings: .init(apiKey: "key", fetch: fetch)).chat().doGenerate(options: .init(prompt: []))
            Issue.record("Expected provider error")
        } catch let error as APICallError { #expect(error.message == "Rejected") }
    }
}
