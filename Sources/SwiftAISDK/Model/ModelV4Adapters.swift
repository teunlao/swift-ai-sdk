import Foundation
import AISDKProvider

/**
 Swift adapters for resolving legacy provider/model contracts through the V4 surface.

 Port direction:
 - `@ai-sdk/ai/src/model/as-provider-v4.ts`
 - `@ai-sdk/ai/src/model/as-language-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-embedding-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-image-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-reranking-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-speech-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-transcription-model-v4.ts`
 - `@ai-sdk/ai/src/model/as-video-model-v4.ts`
 */

// MARK: - Public V4 Adapter Entry Points

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asProviderV4(_ provider: any ProviderV4) -> any ProviderV4 {
    provider
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asProviderV4(_ provider: any ProviderV3) -> any ProviderV4 {
    ProviderV3ToV4Adapter(wrapping: provider)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asLanguageModelV4(_ model: any LanguageModelV4) -> any LanguageModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asLanguageModelV4(_ model: any LanguageModelV3) -> any LanguageModelV4 {
    LanguageModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asEmbeddingModelV4(_ model: any EmbeddingModelV4) -> any EmbeddingModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asEmbeddingModelV4(_ model: any EmbeddingModelV3<String>) -> any EmbeddingModelV4 {
    EmbeddingModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asImageModelV4(_ model: any ImageModelV4) -> any ImageModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asImageModelV4(_ model: any ImageModelV3) -> any ImageModelV4 {
    ImageModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asImageModelV4(_ model: any ImageModelV2) -> any ImageModelV4 {
    ImageModelV2ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asRerankingModelV4(_ model: any RerankingModelV4) -> any RerankingModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asRerankingModelV4(_ model: any RerankingModelV3) -> any RerankingModelV4 {
    RerankingModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asSpeechModelV4(_ model: any SpeechModelV4) -> any SpeechModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asSpeechModelV4(_ model: any SpeechModelV3) -> any SpeechModelV4 {
    SpeechModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asSpeechModelV4(_ model: any SpeechModelV2) -> any SpeechModelV4 {
    SpeechModelV2ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asTranscriptionModelV4(_ model: any TranscriptionModelV4) -> any TranscriptionModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asTranscriptionModelV4(_ model: any TranscriptionModelV3) -> any TranscriptionModelV4 {
    TranscriptionModelV3ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asTranscriptionModelV4(_ model: any TranscriptionModelV2) -> any TranscriptionModelV4 {
    TranscriptionModelV2ToV4Adapter(wrapping: model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asVideoModelV4(_ model: any VideoModelV4) -> any VideoModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func asVideoModelV4(_ model: any VideoModelV3) -> any VideoModelV4 {
    VideoModelV3ToV4Adapter(wrapping: model)
}

// MARK: - Public V4 Resolution Helpers

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveLanguageModelV4(_ model: LanguageModel) throws -> any LanguageModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .string(let id):
        return try _resolveGlobalProviderV4(modelId: id, modelType: .languageModel)
            .languageModel(modelId: id)
    case .v3, .v2:
        return try asLanguageModelV4(resolveLanguageModel(model))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveEmbeddingModelV4(_ model: EmbeddingModel) throws -> any EmbeddingModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .string(let id):
        return try _resolveGlobalProviderV4(modelId: id, modelType: .textEmbeddingModel)
            .embeddingModel(modelId: id)
    case .v3, .v2:
        return try asEmbeddingModelV4(resolveEmbeddingModel(model))
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveImageModelV4(_ model: any ImageModelV3) -> any ImageModelV4 {
    asImageModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveImageModelV4(_ model: any ImageModelV4) -> any ImageModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveImageModelV4(_ model: any ImageModelV2) -> any ImageModelV4 {
    asImageModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveImageModelV4(_ model: ImageModel) throws -> any ImageModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .v3(let model):
        return asImageModelV4(model)
    case .v2(let model):
        return asImageModelV4(model)
    case .string(let id):
        return try _resolveGlobalProviderV4(modelId: id, modelType: .imageModel)
            .imageModel(modelId: id)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveRerankingModelV4(_ model: any RerankingModelV3) -> any RerankingModelV4 {
    asRerankingModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveRerankingModelV4(_ model: any RerankingModelV4) -> any RerankingModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveRerankingModelV4(_ model: RerankingModel) throws -> any RerankingModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .v3(let model):
        return asRerankingModelV4(model)
    case .string(let id):
        let provider = try _resolveGlobalProviderV4(modelId: id, modelType: .rerankingModel)
        guard let model = try provider.rerankingModel(modelId: id) else {
            throw NoSuchModelError(modelId: id, modelType: .rerankingModel)
        }
        return model
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveSpeechModelV4(_ model: any SpeechModelV3) -> any SpeechModelV4 {
    asSpeechModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveSpeechModelV4(_ model: any SpeechModelV4) -> any SpeechModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveSpeechModelV4(_ model: any SpeechModelV2) -> any SpeechModelV4 {
    asSpeechModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveSpeechModelV4(_ model: SpeechModel) throws -> any SpeechModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .v3(let model):
        return asSpeechModelV4(model)
    case .v2(let model):
        return asSpeechModelV4(model)
    case .string(let id):
        let provider = try _resolveGlobalProviderV4(modelId: id, modelType: .speechModel)
        guard let model = try provider.speechModel(modelId: id) else {
            throw NoSuchModelError(modelId: id, modelType: .speechModel)
        }
        return model
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveTranscriptionModelV4(_ model: any TranscriptionModelV3) -> any TranscriptionModelV4 {
    asTranscriptionModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveTranscriptionModelV4(_ model: any TranscriptionModelV4) -> any TranscriptionModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveTranscriptionModelV4(_ model: any TranscriptionModelV2) -> any TranscriptionModelV4 {
    asTranscriptionModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveTranscriptionModelV4(_ model: TranscriptionModel) throws -> any TranscriptionModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .v3(let model):
        return asTranscriptionModelV4(model)
    case .v2(let model):
        return asTranscriptionModelV4(model)
    case .string(let id):
        let provider = try _resolveGlobalProviderV4(modelId: id, modelType: .transcriptionModel)
        guard let model = try provider.transcriptionModel(modelId: id) else {
            throw NoSuchModelError(modelId: id, modelType: .transcriptionModel)
        }
        return model
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveVideoModelV4(_ model: any VideoModelV3) -> any VideoModelV4 {
    asVideoModelV4(model)
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveVideoModelV4(_ model: any VideoModelV4) -> any VideoModelV4 {
    model
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
public func resolveVideoModelV4(_ model: VideoModel) throws -> any VideoModelV4 {
    switch model {
    case .v4(let model):
        return model
    case .v3(let model):
        return asVideoModelV4(model)
    case .string(let id):
        return try _resolveGlobalVideoModelV4(modelId: id)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _resolveGlobalVideoModelV4(modelId id: String) throws -> any VideoModelV4 {
    let disabled = disableGlobalProviderForStringResolution || _ResolveModelContext.disableGlobalProvider
    let provider = _ResolveModelContext.overrideProvider ?? (disabled ? nil : globalDefaultProvider)

    guard let provider else {
        throw NoSuchProviderError(
            modelId: id,
            modelType: .videoModel,
            providerId: "default",
            availableProviders: [],
            message: "No global default provider with video model support set. Set `globalDefaultProvider` before resolving string video model IDs."
        )
    }

    guard let model = try provider.videoModel(modelId: id) else {
        throw NoSuchModelError(modelId: id, modelType: .videoModel)
    }

    return asVideoModelV4(model)
}

// MARK: - Provider Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class ProviderV3ToV4Adapter: ProviderV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let provider: any ProviderV3

    init(wrapping provider: any ProviderV3) {
        self.provider = provider
    }

    func languageModel(modelId: String) throws -> any LanguageModelV4 {
        try asLanguageModelV4(provider.languageModel(modelId: modelId))
    }

    func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 {
        try asEmbeddingModelV4(provider.textEmbeddingModel(modelId: modelId))
    }

    func imageModel(modelId: String) throws -> any ImageModelV4 {
        try asImageModelV4(provider.imageModel(modelId: modelId))
    }

    func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? {
        try provider.transcriptionModel(modelId: modelId).map(asTranscriptionModelV4)
    }

    func speechModel(modelId: String) throws -> (any SpeechModelV4)? {
        try provider.speechModel(modelId: modelId).map(asSpeechModelV4)
    }

    func rerankingModel(modelId: String) throws -> (any RerankingModelV4)? {
        try provider.rerankingModel(modelId: modelId).map(asRerankingModelV4)
    }

    func files() throws -> (any FilesV4)? {
        nil
    }

    func skills() throws -> (any SkillsV4)? {
        nil
    }
}

// MARK: - Language Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class LanguageModelV3ToV4Adapter: LanguageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any LanguageModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await model.supportedUrls }
    }

    init(wrapping model: any LanguageModelV3) {
        self.model = model
    }

    func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        let result = try await model.doGenerate(options: try _convertLanguageModelV4CallOptionsToV3(options))
        return try _convertLanguageModelV3GenerateResultToV4(result)
    }

    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await model.doStream(options: try _convertLanguageModelV4CallOptionsToV3(options))
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try _convertLanguageModelV3StreamPartToV4(part))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }

        return LanguageModelV4StreamResult(
            stream: stream,
            request: result.request.map(_convertLanguageModelV3RequestInfoToV4),
            response: result.response.map(_convertLanguageModelV3StreamResponseInfoToV4)
        )
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private func _convertLanguageModelV4CallOptionsToV3(_ options: LanguageModelV4CallOptions) throws -> LanguageModelV3CallOptions {
    if options.reasoning != nil {
        throw UnsupportedFunctionalityError(functionality: "language model v4 reasoning option on v3 model")
    }

    return LanguageModelV3CallOptions(
        prompt: try options.prompt.map(_convertLanguageModelV4MessageToV3),
        maxOutputTokens: options.maxOutputTokens,
        temperature: options.temperature,
        stopSequences: options.stopSequences,
        topP: options.topP,
        topK: options.topK,
        presencePenalty: options.presencePenalty,
        frequencyPenalty: options.frequencyPenalty,
        responseFormat: options.responseFormat.map(_convertLanguageModelV4ResponseFormatToV3),
        seed: options.seed,
        tools: try options.tools?.map(_convertLanguageModelV4ToolToV3),
        toolChoice: options.toolChoice.map(_convertLanguageModelV4ToolChoiceToV3),
        includeRawChunks: options.includeRawChunks,
        abortSignal: options.abortSignal,
        headers: options.headers,
        providerOptions: options.providerOptions
    )
}

private func _convertLanguageModelV4ResponseFormatToV3(_ value: LanguageModelV4ResponseFormat) -> LanguageModelV3ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func _convertLanguageModelV4ToolChoiceToV3(_ value: LanguageModelV4ToolChoice) -> LanguageModelV3ToolChoice {
    switch value {
    case .auto:
        return .auto
    case .none:
        return .none
    case .required:
        return .required
    case .tool(let toolName):
        return .tool(toolName: toolName)
    }
}

private func _convertLanguageModelV4ToolToV3(_ value: LanguageModelV4Tool) throws -> LanguageModelV3Tool {
    switch value {
    case .function(let tool):
        return .function(
            LanguageModelV3FunctionTool(
                name: tool.name,
                inputSchema: tool.inputSchema,
                inputExamples: tool.inputExamples?.map { LanguageModelV3ToolInputExample(input: $0.input) },
                description: tool.description,
                strict: tool.strict,
                providerOptions: tool.providerOptions
            )
        )
    case .provider(let tool):
        return .provider(LanguageModelV3ProviderTool(id: tool.id, name: tool.name, args: tool.args))
    }
}

private func _convertLanguageModelV4MessageToV3(_ value: LanguageModelV4Message) throws -> LanguageModelV3Message {
    switch value {
    case let .system(content, providerOptions):
        return .system(content: content, providerOptions: providerOptions)
    case let .user(content, providerOptions):
        return .user(content: try content.map(_convertLanguageModelV4UserMessagePartToV3), providerOptions: providerOptions)
    case let .assistant(content, providerOptions):
        return .assistant(content: try content.map(_convertLanguageModelV4MessagePartToV3), providerOptions: providerOptions)
    case let .tool(content, providerOptions):
        return .tool(content: try content.map(_convertLanguageModelV4ToolMessagePartToV3), providerOptions: providerOptions)
    }
}

private func _convertLanguageModelV4UserMessagePartToV3(_ value: LanguageModelV4UserMessagePart) throws -> LanguageModelV3UserMessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(
            LanguageModelV3FilePart(
                data: try _convertSharedV4FileDataToLanguageModelV3DataContent(part.data),
                mediaType: part.mediaType,
                filename: part.filename,
                providerOptions: part.providerOptions
            )
        )
    }
}

private func _convertLanguageModelV4MessagePartToV3(_ value: LanguageModelV4MessagePart) throws -> LanguageModelV3MessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(
            LanguageModelV3FilePart(
                data: try _convertSharedV4FileDataToLanguageModelV3DataContent(part.data),
                mediaType: part.mediaType,
                filename: part.filename,
                providerOptions: part.providerOptions
            )
        )
    case .reasoning(let part):
        return .reasoning(LanguageModelV3ReasoningPart(text: part.text, providerOptions: part.providerOptions))
    case .toolCall(let part):
        return .toolCall(
            LanguageModelV3ToolCallPart(
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                input: part.input,
                providerExecuted: part.providerExecuted,
                providerOptions: part.providerOptions
            )
        )
    case .toolResult(let part):
        return .toolResult(
            LanguageModelV3ToolResultPart(
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                output: try _convertLanguageModelV4ToolResultOutputToV3(part.output),
                providerOptions: part.providerOptions
            )
        )
    case .custom:
        throw UnsupportedFunctionalityError(functionality: "language model v4 custom prompt parts on v3 model")
    case .reasoningFile:
        throw UnsupportedFunctionalityError(functionality: "language model v4 reasoning-file prompt parts on v3 model")
    }
}

private func _convertLanguageModelV4ToolMessagePartToV3(_ value: LanguageModelV4ToolMessagePart) throws -> LanguageModelV3ToolMessagePart {
    switch value {
    case .toolResult(let part):
        return .toolResult(
            LanguageModelV3ToolResultPart(
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                output: try _convertLanguageModelV4ToolResultOutputToV3(part.output),
                providerOptions: part.providerOptions
            )
        )
    case .toolApprovalResponse(let part):
        return .toolApprovalResponse(
            LanguageModelV3ToolApprovalResponsePart(
                approvalId: part.approvalId,
                approved: part.approved,
                reason: part.reason,
                providerOptions: part.providerOptions
            )
        )
    }
}

private func _convertLanguageModelV4ToolResultOutputToV3(_ value: LanguageModelV4ToolResultOutput) throws -> LanguageModelV3ToolResultOutput {
    switch value {
    case let .text(value, providerOptions):
        return .text(value: value, providerOptions: providerOptions)
    case let .json(value, providerOptions):
        return .json(value: value, providerOptions: providerOptions)
    case let .executionDenied(reason, providerOptions):
        return .executionDenied(reason: reason, providerOptions: providerOptions)
    case let .errorText(value, providerOptions):
        return .errorText(value: value, providerOptions: providerOptions)
    case let .errorJson(value, providerOptions):
        return .errorJson(value: value, providerOptions: providerOptions)
    case .content(let value):
        return .content(value: try value.map(_convertLanguageModelV4ToolResultContentPartToV3))
    }
}

private func _convertLanguageModelV4ToolResultContentPartToV3(
    _ value: LanguageModelV4ToolResultContentPart
) throws -> LanguageModelV3ToolResultContentPart {
    switch value {
    case let .text(text, providerOptions):
        if providerOptions != nil {
            throw UnsupportedFunctionalityError(functionality: "tool result text providerOptions on v3 model")
        }
        return .text(text: text)
    case let .file(data, mediaType, _, providerOptions):
        if providerOptions != nil {
            throw UnsupportedFunctionalityError(functionality: "tool result file providerOptions on v3 model")
        }
        return .media(data: try _convertSharedV4FileDataToBase64String(data), mediaType: mediaType)
    case .custom:
        throw UnsupportedFunctionalityError(functionality: "tool result custom content on v3 model")
    }
}

private func _convertSharedV4FileDataToLanguageModelV3DataContent(_ value: SharedV4FileData) throws -> LanguageModelV3DataContent {
    switch value {
    case .data(let data):
        return .data(data)
    case .base64(let base64):
        return .base64(base64)
    case .url(let url):
        return .url(url)
    case .text(let text):
        return .data(Data(text.utf8))
    case .reference:
        throw UnsupportedFunctionalityError(functionality: "provider reference file data on v3 model")
    }
}

private func _convertSharedV4FileDataToBase64String(_ value: SharedV4FileData) throws -> String {
    switch value {
    case .data(let data):
        return data.base64EncodedString()
    case .base64(let base64):
        return base64
    case .text(let text):
        return Data(text.utf8).base64EncodedString()
    case .url:
        throw UnsupportedFunctionalityError(functionality: "tool result file URLs on v3 model")
    case .reference:
        throw UnsupportedFunctionalityError(functionality: "provider reference file data on v3 model")
    }
}

private func _convertLanguageModelV3GenerateResultToV4(_ result: LanguageModelV3GenerateResult) throws -> LanguageModelV4GenerateResult {
    LanguageModelV4GenerateResult(
        content: try result.content.map(_convertLanguageModelV3ContentToV4),
        finishReason: _convertLanguageModelV3FinishReasonToV4(result.finishReason),
        usage: _convertLanguageModelV3UsageToV4(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map(_convertLanguageModelV3RequestInfoToV4),
        response: result.response.map(_convertLanguageModelV3ResponseInfoToV4),
        warnings: result.warnings.map(_convertSharedV3WarningToV4)
    )
}

private func _convertLanguageModelV3ContentToV4(_ value: LanguageModelV3Content) throws -> LanguageModelV4Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV4Text(text: content.text, providerMetadata: content.providerMetadata))
    case .reasoning(let content):
        return .reasoning(LanguageModelV4Reasoning(text: content.text, providerMetadata: content.providerMetadata))
    case .file(let content):
        return .file(_convertLanguageModelV3FileToV4(content))
    case .toolApprovalRequest(let request):
        return .toolApprovalRequest(_convertLanguageModelV3ToolApprovalRequestToV4(request))
    case .source(let source):
        return .source(_convertLanguageModelV3SourceToV4(source))
    case .toolCall(let toolCall):
        return .toolCall(_convertLanguageModelV3ToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(_convertLanguageModelV3ToolResultToV4(toolResult))
    }
}

private func _convertLanguageModelV3StreamPartToV4(_ value: LanguageModelV3StreamPart) throws -> LanguageModelV4StreamPart {
    switch value {
    case let .textStart(id, providerMetadata):
        return .textStart(id: id, providerMetadata: providerMetadata)
    case let .textDelta(id, delta, providerMetadata):
        return .textDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .textEnd(id, providerMetadata):
        return .textEnd(id: id, providerMetadata: providerMetadata)
    case let .reasoningStart(id, providerMetadata):
        return .reasoningStart(id: id, providerMetadata: providerMetadata)
    case let .reasoningDelta(id, delta, providerMetadata):
        return .reasoningDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .reasoningEnd(id, providerMetadata):
        return .reasoningEnd(id: id, providerMetadata: providerMetadata)
    case let .toolInputStart(id, toolName, providerMetadata, providerExecuted, dynamic, title):
        return .toolInputStart(
            id: id,
            toolName: toolName,
            providerMetadata: providerMetadata,
            providerExecuted: providerExecuted,
            dynamic: dynamic,
            title: title
        )
    case let .toolInputDelta(id, delta, providerMetadata):
        return .toolInputDelta(id: id, delta: delta, providerMetadata: providerMetadata)
    case let .toolInputEnd(id, providerMetadata):
        return .toolInputEnd(id: id, providerMetadata: providerMetadata)
    case .toolApprovalRequest(let request):
        return .toolApprovalRequest(_convertLanguageModelV3ToolApprovalRequestToV4(request))
    case .toolCall(let toolCall):
        return .toolCall(_convertLanguageModelV3ToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(_convertLanguageModelV3ToolResultToV4(toolResult))
    case .file(let file):
        return .file(_convertLanguageModelV3FileToV4(file))
    case .source(let source):
        return .source(_convertLanguageModelV3SourceToV4(source))
    case .streamStart(let warnings):
        return .streamStart(warnings: warnings.map(_convertSharedV3WarningToV4))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: _convertLanguageModelV3FinishReasonToV4(finishReason),
            usage: _convertLanguageModelV3UsageToV4(usage),
            providerMetadata: providerMetadata
        )
    case .raw(let rawValue):
        return .raw(rawValue: rawValue)
    case .error(let error):
        return .error(error: error)
    }
}

private func _convertLanguageModelV3FileToV4(_ value: LanguageModelV3File) -> LanguageModelV4File {
    LanguageModelV4File(
        mediaType: value.mediaType,
        data: _convertLanguageModelV3FileDataToV4(value.data),
        providerMetadata: value.providerMetadata
    )
}

private func _convertLanguageModelV3FileDataToV4(_ value: LanguageModelV3FileData) -> LanguageModelV4FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .data(data)
    }
}

private func _convertLanguageModelV3ToolApprovalRequestToV4(
    _ value: LanguageModelV3ToolApprovalRequest
) -> LanguageModelV4ToolApprovalRequest {
    LanguageModelV4ToolApprovalRequest(
        approvalId: value.approvalId,
        toolCallId: value.toolCallId,
        providerMetadata: value.providerMetadata
    )
}

private func _convertLanguageModelV3SourceToV4(_ value: LanguageModelV3Source) -> LanguageModelV4Source {
    switch value {
    case let .url(id, url, title, providerMetadata):
        return .url(id: id, url: url, title: title, providerMetadata: providerMetadata)
    case let .document(id, mediaType, title, filename, providerMetadata):
        return .document(
            id: id,
            mediaType: mediaType,
            title: title,
            filename: filename,
            providerMetadata: providerMetadata
        )
    }
}

private func _convertLanguageModelV3ToolCallToV4(_ value: LanguageModelV3ToolCall) -> LanguageModelV4ToolCall {
    LanguageModelV4ToolCall(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        input: value.input,
        providerExecuted: value.providerExecuted,
        dynamic: value.dynamic,
        providerMetadata: value.providerMetadata
    )
}

private func _convertLanguageModelV3ToolResultToV4(_ value: LanguageModelV3ToolResult) -> LanguageModelV4ToolResult {
    LanguageModelV4ToolResult(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        result: value.result,
        isError: value.isError,
        preliminary: value.preliminary,
        dynamic: value.dynamic,
        providerMetadata: value.providerMetadata
    )
}

private func _convertLanguageModelV3ToolResultOutputToV4(
    _ value: LanguageModelV3ToolResultOutput
) throws -> LanguageModelV4ToolResultOutput {
    switch value {
    case let .text(value, providerOptions):
        return .text(value: value, providerOptions: providerOptions)
    case let .json(value, providerOptions):
        return .json(value: value, providerOptions: providerOptions)
    case let .executionDenied(reason, providerOptions):
        return .executionDenied(reason: reason, providerOptions: providerOptions)
    case let .errorText(value, providerOptions):
        return .errorText(value: value, providerOptions: providerOptions)
    case let .errorJson(value, providerOptions):
        return .errorJson(value: value, providerOptions: providerOptions)
    case let .content(value, providerOptions):
        if providerOptions != nil {
            throw UnsupportedFunctionalityError(functionality: "tool result content providerOptions on v4 model")
        }
        return .content(value: value.map(_convertLanguageModelV3ToolResultContentPartToV4))
    }
}

private func _convertLanguageModelV3ToolResultContentPartToV4(
    _ value: LanguageModelV3ToolResultContentPart
) -> LanguageModelV4ToolResultContentPart {
    switch value {
    case .text(let text):
        return .text(text: text, providerOptions: nil)
    case let .media(data, mediaType):
        return .file(data: .base64(data), mediaType: mediaType, filename: nil, providerOptions: nil)
    }
}

private func _convertLanguageModelV3FinishReasonToV4(_ value: LanguageModelV3FinishReason) -> LanguageModelV4FinishReason {
    LanguageModelV4FinishReason(
        unified: LanguageModelV4FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func _convertLanguageModelV3UsageToV4(_ value: LanguageModelV3Usage) -> LanguageModelV4Usage {
    LanguageModelV4Usage(
        inputTokens: .init(
            total: value.inputTokens.total,
            noCache: value.inputTokens.noCache,
            cacheRead: value.inputTokens.cacheRead,
            cacheWrite: value.inputTokens.cacheWrite
        ),
        outputTokens: .init(
            total: value.outputTokens.total,
            text: value.outputTokens.text,
            reasoning: value.outputTokens.reasoning
        ),
        raw: value.raw
    )
}

private func _convertLanguageModelV3RequestInfoToV4(_ value: LanguageModelV3RequestInfo) -> LanguageModelV4RequestInfo {
    LanguageModelV4RequestInfo(body: value.body)
}

private func _convertLanguageModelV3ResponseInfoToV4(_ value: LanguageModelV3ResponseInfo) -> LanguageModelV4ResponseInfo {
    LanguageModelV4ResponseInfo(
        id: value.id,
        timestamp: value.timestamp,
        modelId: value.modelId,
        headers: value.headers,
        body: value.body
    )
}

private func _convertLanguageModelV3StreamResponseInfoToV4(
    _ value: LanguageModelV3StreamResponseInfo
) -> LanguageModelV4StreamResponseInfo {
    LanguageModelV4StreamResponseInfo(headers: value.headers)
}

// MARK: - Embedding Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class EmbeddingModelV3ToV4Adapter: EmbeddingModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any EmbeddingModelV3<String>

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxEmbeddingsPerCall: Int? { get async throws { try await model.maxEmbeddingsPerCall } }
    var supportsParallelCalls: Bool { get async throws { try await model.supportsParallelCalls } }

    init(wrapping model: any EmbeddingModelV3<String>) {
        self.model = model
    }

    func doEmbed(options: EmbeddingModelV4CallOptions) async throws -> EmbeddingModelV4Result {
        let result = try await model.doEmbed(
            options: EmbeddingModelV3DoEmbedOptions(
                values: options.values,
                abortSignal: options.abortSignal,
                providerOptions: options.providerOptions,
                headers: options.headers
            )
        )

        return EmbeddingModelV4Result(
            embeddings: result.embeddings,
            usage: result.usage.map { EmbeddingModelV4Usage(tokens: $0.tokens) },
            providerMetadata: result.providerMetadata,
            response: result.response.map { EmbeddingModelV4ResponseInfo(headers: $0.headers, body: $0.body) },
            warnings: result.warnings.map(_convertSharedV3WarningToV4)
        )
    }
}

// MARK: - Image Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class ImageModelV3ToV4Adapter: ImageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any ImageModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { _convertImageModelV3MaxImagesPerCallToV4(model.maxImagesPerCall) }

    init(wrapping model: any ImageModelV3) {
        self.model = model
    }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let result = try await model.doGenerate(options: try _convertImageModelV4CallOptionsToV3(options))
        return ImageModelV4GenerateResult(
            images: _convertImageModelV3GeneratedImagesToV4(result.images),
            warnings: result.warnings.map(_convertSharedV3WarningToV4),
            providerMetadata: _convertImageModelV3ProviderMetadataToV4(result.providerMetadata),
            response: ImageModelV4ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            ),
            usage: result.usage.map {
                ImageModelV4Usage(
                    inputTokens: $0.inputTokens,
                    outputTokens: $0.outputTokens,
                    totalTokens: $0.totalTokens
                )
            }
        )
    }
}

private func _convertImageModelV3MaxImagesPerCallToV4(_ value: ImageModelV3MaxImagesPerCall) -> ImageModelV4MaxImagesPerCall {
    switch value {
    case .value(let count):
        return .value(count)
    case .default:
        return .default
    case .function(let resolver):
        return .function(resolver)
    }
}

private func _convertImageModelV4CallOptionsToV3(_ options: ImageModelV4CallOptions) throws -> ImageModelV3CallOptions {
    ImageModelV3CallOptions(
        prompt: options.prompt,
        n: options.n,
        size: options.size,
        aspectRatio: options.aspectRatio,
        seed: options.seed,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers,
        files: try options.files?.map(_convertImageModelV4FileToV3),
        mask: try options.mask.map(_convertImageModelV4FileToV3)
    )
}

private func _convertImageModelV4FileToV3(_ value: ImageModelV4File) throws -> ImageModelV3File {
    switch value {
    case let .file(mediaType, data, providerOptions):
        return .file(mediaType: mediaType, data: _convertImageModelV4FileDataToV3(data), providerOptions: providerOptions)
    case let .url(url, providerOptions):
        return .url(url: url, providerOptions: providerOptions)
    }
}

private func _convertImageModelV4FileDataToV3(_ value: ImageModelV4FileData) -> ImageModelV3FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func _convertImageModelV3GeneratedImagesToV4(_ value: ImageModelV3GeneratedImages) -> ImageModelV4GeneratedImages {
    switch value {
    case .base64(let images):
        return .base64(images)
    case .binary(let images):
        return .binary(images)
    }
}

private func _convertImageModelV3ProviderMetadataToV4(
    _ value: ImageModelV3ProviderMetadata?
) -> ImageModelV4ProviderMetadata? {
    value?.mapValues { ImageModelV4ProviderMetadataValue(images: $0.images, additionalData: $0.additionalData) }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class ImageModelV2ToV4Adapter: ImageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any ImageModelV2

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { _convertImageModelV2MaxImagesPerCallToV4(model.maxImagesPerCall) }

    init(wrapping model: any ImageModelV2) {
        self.model = model
    }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        guard options.files == nil, options.mask == nil else {
            throw UnsupportedFunctionalityError(functionality: "image model v2 does not support image editing files or masks")
        }

        let result = try await model.doGenerate(
            options: ImageModelV2CallOptions(
                prompt: options.prompt ?? "",
                n: options.n,
                size: options.size,
                aspectRatio: options.aspectRatio,
                seed: options.seed,
                providerOptions: options.providerOptions,
                abortSignal: options.abortSignal,
                headers: options.headers
            )
        )

        return ImageModelV4GenerateResult(
            images: _convertImageModelV2GeneratedImagesToV4(result.images),
            warnings: result.warnings.map(_convertImageModelV2WarningToV4),
            providerMetadata: _convertImageModelV2ProviderMetadataToV4(result.providerMetadata),
            response: ImageModelV4ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            ),
            usage: nil
        )
    }
}

private func _convertImageModelV2MaxImagesPerCallToV4(_ value: ImageModelV2MaxImagesPerCall) -> ImageModelV4MaxImagesPerCall {
    switch value {
    case .value(let count):
        return .value(count)
    case .default:
        return .default
    case .function(let resolver):
        return .function(resolver)
    }
}

private func _convertImageModelV2GeneratedImagesToV4(_ value: ImageModelV2GeneratedImages) -> ImageModelV4GeneratedImages {
    switch value {
    case .base64(let images):
        return .base64(images)
    case .binary(let images):
        return .binary(images)
    }
}

private func _convertImageModelV2ProviderMetadataToV4(
    _ value: ImageModelV2ProviderMetadata?
) -> ImageModelV4ProviderMetadata? {
    value?.mapValues { ImageModelV4ProviderMetadataValue(images: $0.images, additionalData: $0.additionalData) }
}

private func _convertImageModelV2WarningToV4(_ value: ImageModelV2CallWarning) -> SharedV4Warning {
    switch value {
    case let .unsupportedSetting(setting, details):
        return .unsupported(feature: setting, details: details)
    case .other(let message):
        return .other(message: message)
    }
}

// MARK: - Reranking Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class RerankingModelV3ToV4Adapter: RerankingModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any RerankingModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }

    init(wrapping model: any RerankingModelV3) {
        self.model = model
    }

    func doRerank(options: RerankingModelV4CallOptions) async throws -> RerankingModelV4Result {
        let result = try await model.doRerank(options: _convertRerankingModelV4CallOptionsToV3(options))
        return RerankingModelV4Result(
            ranking: result.ranking.map { RerankingModelV4Ranking(index: $0.index, relevanceScore: $0.relevanceScore) },
            providerMetadata: result.providerMetadata,
            warnings: result.warnings.map(_convertSharedV3WarningToV4),
            response: result.response.map {
                RerankingModelV4ResponseInfo(
                    id: $0.id,
                    timestamp: $0.timestamp,
                    modelId: $0.modelId,
                    headers: $0.headers,
                    body: $0.body
                )
            }
        )
    }
}

private func _convertRerankingModelV4CallOptionsToV3(_ options: RerankingModelV4CallOptions) -> RerankingModelV3CallOptions {
    let documents: RerankingModelV3CallOptions.Documents
    switch options.documents {
    case .text(let values):
        documents = .text(values: values)
    case .object(let values):
        documents = .object(values: values)
    }

    return RerankingModelV3CallOptions(
        documents: documents,
        query: options.query,
        topN: options.topN,
        abortSignal: options.abortSignal,
        providerOptions: options.providerOptions,
        headers: options.headers
    )
}

// MARK: - Speech Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class SpeechModelV3ToV4Adapter: SpeechModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any SpeechModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }

    init(wrapping model: any SpeechModelV3) {
        self.model = model
    }

    func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let result = try await model.doGenerate(options: _convertSpeechModelV4CallOptionsToV3(options))
        return SpeechModelV4Result(
            audio: _convertSpeechModelV3AudioToV4(result.audio),
            warnings: result.warnings.map(_convertSharedV3WarningToV4),
            request: result.request.map { SpeechModelV4Result.RequestInfo(body: $0.body) },
            response: SpeechModelV4Result.ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                body: result.response.body
            ),
            providerMetadata: result.providerMetadata
        )
    }
}

private func _convertSpeechModelV4CallOptionsToV3(_ options: SpeechModelV4CallOptions) -> SpeechModelV3CallOptions {
    SpeechModelV3CallOptions(
        text: options.text,
        voice: options.voice,
        outputFormat: options.outputFormat,
        instructions: options.instructions,
        speed: options.speed,
        language: options.language,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers
    )
}

private func _convertSpeechModelV3AudioToV4(_ value: SpeechModelV3Audio) -> SpeechModelV4Audio {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class SpeechModelV2ToV4Adapter: SpeechModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any SpeechModelV2

    var provider: String { model.provider }
    var modelId: String { model.modelId }

    init(wrapping model: any SpeechModelV2) {
        self.model = model
    }

    func doGenerate(options: SpeechModelV4CallOptions) async throws -> SpeechModelV4Result {
        let result = try await model.doGenerate(options: _convertSpeechModelV4CallOptionsToV2(options))
        return SpeechModelV4Result(
            audio: _convertSpeechModelV2AudioToV4(result.audio),
            warnings: result.warnings.map(_convertSpeechModelV2WarningToV4),
            request: result.request.map { SpeechModelV4Result.RequestInfo(body: $0.body) },
            response: SpeechModelV4Result.ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                body: result.response.body
            ),
            providerMetadata: result.providerMetadata
        )
    }
}

private func _convertSpeechModelV4CallOptionsToV2(_ options: SpeechModelV4CallOptions) -> SpeechModelV2CallOptions {
    SpeechModelV2CallOptions(
        text: options.text,
        voice: options.voice,
        outputFormat: options.outputFormat,
        instructions: options.instructions,
        speed: options.speed,
        language: options.language,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers
    )
}

private func _convertSpeechModelV2AudioToV4(_ value: SpeechModelV2Audio) -> SpeechModelV4Audio {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func _convertSpeechModelV2WarningToV4(_ value: SpeechModelV2CallWarning) -> SharedV4Warning {
    switch value {
    case let .unsupportedSetting(setting, details):
        return .unsupported(feature: setting, details: details)
    case .other(let message):
        return .other(message: message)
    }
}

// MARK: - Transcription Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class TranscriptionModelV2ToV4Adapter: TranscriptionModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any TranscriptionModelV2

    var provider: String { model.provider }
    var modelId: String { model.modelId }

    init(wrapping model: any TranscriptionModelV2) {
        self.model = model
    }

    func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let result = try await model.doGenerate(options: _convertTranscriptionModelV4CallOptionsToV2(options))
        return TranscriptionModelV4Result(
            text: result.text,
            segments: result.segments.map {
                TranscriptionModelV4Result.Segment(
                    text: $0.text,
                    startSecond: $0.startSecond,
                    endSecond: $0.endSecond
                )
            },
            language: result.language,
            durationInSeconds: result.durationInSeconds,
            warnings: result.warnings.map(_convertTranscriptionModelV2WarningToV4),
            request: result.request.map { TranscriptionModelV4Result.RequestInfo(body: $0.body) },
            response: TranscriptionModelV4Result.ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                body: result.response.body
            ),
            providerMetadata: result.providerMetadata
        )
    }
}

private func _convertTranscriptionModelV4CallOptionsToV2(
    _ options: TranscriptionModelV4CallOptions
) -> TranscriptionModelV2CallOptions {
    TranscriptionModelV2CallOptions(
        audio: _convertTranscriptionModelV4AudioToV2(options.audio),
        mediaType: options.mediaType,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers
    )
}

private func _convertTranscriptionModelV4AudioToV2(_ value: TranscriptionModelV4Audio) -> TranscriptionModelV2Audio {
    switch value {
    case .binary(let data):
        return .binary(data)
    case .base64(let base64):
        return .base64(base64)
    }
}

private func _convertTranscriptionModelV2WarningToV4(_ value: TranscriptionModelV2CallWarning) -> SharedV4Warning {
    switch value {
    case let .unsupportedSetting(setting, details):
        return .unsupported(feature: setting, details: details)
    case .other(let message):
        return .other(message: message)
    }
}

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class TranscriptionModelV3ToV4Adapter: TranscriptionModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any TranscriptionModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }

    init(wrapping model: any TranscriptionModelV3) {
        self.model = model
    }

    func doGenerate(options: TranscriptionModelV4CallOptions) async throws -> TranscriptionModelV4Result {
        let result = try await model.doGenerate(options: _convertTranscriptionModelV4CallOptionsToV3(options))
        return TranscriptionModelV4Result(
            text: result.text,
            segments: result.segments.map {
                TranscriptionModelV4Result.Segment(
                    text: $0.text,
                    startSecond: $0.startSecond,
                    endSecond: $0.endSecond
                )
            },
            language: result.language,
            durationInSeconds: result.durationInSeconds,
            warnings: result.warnings.map(_convertSharedV3WarningToV4),
            request: result.request.map { TranscriptionModelV4Result.RequestInfo(body: $0.body) },
            response: TranscriptionModelV4Result.ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers,
                body: result.response.body
            ),
            providerMetadata: result.providerMetadata
        )
    }
}

private func _convertTranscriptionModelV4CallOptionsToV3(
    _ options: TranscriptionModelV4CallOptions
) -> TranscriptionModelV3CallOptions {
    TranscriptionModelV3CallOptions(
        audio: _convertTranscriptionModelV4AudioToV3(options.audio),
        mediaType: options.mediaType,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers
    )
}

private func _convertTranscriptionModelV4AudioToV3(_ value: TranscriptionModelV4Audio) -> TranscriptionModelV3Audio {
    switch value {
    case .binary(let data):
        return .binary(data)
    case .base64(let base64):
        return .base64(base64)
    }
}

// MARK: - Video Model Adapter

@available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *)
private final class VideoModelV3ToV4Adapter: VideoModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any VideoModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxVideosPerCall: VideoModelV4MaxVideosPerCall { _convertVideoModelV3MaxVideosPerCallToV4(model.maxVideosPerCall) }

    init(wrapping model: any VideoModelV3) {
        self.model = model
    }

    func doGenerate(options: VideoModelV4CallOptions) async throws -> VideoModelV4GenerateResult {
        let result = try await model.doGenerate(options: try _convertVideoModelV4CallOptionsToV3(options))
        return VideoModelV4GenerateResult(
            videos: try result.videos.map(_convertVideoModelV3VideoDataToV4),
            warnings: result.warnings.map(_convertSharedV3WarningToV4),
            providerMetadata: result.providerMetadata,
            response: VideoModelV4ResponseInfo(
                timestamp: result.response.timestamp,
                modelId: result.response.modelId,
                headers: result.response.headers
            )
        )
    }
}

private func _convertVideoModelV3MaxVideosPerCallToV4(_ value: VideoModelV3MaxVideosPerCall) -> VideoModelV4MaxVideosPerCall {
    switch value {
    case .value(let count):
        return .value(count)
    case .default:
        return .default
    case .function(let resolver):
        return .function(resolver)
    }
}

private func _convertVideoModelV4CallOptionsToV3(_ options: VideoModelV4CallOptions) throws -> VideoModelV3CallOptions {
    if options.frameImages?.isEmpty == false {
        throw UnsupportedFunctionalityError(functionality: "video model v4 frameImages option on v3 model")
    }
    if options.inputReferences?.isEmpty == false {
        throw UnsupportedFunctionalityError(functionality: "video model v4 inputReferences option on v3 model")
    }
    if options.generateAudio != nil {
        throw UnsupportedFunctionalityError(functionality: "video model v4 generateAudio option on v3 model")
    }

    return VideoModelV3CallOptions(
        prompt: options.prompt,
        n: options.n,
        aspectRatio: options.aspectRatio,
        resolution: options.resolution,
        duration: options.duration,
        fps: options.fps,
        seed: options.seed,
        image: try options.image.map(_convertVideoModelV4FileToV3),
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers
    )
}

private func _convertVideoModelV4FileToV3(_ value: VideoModelV4File) throws -> VideoModelV3File {
    switch value {
    case let .file(mediaType, data, providerOptions):
        return .file(mediaType: mediaType, data: _convertVideoModelV4FileDataToV3(data), providerOptions: providerOptions)
    case let .url(url, providerOptions):
        return .url(url: url, providerOptions: providerOptions)
    }
}

private func _convertVideoModelV4FileDataToV3(_ value: VideoModelV4FileData) -> VideoModelV3FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func _convertVideoModelV3VideoDataToV4(_ value: VideoModelV3VideoData) throws -> VideoModelV4VideoData {
    switch value {
    case let .url(url, mediaType):
        return .url(url: url, mediaType: try _requireVideoMediaType(mediaType))
    case let .base64(data, mediaType):
        return .base64(data: data, mediaType: try _requireVideoMediaType(mediaType))
    case let .binary(data, mediaType):
        return .binary(data: data, mediaType: try _requireVideoMediaType(mediaType))
    }
}

private func _requireVideoMediaType(_ mediaType: String?) throws -> String {
    guard let mediaType else {
        throw UnsupportedFunctionalityError(functionality: "video model v3 result without mediaType on v4 model")
    }
    return mediaType
}

// MARK: - Shared Converters

private func _convertSharedV3WarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .other(let message):
        return .other(message: message)
    }
}
