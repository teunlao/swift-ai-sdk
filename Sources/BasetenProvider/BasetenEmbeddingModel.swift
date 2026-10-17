import Foundation
import AISDKProvider

public struct BasetenPerformanceResponse: Codable, Sendable {
    public struct Item: Codable, Sendable {
        public let embedding: [Double]
        public init(embedding: [Double]) { self.embedding = embedding }
    }
    public struct Usage: Codable, Sendable {
        public let totalTokens: Int?
        public init(totalTokens: Int?) { self.totalTokens = totalTokens }
        enum CodingKeys: String, CodingKey { case totalTokens = "total_tokens" }
    }
    public let data: [Item]
    public let usage: Usage?
    public init(data: [Item], usage: Usage? = nil) { self.data = data; self.usage = usage }
}
public protocol BasetenPerformanceClient: Sendable {
    func embed(input: [String], model: String) async throws -> BasetenPerformanceResponse
}
public typealias BasetenPerformanceClientConstructor = @Sendable (_ baseURL: String, _ apiKey: String) throws -> any BasetenPerformanceClient

final class BasetenEmbeddingModel: EmbeddingModelV4 {
    let specificationVersion = "v4"
    let provider = "baseten.embedding"
    let modelId: String
    private let client: @Sendable () throws -> any BasetenPerformanceClient
    var maxEmbeddingsPerCall: Int? { get async throws { nil } }
    var supportsParallelCalls: Bool { get async throws { true } }
    init(modelId: String, client: @escaping @Sendable () throws -> any BasetenPerformanceClient) { self.modelId = modelId; self.client = client }
    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let response = try await client().embed(input: options.values, model: modelId)
        let body = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(response))
        return .init(embeddings: response.data.map(\.embedding), usage: response.usage?.totalTokens.map { .init(tokens: $0) },
                     response: .init(headers: [:], body: body), warnings: [])
    }
}

public struct BasetenEmbeddingModelOptions: Codable, Sendable, Equatable {
    public init() {}
}
