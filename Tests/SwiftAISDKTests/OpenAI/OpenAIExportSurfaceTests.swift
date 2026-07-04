import AISDKProvider
import OpenAIProvider
import Testing

@Suite("OpenAI public export surface")
struct OpenAIExportSurfaceTests {
    @Test("index-exported option aliases are public")
    func indexExportedOptionAliasesArePublic() {
        let responses: OpenAILanguageModelResponsesOptions = .init(
            promptCacheRetention: "24h",
            serviceTier: "default",
            textVerbosity: "medium"
        )
        #expect(responses.serviceTier == "default")

        let chat: OpenAILanguageModelChatOptions = .init(
            logitBias: ["42": -1],
            logprobs: .number(2),
            parallelToolCalls: false,
            user: "user-1",
            reasoningEffort: .xhigh,
            maxCompletionTokens: 128,
            store: true,
            metadata: ["team": "sdk"],
            prediction: ["type": .string("content")],
            serviceTier: .default,
            strictJsonSchema: false,
            textVerbosity: .high,
            promptCacheKey: "cache-key",
            promptCacheRetention: .twentyFourHours,
            safetyIdentifier: "safe-user",
            systemMessageMode: .developer,
            forceReasoning: true
        )
        let deprecatedChat: OpenAIChatLanguageModelOptions = chat
        #expect(deprecatedChat.reasoningEffort == .xhigh)
        #expect(deprecatedChat.prediction?["type"] == .string("content"))

        let completion: OpenAILanguageModelCompletionOptions = .init(
            echo: true,
            logitBias: ["50256": -100],
            suffix: "done",
            user: "user-1",
            logprobs: .bool(true)
        )
        #expect(completion.logprobs == .bool(true))

        let embedding: OpenAIEmbeddingModelOptions = .init(dimensions: 1536, user: "user-1")
        #expect(embedding.dimensions == 1536)

        let image: OpenAIImageModelOptions = .init(quality: "high", outputFormat: "png", outputCompression: 80)
        #expect(image.outputFormat == "png")

        let generation: OpenAIImageModelGenerationOptions = .init(style: "vivid", moderation: "low")
        #expect(generation.style == "vivid")

        let edit: OpenAIImageModelEditOptions = .init(inputFidelity: "high")
        #expect(edit.inputFidelity == "high")

        let speech: OpenAISpeechModelOptions = .init(instructions: "Speak clearly", speed: 1.25)
        #expect(speech.speed == 1.25)

        let transcription: OpenAITranscriptionModelOptions = .init(
            include: ["logprobs"],
            language: "en",
            prompt: "Names",
            temperature: 0,
            timestampGranularities: ["segment"],
            streaming: .init(delay: "low", include: ["item.input_audio_transcription.logprobs"])
        )
        #expect(transcription.streaming?.delay == "low")

        let files = OpenAIFilesOptions(purpose: "assistants", expiresAfter: 3600)
        #expect(files.expiresAfter == 3600)
    }

    @Test("realtime aliases version and metadata wrappers are public")
    func realtimeAliasesVersionAndMetadataWrappersArePublic() {
        #expect(VERSION == OPENAI_VERSION)

        let config = Experimental_OpenAIRealtimeModelConfig(
            provider: "openai.realtime",
            baseURL: "https://api.openai.com/v1",
            headers: { [:] }
        )
        let model: Experimental_OpenAIRealtimeModel = OpenAIRealtimeModel(modelId: "gpt-realtime", config: config)
        #expect(model.specificationVersion == "v4")

        let responseMetadata = OpenaiResponsesProviderMetadata(
            openai: .init(responseId: "resp-1", logprobs: [.object(["token": .string("Hi")])], serviceTier: "auto")
        )
        #expect(responseMetadata.openai.responseId == "resp-1")

        let reasoningMetadata = OpenaiResponsesReasoningProviderMetadata(
            openai: .init(itemId: "rs_1", reasoningEncryptedContent: "encrypted")
        )
        #expect(reasoningMetadata.openai.reasoningEncryptedContent == "encrypted")

        let compactionMetadata = OpenaiResponsesCompactionProviderMetadata(
            openai: .init(itemId: "cmp_1", encryptedContent: "encrypted")
        )
        #expect(compactionMetadata.openai.type == "compaction")

        let textMetadata = OpenaiResponsesTextProviderMetadata(
            openai: .init(itemId: "msg_1", phase: .commentary, annotations: [.object(["type": .string("file_citation")])])
        )
        #expect(textMetadata.openai.phase == .commentary)

        let sourceDocumentMetadata = OpenaiResponsesSourceDocumentProviderMetadata(
            openai: .containerFileCitation(fileId: "file_1", containerId: "container_1")
        )
        #expect(sourceDocumentMetadata.openai.type == "container_file_citation")
    }
}
