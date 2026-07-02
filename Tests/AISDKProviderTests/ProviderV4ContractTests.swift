import Foundation
import Testing
@testable import AISDKProvider

@Suite("ProviderV4 Contracts")
struct ProviderV4ContractTests {
    @Test("ProviderV4 exposes required v4 model factories and optional upload surfaces")
    func providerV4Surface() throws {
        let provider = MockProviderV4()

        #expect(provider.specificationVersion == "v4")
        #expect(try provider.languageModel(modelId: "language").specificationVersion == "v4")
        #expect(try provider.embeddingModel(modelId: "embedding").modelId == "embedding")
        #expect(try provider.imageModel(modelId: "image").provider == "mock.image")
        #expect(try provider.transcriptionModel(modelId: "transcribe") == nil)
        #expect(try provider.speechModel(modelId: "speech") == nil)
        #expect(try provider.rerankingModel(modelId: "rerank") == nil)
        #expect(try provider.files() == nil)
        #expect(try provider.skills() == nil)
    }

    @Test("LanguageModelV4 prompt supports custom and reasoning-file parts")
    func languagePromptSupportsV4Parts() throws {
        let prompt: LanguageModelV4Prompt = [
            .assistant(
                content: [
                    .custom(.init(kind: "anthropic.thinking")),
                    .reasoningFile(.init(
                        data: .base64("QUJD"),
                        mediaType: "image/png"
                    )),
                    .file(.init(
                        data: .reference(["anthropic": "file-123"]),
                        mediaType: "application/pdf",
                        filename: "source.pdf"
                    )),
                    .toolResult(.init(
                        toolCallId: "call-1",
                        toolName: "lookup",
                        output: .content(value: [
                            .text(text: "ok", providerOptions: nil),
                            .file(
                                data: .text("inline"),
                                mediaType: "text/plain",
                                filename: "note.txt",
                                providerOptions: nil
                            ),
                            .custom(providerOptions: ["provider": ["flag": .bool(true)]])
                        ])
                    ))
                ],
                providerOptions: ["anthropic": ["cacheControl": .string("ephemeral")]]
            )
        ]

        let encoded = try JSONEncoder().encode(prompt)
        let decoded = try JSONDecoder().decode(LanguageModelV4Prompt.self, from: encoded)

        #expect(decoded == prompt)
    }

    @Test("LanguageModelV4 content supports custom and reasoning-file generated output")
    func languageGeneratedContentSupportsV4Parts() throws {
        let content: [LanguageModelV4Content] = [
            .custom(.init(kind: "openai.encrypted_reasoning", providerMetadata: ["openai": ["id": .string("c-1")]])),
            .reasoningFile(.init(mediaType: "image/png", data: .base64("QUJD"))),
            .file(.init(mediaType: "text/plain", data: .url(URL(string: "https://example.com/file.txt")!))),
            .toolApprovalRequest(.init(approvalId: "approval-1", toolCallId: "tool-1"))
        ]

        let encoded = try JSONEncoder().encode(content)
        let decoded = try JSONDecoder().decode([LanguageModelV4Content].self, from: encoded)

        #expect(decoded == content)
    }

    @Test("LanguageModelV4 call options include normalized reasoning effort")
    func languageCallOptionsExposeReasoningEffort() {
        let options = LanguageModelV4CallOptions(
            prompt: [.system(content: "Be concise", providerOptions: nil)],
            reasoning: .xhigh,
            providerOptions: ["openai": ["reasoningSummary": .string("detailed")]]
        )

        #expect(options.reasoning == .xhigh)
        #expect(options.providerOptions?["openai"]?["reasoningSummary"] == .string("detailed"))
    }

    @Test("non-language v4 call contracts carry shared v4 options and new video inputs")
    func nonLanguageContractsExposeV4Fields() {
        let embedding = EmbeddingModelV4CallOptions(
            values: ["a"],
            providerOptions: ["cohere": ["truncate": .string("END")]],
            headers: ["x-test": "1"]
        )
        let image = ImageModelV4CallOptions(
            prompt: "draw",
            n: 1,
            files: [.url(url: "https://example.com/in.png", providerOptions: nil)],
            providerOptions: ["openai": ["style": .string("vivid")]]
        )
        let video = VideoModelV4CallOptions(
            prompt: "animate",
            n: 1,
            frameImages: [
                .init(
                    image: .file(mediaType: "image/png", data: .base64("QUJD"), providerOptions: nil),
                    frameType: .firstFrame
                )
            ],
            inputReferences: [.url(url: "https://example.com/ref.png", providerOptions: nil)],
            generateAudio: true,
            providerOptions: ["fal": ["loop": .bool(true)]]
        )
        let rerank = RerankingModelV4Result(
            ranking: [.init(index: 0, relevanceScore: 0.9)],
            warnings: [.deprecated(setting: "topK", message: "Use topN.")]
        )

        #expect(embedding.providerOptions?["cohere"]?["truncate"] == .string("END"))
        #expect(image.providerOptions?["openai"]?["style"] == .string("vivid"))
        #expect(video.frameImages?.first?.frameType == .firstFrame)
        #expect(video.generateAudio == true)
        #expect(rerank.warnings == [.deprecated(setting: "topK", message: "Use topN.")])
    }
}

private struct MockProviderV4: ProviderV4 {
    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        MockLanguageModelV4(modelId: modelId)
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        MockEmbeddingModelV4(modelId: modelId)
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        MockImageModelV4(modelId: modelId)
    }
}

private struct MockLanguageModelV4: LanguageModelV4 {
    let provider = "mock.language"
    let modelId: String

    func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        LanguageModelV4GenerateResult(
            content: [.text(.init(text: "ok"))],
            finishReason: .init(unified: .stop),
            usage: .init()
        )
    }

    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        LanguageModelV4StreamResult(stream: AsyncThrowingStream { continuation in
            continuation.finish()
        })
    }
}

private struct MockEmbeddingModelV4: EmbeddingModelV4 {
    let provider = "mock.embedding"
    let modelId: String

    var maxEmbeddingsPerCall: Int? {
        get async throws { nil }
    }

    var supportsParallelCalls: Bool {
        get async throws { true }
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        EmbeddingModelV4Result(embeddings: [[0, 1]], warnings: [])
    }
}

private struct MockImageModelV4: ImageModelV4 {
    let provider = "mock.image"
    let modelId: String
    let maxImagesPerCall: ImageModelV4MaxImagesPerCall = .default

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        ImageModelV4GenerateResult(
            images: .base64(["QUJD"]),
            response: .init(timestamp: Date(timeIntervalSince1970: 0), modelId: modelId)
        )
    }
}
