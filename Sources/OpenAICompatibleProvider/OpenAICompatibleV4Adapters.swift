import Foundation
import AISDKProvider

final class OpenAICompatibleLanguageModelV4Adapter: LanguageModelV4, @unchecked Sendable {
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
        let result = try await model.doGenerate(options: try convertLanguageModelV4CallOptionsToV3(options))
        return try convertLanguageModelV3GenerateResultToV4(result)
    }

    func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await model.doStream(options: try convertLanguageModelV4CallOptionsToV3(options))
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertLanguageModelV3StreamPartToV4(part))
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
            request: result.request.map(convertLanguageModelV3RequestInfoToV4),
            response: result.response.map(convertLanguageModelV3StreamResponseInfoToV4)
        )
    }
}

private func convertLanguageModelV4CallOptionsToV3(_ options: LanguageModelV4CallOptions) throws -> LanguageModelV3CallOptions {
    if options.reasoning != nil {
        throw UnsupportedFunctionalityError(functionality: "language model v4 reasoning option on v3-backed OpenAI-compatible model")
    }

    return LanguageModelV3CallOptions(
        prompt: try options.prompt.map(convertLanguageModelV4MessageToV3),
        maxOutputTokens: options.maxOutputTokens,
        temperature: options.temperature,
        stopSequences: options.stopSequences,
        topP: options.topP,
        topK: options.topK,
        presencePenalty: options.presencePenalty,
        frequencyPenalty: options.frequencyPenalty,
        responseFormat: options.responseFormat.map(convertLanguageModelV4ResponseFormatToV3),
        seed: options.seed,
        tools: try options.tools?.map(convertLanguageModelV4ToolToV3),
        toolChoice: options.toolChoice.map(convertLanguageModelV4ToolChoiceToV3),
        includeRawChunks: options.includeRawChunks,
        abortSignal: options.abortSignal,
        headers: options.headers,
        providerOptions: options.providerOptions
    )
}

private func convertLanguageModelV4ResponseFormatToV3(_ value: LanguageModelV4ResponseFormat) -> LanguageModelV3ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

private func convertLanguageModelV4ToolChoiceToV3(_ value: LanguageModelV4ToolChoice) -> LanguageModelV3ToolChoice {
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

private func convertLanguageModelV4ToolToV3(_ value: LanguageModelV4Tool) throws -> LanguageModelV3Tool {
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

private func convertLanguageModelV4MessageToV3(_ value: LanguageModelV4Message) throws -> LanguageModelV3Message {
    switch value {
    case let .system(content, providerOptions):
        return .system(content: content, providerOptions: providerOptions)
    case let .user(content, providerOptions):
        return .user(content: try content.map(convertLanguageModelV4UserMessagePartToV3), providerOptions: providerOptions)
    case let .assistant(content, providerOptions):
        return .assistant(content: try content.map(convertLanguageModelV4MessagePartToV3), providerOptions: providerOptions)
    case let .tool(content, providerOptions):
        return .tool(content: try content.map(convertLanguageModelV4ToolMessagePartToV3), providerOptions: providerOptions)
    }
}

private func convertLanguageModelV4UserMessagePartToV3(_ value: LanguageModelV4UserMessagePart) throws -> LanguageModelV3UserMessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(
            LanguageModelV3FilePart(
                data: try convertSharedV4FileDataToLanguageModelV3DataContent(part.data),
                mediaType: part.mediaType,
                filename: part.filename,
                providerOptions: part.providerOptions
            )
        )
    }
}

private func convertLanguageModelV4MessagePartToV3(_ value: LanguageModelV4MessagePart) throws -> LanguageModelV3MessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(
            LanguageModelV3FilePart(
                data: try convertSharedV4FileDataToLanguageModelV3DataContent(part.data),
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
                output: try convertLanguageModelV4ToolResultOutputToV3(part.output),
                providerOptions: part.providerOptions
            )
        )
    case .custom:
        throw UnsupportedFunctionalityError(functionality: "language model v4 custom prompt parts on v3-backed OpenAI-compatible model")
    case .reasoningFile:
        throw UnsupportedFunctionalityError(functionality: "language model v4 reasoning-file prompt parts on v3-backed OpenAI-compatible model")
    }
}

private func convertLanguageModelV4ToolMessagePartToV3(_ value: LanguageModelV4ToolMessagePart) throws -> LanguageModelV3ToolMessagePart {
    switch value {
    case .toolResult(let part):
        return .toolResult(
            LanguageModelV3ToolResultPart(
                toolCallId: part.toolCallId,
                toolName: part.toolName,
                output: try convertLanguageModelV4ToolResultOutputToV3(part.output),
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

private func convertLanguageModelV4ToolResultOutputToV3(_ value: LanguageModelV4ToolResultOutput) throws -> LanguageModelV3ToolResultOutput {
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
        return .content(value: try value.map(convertLanguageModelV4ToolResultContentPartToV3))
    }
}

private func convertLanguageModelV4ToolResultContentPartToV3(
    _ value: LanguageModelV4ToolResultContentPart
) throws -> LanguageModelV3ToolResultContentPart {
    switch value {
    case let .text(text, providerOptions):
        if providerOptions != nil {
            throw UnsupportedFunctionalityError(functionality: "tool result text providerOptions on v3-backed OpenAI-compatible model")
        }
        return .text(text: text)
    case let .file(data, mediaType, _, providerOptions):
        if providerOptions != nil {
            throw UnsupportedFunctionalityError(functionality: "tool result file providerOptions on v3-backed OpenAI-compatible model")
        }
        return .media(data: try convertSharedV4FileDataToBase64String(data), mediaType: mediaType)
    case .custom:
        throw UnsupportedFunctionalityError(functionality: "tool result custom content on v3-backed OpenAI-compatible model")
    }
}

private func convertSharedV4FileDataToLanguageModelV3DataContent(_ value: SharedV4FileData) throws -> LanguageModelV3DataContent {
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
        throw UnsupportedFunctionalityError(functionality: "provider reference file data on v3-backed OpenAI-compatible model")
    }
}

private func convertSharedV4FileDataToBase64String(_ value: SharedV4FileData) throws -> String {
    switch value {
    case .data(let data):
        return data.base64EncodedString()
    case .base64(let base64):
        return base64
    case .text(let text):
        return Data(text.utf8).base64EncodedString()
    case .url:
        throw UnsupportedFunctionalityError(functionality: "tool result file URLs on v3-backed OpenAI-compatible model")
    case .reference:
        throw UnsupportedFunctionalityError(functionality: "provider reference file data on v3-backed OpenAI-compatible model")
    }
}

private func convertLanguageModelV3GenerateResultToV4(_ result: LanguageModelV3GenerateResult) throws -> LanguageModelV4GenerateResult {
    LanguageModelV4GenerateResult(
        content: try result.content.map(convertLanguageModelV3ContentToV4),
        finishReason: convertLanguageModelV3FinishReasonToV4(result.finishReason),
        usage: convertLanguageModelV3UsageToV4(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map(convertLanguageModelV3RequestInfoToV4),
        response: result.response.map(convertLanguageModelV3ResponseInfoToV4),
        warnings: result.warnings.map(convertSharedV3WarningToV4)
    )
}

private func convertLanguageModelV3ContentToV4(_ value: LanguageModelV3Content) throws -> LanguageModelV4Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV4Text(text: content.text, providerMetadata: content.providerMetadata))
    case .reasoning(let content):
        return .reasoning(LanguageModelV4Reasoning(text: content.text, providerMetadata: content.providerMetadata))
    case .file(let content):
        return .file(convertLanguageModelV3FileToV4(content))
    case .toolApprovalRequest(let request):
        return .toolApprovalRequest(convertLanguageModelV3ToolApprovalRequestToV4(request))
    case .source(let source):
        return .source(convertLanguageModelV3SourceToV4(source))
    case .toolCall(let toolCall):
        return .toolCall(convertLanguageModelV3ToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(convertLanguageModelV3ToolResultToV4(toolResult))
    }
}

private func convertLanguageModelV3StreamPartToV4(_ value: LanguageModelV3StreamPart) throws -> LanguageModelV4StreamPart {
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
        return .toolApprovalRequest(convertLanguageModelV3ToolApprovalRequestToV4(request))
    case .toolCall(let toolCall):
        return .toolCall(convertLanguageModelV3ToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(convertLanguageModelV3ToolResultToV4(toolResult))
    case .file(let file):
        return .file(convertLanguageModelV3FileToV4(file))
    case .source(let source):
        return .source(convertLanguageModelV3SourceToV4(source))
    case .streamStart(let warnings):
        return .streamStart(warnings: warnings.map(convertSharedV3WarningToV4))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertLanguageModelV3FinishReasonToV4(finishReason),
            usage: convertLanguageModelV3UsageToV4(usage),
            providerMetadata: providerMetadata
        )
    case .raw(let rawValue):
        return .raw(rawValue: rawValue)
    case .error(let error):
        return .error(error: error)
    }
}

private func convertLanguageModelV3FileToV4(_ value: LanguageModelV3File) -> LanguageModelV4File {
    LanguageModelV4File(
        mediaType: value.mediaType,
        data: convertLanguageModelV3FileDataToV4(value.data),
        providerMetadata: value.providerMetadata
    )
}

private func convertLanguageModelV3FileDataToV4(_ value: LanguageModelV3FileData) -> LanguageModelV4FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .data(data)
    }
}

private func convertLanguageModelV3ToolApprovalRequestToV4(
    _ value: LanguageModelV3ToolApprovalRequest
) -> LanguageModelV4ToolApprovalRequest {
    LanguageModelV4ToolApprovalRequest(
        approvalId: value.approvalId,
        toolCallId: value.toolCallId,
        providerMetadata: value.providerMetadata
    )
}

private func convertLanguageModelV3SourceToV4(_ value: LanguageModelV3Source) -> LanguageModelV4Source {
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

private func convertLanguageModelV3ToolCallToV4(_ value: LanguageModelV3ToolCall) -> LanguageModelV4ToolCall {
    LanguageModelV4ToolCall(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        input: value.input,
        providerExecuted: value.providerExecuted,
        dynamic: value.dynamic,
        providerMetadata: value.providerMetadata
    )
}

private func convertLanguageModelV3ToolResultToV4(_ value: LanguageModelV3ToolResult) -> LanguageModelV4ToolResult {
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

private func convertLanguageModelV3FinishReasonToV4(_ value: LanguageModelV3FinishReason) -> LanguageModelV4FinishReason {
    LanguageModelV4FinishReason(
        unified: LanguageModelV4FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertLanguageModelV3UsageToV4(_ value: LanguageModelV3Usage) -> LanguageModelV4Usage {
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

private func convertLanguageModelV3RequestInfoToV4(_ value: LanguageModelV3RequestInfo) -> LanguageModelV4RequestInfo {
    LanguageModelV4RequestInfo(body: value.body)
}

private func convertLanguageModelV3ResponseInfoToV4(_ value: LanguageModelV3ResponseInfo) -> LanguageModelV4ResponseInfo {
    LanguageModelV4ResponseInfo(
        id: value.id,
        timestamp: value.timestamp,
        modelId: value.modelId,
        headers: value.headers,
        body: value.body
    )
}

private func convertLanguageModelV3StreamResponseInfoToV4(
    _ value: LanguageModelV3StreamResponseInfo
) -> LanguageModelV4StreamResponseInfo {
    LanguageModelV4StreamResponseInfo(headers: value.headers)
}

final class OpenAICompatibleEmbeddingModelV4Adapter: EmbeddingModelV4, @unchecked Sendable {
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
            warnings: result.warnings.map(convertSharedV3WarningToV4)
        )
    }
}

final class OpenAICompatibleImageModelV4Adapter: ImageModelV4, @unchecked Sendable {
    let specificationVersion = "v4"

    private let model: any ImageModelV3

    var provider: String { model.provider }
    var modelId: String { model.modelId }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { convertImageModelV3MaxImagesPerCallToV4(model.maxImagesPerCall) }

    init(wrapping model: any ImageModelV3) {
        self.model = model
    }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        let result = try await model.doGenerate(options: try convertImageModelV4CallOptionsToV3(options))
        return ImageModelV4GenerateResult(
            images: convertImageModelV3GeneratedImagesToV4(result.images),
            warnings: result.warnings.map(convertSharedV3WarningToV4),
            providerMetadata: convertImageModelV3ProviderMetadataToV4(result.providerMetadata),
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

private func convertImageModelV3MaxImagesPerCallToV4(_ value: ImageModelV3MaxImagesPerCall) -> ImageModelV4MaxImagesPerCall {
    switch value {
    case .value(let count):
        return .value(count)
    case .default:
        return .default
    case .function(let resolver):
        return .function(resolver)
    }
}

private func convertImageModelV4CallOptionsToV3(_ options: ImageModelV4CallOptions) throws -> ImageModelV3CallOptions {
    ImageModelV3CallOptions(
        prompt: options.prompt,
        n: options.n,
        size: options.size,
        aspectRatio: options.aspectRatio,
        seed: options.seed,
        providerOptions: options.providerOptions,
        abortSignal: options.abortSignal,
        headers: options.headers,
        files: try options.files?.map(convertImageModelV4FileToV3),
        mask: try options.mask.map(convertImageModelV4FileToV3)
    )
}

private func convertImageModelV4FileToV3(_ value: ImageModelV4File) throws -> ImageModelV3File {
    switch value {
    case let .file(mediaType, data, providerOptions):
        return .file(mediaType: mediaType, data: convertImageModelV4FileDataToV3(data), providerOptions: providerOptions)
    case let .url(url, providerOptions):
        return .url(url: url, providerOptions: providerOptions)
    }
}

private func convertImageModelV4FileDataToV3(_ value: ImageModelV4FileData) -> ImageModelV3FileData {
    switch value {
    case .base64(let base64):
        return .base64(base64)
    case .binary(let data):
        return .binary(data)
    }
}

private func convertImageModelV3GeneratedImagesToV4(_ value: ImageModelV3GeneratedImages) -> ImageModelV4GeneratedImages {
    switch value {
    case .base64(let images):
        return .base64(images)
    case .binary(let images):
        return .binary(images)
    }
}

private func convertImageModelV3ProviderMetadataToV4(
    _ value: ImageModelV3ProviderMetadata?
) -> ImageModelV4ProviderMetadata? {
    value?.mapValues { ImageModelV4ProviderMetadataValue(images: $0.images, additionalData: $0.additionalData) }
}

private func convertSharedV3WarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .other(let message):
        return .other(message: message)
    }
}
