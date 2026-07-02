import Foundation
import Testing
@testable import AISDKProvider
@testable import SwiftAISDK

@Suite("resolve model V4 adapters")
struct ResolveModelV4Tests {
    @Test("adapts a ProviderV3 through the ProviderV4 surface")
    func adaptsProviderV3ToProviderV4() async throws {
        let provider = AdapterProviderV3()
        let providerV4 = asProviderV4(provider)

        #expect(providerV4.specificationVersion == "v4")
        #expect(try providerV4.languageModel(modelId: "language").specificationVersion == "v4")
        #expect(try providerV4.embeddingModel(modelId: "embedding").specificationVersion == "v4")
        #expect(try providerV4.imageModel(modelId: "image").specificationVersion == "v4")
        #expect(try providerV4.transcriptionModel(modelId: "transcription")?.specificationVersion == "v4")
        #expect(try providerV4.speechModel(modelId: "speech")?.specificationVersion == "v4")
        #expect(try providerV4.rerankingModel(modelId: "rerank")?.specificationVersion == "v4")
        #expect(try providerV4.files() == nil)
        #expect(try providerV4.skills() == nil)
    }

    @Test("resolveLanguageModelV4 accepts a direct V4 language model")
    func resolveLanguageModelV4AcceptsDirectV4Model() async throws {
        let directModel = MockLanguageModelV4(
            provider: "direct-provider",
            modelId: "direct-v4",
            doGenerate: .function { options in
                #expect(options.reasoning == .high)
                return LanguageModelV4GenerateResult(
                    content: [.text(LanguageModelV4Text(text: "direct v4"))],
                    finishReason: LanguageModelV4FinishReason(unified: .stop),
                    usage: LanguageModelV4Usage(
                        inputTokens: .init(total: 1),
                        outputTokens: .init(total: 2)
                    ),
                    warnings: [.deprecated(setting: "legacy-option", message: "use v4")]
                )
            }
        )

        let resolved = try resolveLanguageModelV4(.v4(directModel))

        #expect(resolved.provider == "direct-provider")
        #expect(resolved.modelId == "direct-v4")
        #expect(resolved.specificationVersion == "v4")

        let result = try await resolved.doGenerate(
            options: LanguageModelV4CallOptions(prompt: [], reasoning: .high)
        )

        #expect(result.warnings == [.deprecated(setting: "legacy-option", message: "use v4")])
        #expect(directModel.doGenerateCalls.count == 1)
        #expect(directModel.doGenerateCalls.first?.reasoning == .high)

        guard case .text(let text) = result.content.first else {
            Issue.record("Expected direct V4 generated text content")
            return
        }
        #expect(text.text == "direct v4")
    }

    @Test("resolveLanguageModelV4 resolves string IDs through a V4 global provider")
    func resolveLanguageModelV4ResolvesStringThroughV4Provider() throws {
        let model = MockLanguageModelV4(provider: "v4-global", modelId: "actual-v4")
        let provider = customProviderV4(languageModels: ["requested": model])

        let resolved = try withGlobalProviderV4(provider) {
            try resolveLanguageModelV4(.string("requested"))
        }

        #expect(resolved.provider == "v4-global")
        #expect(resolved.modelId == "actual-v4")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("resolveLanguageModelV4 adapts legacy global providers for string IDs")
    func resolveLanguageModelV4AdaptsLegacyGlobalProviderForString() throws {
        let provider = AdapterProviderV3()

        let resolved = try withGlobalProvider(provider) {
            try resolveLanguageModelV4(.string("language"))
        }

        #expect(resolved.provider == "test-provider")
        #expect(resolved.modelId == "language")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("resolveEmbeddingModelV4 resolves string IDs through ProviderV4 embeddingModel")
    func resolveEmbeddingModelV4ResolvesStringThroughV4Provider() throws {
        let embeddingModel = RecordingEmbeddingModelV4(provider: "v4-global", modelId: "actual-embedding")
        let provider = customProviderV4(embeddingModels: ["requested": embeddingModel])

        let resolved = try withGlobalProviderV4(provider) {
            try resolveEmbeddingModelV4(.string("requested"))
        }

        #expect(resolved.provider == "v4-global")
        #expect(resolved.modelId == "actual-embedding")
        #expect(resolved.specificationVersion == "v4")
    }

    @Test("resolveLanguageModelV4 converts V4 options to V3 and V3 results back to V4")
    func languageAdapterConvertsGenerateAndStream() async throws {
        let baseModel = RecordingLanguageModelV3()
        let model = try resolveLanguageModelV4(.v3(baseModel))

        let generated = try await model.doGenerate(
            options: LanguageModelV4CallOptions(
                prompt: [
                    .user(
                        content: [
                            .text(LanguageModelV4TextPart(text: "hello")),
                            .file(
                                LanguageModelV4FilePart(
                                    data: .text("plain text"),
                                    mediaType: "text/plain",
                                    filename: "note.txt"
                                )
                            )
                        ],
                        providerOptions: ["provider": ["flag": true]]
                    )
                ],
                maxOutputTokens: 20,
                responseFormat: .json(schema: ["type": "object"], name: "answer", description: nil),
                tools: [
                    .function(
                        LanguageModelV4FunctionTool(
                            name: "lookup",
                            inputSchema: ["type": "object"],
                            inputExamples: [LanguageModelV4ToolInputExample(input: ["query": "swift"])],
                            strict: true
                        )
                    )
                ],
                toolChoice: .tool(toolName: "lookup")
            )
        )

        #expect(generated.finishReason == LanguageModelV4FinishReason(unified: .length, raw: "length"))
        #expect(generated.usage.inputTokens.total == 3)
        #expect(generated.usage.outputTokens.reasoning == 1)
        #expect(generated.warnings == [.unsupported(feature: "temperature", details: "ignored")])

        guard case .text(let text) = generated.content.first else {
            Issue.record("Expected generated text content")
            return
        }
        #expect(text.text == "generated")

        guard let lastOptions = baseModel.lastGenerateOptions else {
            Issue.record("Expected V3 generate options to be captured")
            return
        }
        #expect(lastOptions.maxOutputTokens == 20)

        guard case .user(let content, let providerOptions) = lastOptions.prompt.first,
              case .file(let file) = content.last else {
            Issue.record("Expected V4 text file input to be converted to a V3 file part")
            return
        }
        #expect(providerOptions?["provider"]?["flag"] == .bool(true))
        #expect(file.filename == "note.txt")
        #expect(file.data == .data(Data("plain text".utf8)))

        let streamResult = try await model.doStream(options: LanguageModelV4CallOptions(prompt: []))
        var streamParts: [LanguageModelV4StreamPart] = []
        for try await part in streamResult.stream {
            streamParts.append(part)
        }

        #expect(streamParts.count == 3)
        #expect(streamParts.first == .textStart(id: "text-1", providerMetadata: nil))
        #expect(streamParts.last == .finish(
            finishReason: LanguageModelV4FinishReason(unified: .stop),
            usage: LanguageModelV4Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 2)),
            providerMetadata: nil
        ))
    }

    @Test("language V4 adapter rejects V4-only inputs that a V3 model cannot represent")
    func languageAdapterRejectsUnsupportedV4Inputs() async throws {
        let model = asLanguageModelV4(RecordingLanguageModelV3())

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(
                options: LanguageModelV4CallOptions(prompt: [], reasoning: .high)
            )
        }

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(
                options: LanguageModelV4CallOptions(
                    prompt: [
                        .assistant(
                            content: [.custom(LanguageModelV4CustomPart(kind: "provider.custom"))],
                            providerOptions: nil
                        )
                    ]
                )
            )
        }
    }

    @Test("adapts non-language V3 models through V4 calls without losing core fields")
    func adaptsNonLanguageModelsToV4() async throws {
        let embeddingModel = asEmbeddingModelV4(RecordingEmbeddingModelV3())
        let embedding = try await embeddingModel.doEmbed(
            options: EmbeddingModelV4CallOptions(values: ["one", "two"])
        )
        #expect(embedding.embeddings == [[1, 2], [3, 4]])
        #expect(embedding.usage == EmbeddingModelV4Usage(tokens: 9))
        #expect(embedding.warnings == [.compatibility(feature: "batch", details: "v3")])

        let imageBase = RecordingImageModelV3()
        let image = try await asImageModelV4(imageBase).doGenerate(
            options: ImageModelV4CallOptions(
                prompt: "draw",
                n: 1,
                files: [.file(mediaType: "image/png", data: .base64("input"), providerOptions: nil)]
            )
        )
        #expect(image.usage == ImageModelV4Usage(inputTokens: 1, outputTokens: 2, totalTokens: 3))
        #expect(image.providerMetadata?["images"]?.images == [.string("metadata")])
        guard case .base64(let images) = image.images else {
            Issue.record("Expected base64 image output")
            return
        }
        #expect(images == ["image-data"])
        guard case .file(_, let imageFileData, _) = imageBase.lastOptions?.files?.first else {
            Issue.record("Expected image V4 file input to be converted to V3")
            return
        }
        #expect(imageFileData == .base64("input"))

        let reranking = try await asRerankingModelV4(RecordingRerankingModelV3()).doRerank(
            options: RerankingModelV4CallOptions(documents: .text(values: ["a", "b"]), query: "b", topN: 1)
        )
        #expect(reranking.ranking == [RerankingModelV4Ranking(index: 1, relevanceScore: 0.9)])

        let speech = try await asSpeechModelV4(RecordingSpeechModelV3()).doGenerate(
            options: SpeechModelV4CallOptions(text: "hello", voice: "voice-a")
        )
        #expect(speech.audio == .binary(Data([1, 2, 3])))
        #expect(speech.response.modelId == "speech-model")

        let transcription = try await asTranscriptionModelV4(RecordingTranscriptionModelV3()).doGenerate(
            options: TranscriptionModelV4CallOptions(audio: .base64("audio"), mediaType: "audio/wav")
        )
        #expect(transcription.text == "transcript")
        #expect(transcription.segments == [
            TranscriptionModelV4Result.Segment(text: "transcript", startSecond: 0, endSecond: 1)
        ])

        let videoBase = RecordingVideoModelV3()
        let video = try await asVideoModelV4(videoBase).doGenerate(
            options: VideoModelV4CallOptions(
                prompt: "video",
                n: 1,
                image: .file(mediaType: "image/png", data: .binary(Data([9])), providerOptions: nil)
            )
        )
        #expect(video.videos == [.url(url: "https://example.com/video.mp4", mediaType: "video/mp4")])
        guard case .file(_, let videoFileData, _) = videoBase.lastOptions?.image else {
            Issue.record("Expected video V4 image input to be converted to V3")
            return
        }
        #expect(videoFileData == .binary(Data([9])))
    }

    @Test("video adapter rejects V4-only options on V3 models")
    func videoAdapterRejectsV4OnlyOptions() async throws {
        let model = asVideoModelV4(RecordingVideoModelV3())

        await #expect(throws: UnsupportedFunctionalityError.self) {
            _ = try await model.doGenerate(
                options: VideoModelV4CallOptions(
                    prompt: "video",
                    n: 1,
                    frameImages: [
                        VideoModelV4FrameImage(
                            image: .url(url: "https://example.com/frame.png", providerOptions: nil),
                            frameType: .firstFrame
                        )
                    ]
                )
            )
        }
    }
}

private final class AdapterProviderV3: ProviderV3, @unchecked Sendable {
    func languageModel(modelId: String) throws -> any LanguageModelV3 {
        RecordingLanguageModelV3(modelId: modelId)
    }

    func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        RecordingEmbeddingModelV3(modelId: modelId)
    }

    func imageModel(modelId: String) throws -> any ImageModelV3 {
        RecordingImageModelV3(modelId: modelId)
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV3)? {
        RecordingTranscriptionModelV3(modelId: modelId)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV3)? {
        RecordingSpeechModelV3(modelId: modelId)
    }

    func rerankingModel(modelId: String) throws -> (any RerankingModelV3)? {
        RecordingRerankingModelV3(modelId: modelId)
    }
}

private final class RecordingLanguageModelV3: LanguageModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String
    var lastGenerateOptions: LanguageModelV3CallOptions?
    var lastStreamOptions: LanguageModelV3CallOptions?

    init(modelId: String = "language-model") {
        self.modelId = modelId
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        lastGenerateOptions = options
        return LanguageModelV3GenerateResult(
            content: [
                .text(LanguageModelV3Text(text: "generated")),
                .file(LanguageModelV3File(mediaType: "text/plain", data: .base64("ZmlsZQ==")))
            ],
            finishReason: LanguageModelV3FinishReason(unified: .length, raw: "length"),
            usage: LanguageModelV3Usage(
                inputTokens: .init(total: 3, noCache: 2, cacheRead: 1),
                outputTokens: .init(total: 4, text: 3, reasoning: 1)
            ),
            warnings: [.unsupported(feature: "temperature", details: "ignored")]
        )
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        lastStreamOptions = options
        return LanguageModelV3StreamResult(
            stream: AsyncThrowingStream { continuation in
                continuation.yield(.textStart(id: "text-1", providerMetadata: nil))
                continuation.yield(.textDelta(id: "text-1", delta: "hi", providerMetadata: nil))
                continuation.yield(.finish(
                    finishReason: LanguageModelV3FinishReason(unified: .stop),
                    usage: LanguageModelV3Usage(
                        inputTokens: .init(total: 1),
                        outputTokens: .init(total: 2)
                    ),
                    providerMetadata: nil
                ))
                continuation.finish()
            }
        )
    }
}

private final class RecordingEmbeddingModelV3: EmbeddingModelV3, @unchecked Sendable {
    typealias VALUE = String

    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String

    init(modelId: String = "embedding-model") {
        self.modelId = modelId
    }

    var maxEmbeddingsPerCall: Int? {
        get async throws { 2 }
    }

    var supportsParallelCalls: Bool {
        get async throws { true }
    }

    func doEmbed(options: EmbeddingModelV3DoEmbedOptions<String>) async throws -> EmbeddingModelV3DoEmbedResult {
        #expect(options.values == ["one", "two"])
        return EmbeddingModelV3DoEmbedResult(
            embeddings: [[1, 2], [3, 4]],
            usage: EmbeddingModelV3Usage(tokens: 9),
            response: EmbeddingModelV3ResponseInfo(headers: ["x-test": "yes"], body: nil),
            warnings: [.compatibility(feature: "batch", details: "v3")]
        )
    }
}

private final class RecordingEmbeddingModelV4: EmbeddingModelV4, @unchecked Sendable {
    let specificationVersion = "v4"
    let provider: String
    let modelId: String

    init(provider: String = "test-provider", modelId: String = "embedding-model") {
        self.provider = provider
        self.modelId = modelId
    }

    var maxEmbeddingsPerCall: Int? {
        get async throws { 4 }
    }

    var supportsParallelCalls: Bool {
        get async throws { true }
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        EmbeddingModelV4Result(
            embeddings: options.values.map { _ in [1, 2, 3] },
            usage: EmbeddingModelV4Usage(tokens: options.values.count)
        )
    }
}

private final class RecordingImageModelV3: ImageModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String
    let maxImagesPerCall: ImageModelV3MaxImagesPerCall = .value(2)
    var lastOptions: ImageModelV3CallOptions?

    init(modelId: String = "image-model") {
        self.modelId = modelId
    }

    func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        lastOptions = options
        return ImageModelV3GenerateResult(
            images: .base64(["image-data"]),
            warnings: [.other(message: "image warning")],
            providerMetadata: ["images": ImageModelV3ProviderMetadataValue(images: [.string("metadata")])],
            response: ImageModelV3ResponseInfo(timestamp: Date(timeIntervalSince1970: 1), modelId: modelId),
            usage: ImageModelV3Usage(inputTokens: 1, outputTokens: 2, totalTokens: 3)
        )
    }
}

private final class RecordingRerankingModelV3: RerankingModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String

    init(modelId: String = "reranking-model") {
        self.modelId = modelId
    }

    func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        #expect(options.query == "b")
        #expect(options.topN == 1)
        return RerankingModelV3DoRerankResult(
            ranking: [RerankingModelV3Ranking(index: 1, relevanceScore: 0.9)]
        )
    }
}

private final class RecordingSpeechModelV3: SpeechModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String

    init(modelId: String = "speech-model") {
        self.modelId = modelId
    }

    func doGenerate(options: SpeechModelV3CallOptions) async throws -> SpeechModelV3Result {
        #expect(options.text == "hello")
        #expect(options.voice == "voice-a")
        return SpeechModelV3Result(
            audio: .binary(Data([1, 2, 3])),
            response: SpeechModelV3Result.ResponseInfo(
                timestamp: Date(timeIntervalSince1970: 2),
                modelId: modelId
            )
        )
    }
}

private final class RecordingTranscriptionModelV3: TranscriptionModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String

    init(modelId: String = "transcription-model") {
        self.modelId = modelId
    }

    func doGenerate(options: TranscriptionModelV3CallOptions) async throws -> TranscriptionModelV3Result {
        #expect(options.audio == .base64("audio"))
        #expect(options.mediaType == "audio/wav")
        return TranscriptionModelV3Result(
            text: "transcript",
            segments: [.init(text: "transcript", startSecond: 0, endSecond: 1)],
            response: TranscriptionModelV3Result.ResponseInfo(
                timestamp: Date(timeIntervalSince1970: 3),
                modelId: modelId
            )
        )
    }
}

private final class RecordingVideoModelV3: VideoModelV3, @unchecked Sendable {
    let specificationVersion = "v3"
    let provider = "test-provider"
    let modelId: String
    let maxVideosPerCall: VideoModelV3MaxVideosPerCall = .value(1)
    var lastOptions: VideoModelV3CallOptions?

    init(modelId: String = "video-model") {
        self.modelId = modelId
    }

    func doGenerate(options: VideoModelV3CallOptions) async throws -> VideoModelV3GenerateResult {
        lastOptions = options
        return VideoModelV3GenerateResult(
            videos: [.url(url: "https://example.com/video.mp4", mediaType: "video/mp4")],
            response: VideoModelV3ResponseInfo(
                timestamp: Date(timeIntervalSince1970: 4),
                modelId: modelId
            )
        )
    }
}
