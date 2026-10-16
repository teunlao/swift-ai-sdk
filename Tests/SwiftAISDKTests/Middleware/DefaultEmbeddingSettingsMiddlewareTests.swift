import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

@Suite("defaultEmbeddingSettingsMiddleware")
struct DefaultEmbeddingSettingsMiddlewareTests {
    private func transform(
        _ settings: DefaultEmbeddingSettings,
        _ params: EmbeddingModelV4CallOptions
    ) async throws -> EmbeddingModelV4CallOptions {
        let model = TestEmbeddingModelV4 { _ in EmbeddingModelV4Result(embeddings: []) }
        return try await defaultEmbeddingSettingsMiddleware(settings: settings).transformParams!(params, model)
    }

    @Test("merges headers and deep-merges provider options, the call winning")
    func merge() async throws {
        let result = try await transform(
            DefaultEmbeddingSettings(
                headers: ["X-Default": "default", "X-Shared": "default"],
                providerOptions: ["google": ["taskType": .string("SEMANTIC_SIMILARITY"), "nested": .object(["a": .bool(true)])]]
            ),
            EmbeddingModelV4CallOptions(
                values: ["hello"],
                dimensions: 8,
                providerOptions: ["google": ["nested": .object(["b": .bool(true)])]],
                headers: ["X-Shared": "param"]
            )
        )

        #expect(result.values == ["hello"])
        #expect(result.dimensions == 8)
        #expect(result.headers == ["X-Default": "default", "X-Shared": "param"])
        #expect(result.providerOptions == [
            "google": ["taskType": .string("SEMANTIC_SIMILARITY"), "nested": .object(["a": .bool(true), "b": .bool(true)])],
        ])
    }

    @Test("keeps whichever side is set when the other is absent")
    func oneSided() async throws {
        let defaultsOnly = try await transform(
            DefaultEmbeddingSettings(headers: ["X-Default": "default"], providerOptions: ["p": ["k": .string("v")]]),
            EmbeddingModelV4CallOptions(values: ["hello"])
        )
        #expect(defaultsOnly.headers == ["X-Default": "default"])
        #expect(defaultsOnly.providerOptions == ["p": ["k": .string("v")]])

        let neither = try await transform(DefaultEmbeddingSettings(), EmbeddingModelV4CallOptions(values: ["hello"]))
        #expect(neither.headers == nil)
        #expect(neither.providerOptions == nil)
    }
}
