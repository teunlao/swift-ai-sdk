import Foundation
import AISDKProvider

@testable import SwiftAISDK

/**
 Test double for `EmbeddingModelV3` mirroring upstream `mock-embedding-model-v3`.
 */
final class TestEmbeddingModelV3<Value: Sendable>: EmbeddingModelV3 {
    typealias VALUE = Value

    let specificationVersion: String
    let provider: String
    let modelId: String

    private let maxEmbeddingsPerCallValue: Int?
    private let supportsParallelCallsValue: Bool
    private let doEmbedHandler: @Sendable (EmbeddingModelV3DoEmbedOptions<Value>) async throws -> EmbeddingModelV3DoEmbedResult

    init(
        specificationVersion: String = "v3",
        provider: String = "test-provider",
        modelId: String = "test-model",
        maxEmbeddingsPerCall: Int? = nil,
        supportsParallelCalls: Bool = true,
        doEmbed: @escaping @Sendable (EmbeddingModelV3DoEmbedOptions<Value>) async throws -> EmbeddingModelV3DoEmbedResult
    ) {
        self.specificationVersion = specificationVersion
        self.provider = provider
        self.modelId = modelId
        self.maxEmbeddingsPerCallValue = maxEmbeddingsPerCall
        self.supportsParallelCallsValue = supportsParallelCalls
        self.doEmbedHandler = doEmbed
    }

    var maxEmbeddingsPerCall: Int? {
        get async throws { maxEmbeddingsPerCallValue }
    }

    var supportsParallelCalls: Bool {
        get async throws { supportsParallelCallsValue }
    }

    func doEmbed(options: EmbeddingModelV3DoEmbedOptions<Value>) async throws -> EmbeddingModelV3DoEmbedResult {
        try await doEmbedHandler(options)
    }
}

/**
 Test double for `EmbeddingModelV4` mirroring upstream `mock-embedding-model-v4`.
 */
final class TestEmbeddingModelV4: EmbeddingModelV4, @unchecked Sendable {
    let specificationVersion: String
    let provider: String
    let modelId: String

    private let maxEmbeddingsPerCallValue: Int?
    private let supportsParallelCallsValue: Bool
    private let doEmbedHandler: @Sendable (EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result

    init(
        specificationVersion: String = "v4",
        provider: String = "test-provider",
        modelId: String = "test-model",
        maxEmbeddingsPerCall: Int? = nil,
        supportsParallelCalls: Bool = true,
        doEmbed: @escaping @Sendable (EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result
    ) {
        self.specificationVersion = specificationVersion
        self.provider = provider
        self.modelId = modelId
        self.maxEmbeddingsPerCallValue = maxEmbeddingsPerCall
        self.supportsParallelCallsValue = supportsParallelCalls
        self.doEmbedHandler = doEmbed
    }

    var maxEmbeddingsPerCall: Int? {
        get async throws { maxEmbeddingsPerCallValue }
    }

    var supportsParallelCalls: Bool {
        get async throws { supportsParallelCallsValue }
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        try await doEmbedHandler(options)
    }
}
