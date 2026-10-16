import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK

private final class CapableEmbeddingModel: EmbeddingModelV4, EmbeddingModelMaxInputBytesPerCall,
    EmbeddingModelProviderOptionsTransformer, @unchecked Sendable {
    let provider = "capable-provider"
    let modelId = "capable-model"
    var maxEmbeddingsPerCall: Int? { get async throws { 2 } }
    var supportsParallelCalls: Bool { get async throws { false } }
    var maxInputBytesPerCall: Int? { get async throws { 1024 } }

    func transformProviderOptions(
        _ options: EmbeddingModelProviderOptionsTransformerOptions
    ) async throws -> SharedV4ProviderOptions? {
        ["capable": ["range": .string("\(options.startIndex)-\(options.endIndex)")]]
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        EmbeddingModelV4Result(embeddings: options.values.map { _ in [1] })
    }
}

/// Records the order in which middleware stages run.
private actor Trace {
    private(set) var events: [String] = []
    func record(_ event: String) { events.append(event) }
}

@Suite("wrapEmbeddingModel")
struct WrapEmbeddingModelTests {
    @Test("resolves identifiers from the parameters, then the middleware overrides, then the model")
    func identifiers() async throws {
        let model = TestEmbeddingModelV4(provider: "base-provider", modelId: "base-model", maxEmbeddingsPerCall: 3) { _ in
            EmbeddingModelV4Result(embeddings: [])
        }
        let overriding = EmbeddingModelV4Middleware(
            overrideProvider: { "override-\($0.provider)" },
            overrideModelId: { "override-\($0.modelId)" },
            overrideMaxEmbeddingsPerCall: { _ in 7 },
            overrideSupportsParallelCalls: { _ in false }
        )

        let passthrough = wrapEmbeddingModel(model: model, middleware: EmbeddingModelV4Middleware())
        #expect(passthrough.provider == "base-provider")
        #expect(passthrough.modelId == "base-model")
        #expect(try await passthrough.maxEmbeddingsPerCall == 3)
        #expect(try await passthrough.supportsParallelCalls == true)

        let overridden = wrapEmbeddingModel(model: model, middleware: overriding)
        #expect(overridden.provider == "override-base-provider")
        #expect(overridden.modelId == "override-base-model")
        #expect(try await overridden.maxEmbeddingsPerCall == 7)
        #expect(try await overridden.supportsParallelCalls == false)

        let explicit = wrapEmbeddingModel(model: model, middleware: overriding, modelId: "custom-model", providerId: "custom-provider")
        #expect(explicit.provider == "custom-provider")
        #expect(explicit.modelId == "custom-model")
    }

    @Test("forwards the max input bytes and provider options transformer capabilities of the wrapped model")
    func capabilities() async throws {
        let wrapped = wrapEmbeddingModel(model: CapableEmbeddingModel(), middleware: EmbeddingModelV4Middleware())

        let maxInputBytes = try await (wrapped as? any EmbeddingModelMaxInputBytesPerCall)?.maxInputBytesPerCall
        #expect(maxInputBytes == 1024)
        let transformed = try await (wrapped as? any EmbeddingModelProviderOptionsTransformer)?.transformProviderOptions(
            EmbeddingModelProviderOptionsTransformerOptions(providerOptions: nil, values: ["a", "b"], startIndex: 0, endIndex: 2)
        )
        #expect(transformed == ["capable": ["range": .string("0-2")]])

        let plain = wrapEmbeddingModel(
            model: TestEmbeddingModelV4 { _ in EmbeddingModelV4Result(embeddings: []) },
            middleware: EmbeddingModelV4Middleware()
        )
        #expect(!(plain is any EmbeddingModelProviderOptionsTransformer))
        #expect(try await (plain as? any EmbeddingModelMaxInputBytesPerCall)?.maxInputBytesPerCall == nil)
    }

    @Test("runs transformParams first to last, then wrapEmbed with the first middleware outermost")
    func chaining() async throws {
        let trace = Trace()
        let model = TestEmbeddingModelV4 { options in
            await trace.record("doEmbed \(options.values.joined(separator: ","))")
            return EmbeddingModelV4Result(embeddings: [[0.5]])
        }
        func middleware(_ name: String) -> EmbeddingModelV4Middleware {
            EmbeddingModelV4Middleware(
                transformParams: { params, _ in
                    await trace.record("transform \(name)")
                    return EmbeddingModelV4CallOptions(values: params.values + [name])
                },
                wrapEmbed: { doEmbed, params, _ in
                    await trace.record("wrap \(name) before \(params.values.joined(separator: ","))")
                    let result = try await doEmbed()
                    await trace.record("wrap \(name) after")
                    return result
                }
            )
        }

        let result = try await wrapEmbeddingModel(model: model, middleware: [middleware("A"), middleware("B")])
            .doEmbed(options: EmbeddingModelV4CallOptions(values: ["x"]))

        #expect(result.embeddings == [[0.5]])
        #expect(await trace.events == [
            "transform A",
            "wrap A before x,A",
            "transform B",
            "wrap B before x,A,B",
            "doEmbed x,A,B",
            "wrap B after",
            "wrap A after",
        ])
    }
}
