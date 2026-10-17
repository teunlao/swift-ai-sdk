import Foundation
import Testing
@testable import AISDKProvider
@testable import SwiftAISDK

@Suite("Native model resolution")
struct ResolveModelV4Tests {
    @Test("model reference literals route through the configured provider", arguments: ["literal", "route/\(3)"] as [LanguageModel])
    func literalModelReferences(reference: LanguageModel) async throws {
        let model = MockLanguageModelV4(doGenerate: .singleValue(.init(
            content: [.text(.init(text: "matched"))], finishReason: .stop,
            usage: .init(inputTokens: .init(total: 1), outputTokens: .init(total: 1))
        )))
        let provider = customProvider(languageModels: ["literal": model, "route/3": model])
        let result = try await withGlobalProvider(provider) {
            try await generateText(model: reference, prompt: "route")
        }
        #expect(result.text == "matched")
    }

    @Test("speech and transcription resolution preserves absent provider capabilities")
    func optionalModelCapabilityAbsent() throws {
        try withGlobalProvider(UnsupportedMediaProviderV4()) {
            let speech = try resolveSpeechModel("unsupported")
            let transcription = try resolveTranscriptionModel("unsupported")
            #expect(speech == nil)
            #expect(transcription == nil)
            let custom = customProvider(transcriptionModels: ["alias": "unsupported"],
                speechModels: ["alias": "unsupported"])
            #expect(throws: NoSuchModelError.self) { try custom.speechModel(modelId: "alias") }
            #expect(throws: NoSuchModelError.self) { try custom.transcriptionModel(modelId: "alias") }
        }
    }

    @Test("speech and transcription operations reject an unresolved model")
    func operationsRejectAbsentCapabilities() async {
        await withGlobalProvider(UnsupportedMediaProviderV4()) {
            await #expect(throws: ModelResolutionFailure.self) {
                try await generateSpeech(model: "unsupported", text: "hello")
            }
            await #expect(throws: ModelResolutionFailure.self) {
                try await transcribe(model: "unsupported", audio: .data(Data([1])))
            }
            #expect(throws: ModelResolutionFailure.self) {
                try streamTranscribe(model: "unsupported", audio: AsyncThrowingStream { $0.finish() },
                    inputAudioFormat: .init(type: "audio/pcm", rate: 24_000))
            }
        }
    }

    @Test("unconfigured string models resolve through the default gateway")
    func defaultGatewayResolution() throws {
        let embedding = try resolveEmbeddingModel("openai/text-embedding-3-small")
        #expect(embedding.provider == "gateway")
        #expect(embedding.modelId == "openai/text-embedding-3-small")
        let language = try resolveLanguageModel("anthropic/claude-sonnet-4.6")
        #expect(language.provider == "gateway")
        #expect(language.modelId == "anthropic/claude-sonnet-4.6")
        #expect(try resolveVideoModel("google/veo-3.1-generate-001") is GatewayVideoModel)
        #expect(try resolveSpeechModel("openai/tts-1") is GatewaySpeechModel)
        #expect(try resolveTranscriptionModel("openai/whisper-1") is GatewayTranscriptionModel)
        #expect(try resolveRerankingModel("cohere/rerank-v3.5") is GatewayRerankingModel)
    }
}

private struct UnsupportedMediaProviderV4: ProviderV4 {
    func languageModel(modelId: String) throws -> any LanguageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .languageModel) }
    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}
