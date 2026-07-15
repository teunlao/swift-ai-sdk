import Foundation
import AISDKProvider

public final class AnthropicMessagesLanguageModelV4: LanguageModelV4 {
    private let model: AnthropicMessagesLanguageModel

    public init(modelId: AnthropicMessagesModelId, config: AnthropicMessagesConfig) {
        self.model = AnthropicMessagesLanguageModel(modelId: modelId, config: config)
    }

    fileprivate init(model: AnthropicMessagesLanguageModel) {
        self.model = model
    }

    public var provider: String { model.provider }
    public var modelId: String { model.modelId }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws { try await model.supportedUrls }
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        try convertAnthropicGenerateResultToV4(
            await model.doGenerateV4(options: options)
        )
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await model.doStreamV4(options: options)
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error>(bufferingPolicy: .unbounded) { continuation in
            let task = Task {
                do {
                    for try await part in result.stream {
                        continuation.yield(try convertAnthropicStreamPartToV4(part))
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
            request: result.request.map { LanguageModelV4RequestInfo(body: $0.body) },
            response: result.response.map { LanguageModelV4StreamResponseInfo(headers: $0.headers) }
        )
    }
}

extension AnthropicMessagesLanguageModel {
    func asV4() -> AnthropicMessagesLanguageModelV4 {
        AnthropicMessagesLanguageModelV4(model: self)
    }
}

func convertAnthropicResponseFormatToV3(
    _ value: LanguageModelV4ResponseFormat
) -> LanguageModelV3ResponseFormat {
    switch value {
    case .text:
        return .text
    case let .json(schema, name, description):
        return .json(schema: schema, name: name, description: description)
    }
}

func convertAnthropicToolChoiceToV3(_ value: LanguageModelV4ToolChoice) -> LanguageModelV3ToolChoice {
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

func convertAnthropicToolToV3(_ value: LanguageModelV4Tool) -> LanguageModelV3Tool {
    switch value {
    case .function(let tool):
        return .function(LanguageModelV3FunctionTool(
            name: tool.name,
            inputSchema: tool.inputSchema,
            inputExamples: tool.inputExamples?.map { LanguageModelV3ToolInputExample(input: $0.input) },
            description: tool.description,
            strict: tool.strict,
            providerOptions: tool.providerOptions
        ))
    case .provider(let tool):
        return .provider(LanguageModelV3ProviderTool(id: tool.id, name: tool.name, args: tool.args))
    }
}

func convertAnthropicMessagePartToV3(_ value: LanguageModelV4MessagePart) throws -> LanguageModelV3MessagePart {
    switch value {
    case .text(let part):
        return .text(LanguageModelV3TextPart(text: part.text, providerOptions: part.providerOptions))
    case .file(let part):
        return .file(LanguageModelV3FilePart(
            data: try convertAnthropicFileDataToV3(part.data),
            mediaType: part.mediaType,
            filename: part.filename,
            providerOptions: part.providerOptions
        ))
    case .reasoning(let part):
        return .reasoning(LanguageModelV3ReasoningPart(text: part.text, providerOptions: part.providerOptions))
    case .toolCall(let part):
        return .toolCall(LanguageModelV3ToolCallPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            input: part.input,
            providerExecuted: part.providerExecuted,
            providerOptions: part.providerOptions
        ))
    case .toolResult(let part):
        return .toolResult(LanguageModelV3ToolResultPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            output: try convertAnthropicToolResultOutputToV3(part.output),
            providerOptions: part.providerOptions
        ))
    case .custom(let part):
        return .custom(LanguageModelV3CustomPart(kind: part.kind, providerOptions: part.providerOptions))
    case .reasoningFile:
        throw UnsupportedFunctionalityError(functionality: "Anthropic reasoning-file prompt content")
    }
}

func convertAnthropicToolMessagePartToV3(
    _ value: LanguageModelV4ToolMessagePart
) throws -> LanguageModelV3ToolMessagePart {
    switch value {
    case .toolResult(let part):
        return .toolResult(LanguageModelV3ToolResultPart(
            toolCallId: part.toolCallId,
            toolName: part.toolName,
            output: try convertAnthropicToolResultOutputToV3(part.output),
            providerOptions: part.providerOptions
        ))
    case .toolApprovalResponse(let part):
        return .toolApprovalResponse(LanguageModelV3ToolApprovalResponsePart(
            approvalId: part.approvalId,
            approved: part.approved,
            reason: part.reason,
            providerOptions: part.providerOptions
        ))
    }
}

private func convertAnthropicToolResultOutputToV3(
    _ value: LanguageModelV4ToolResultOutput
) throws -> LanguageModelV3ToolResultOutput {
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
        return .content(value: try value.map(convertAnthropicToolResultContentPartToV3))
    }
}

private func convertAnthropicToolResultContentPartToV3(
    _ value: LanguageModelV4ToolResultContentPart
) throws -> LanguageModelV3ToolResultContentPart {
    switch value {
    case .text(let text, _):
        return .text(text: text)
    case .file(let data, let mediaType, _, _):
        return .media(data: try convertAnthropicFileDataToBase64(data), mediaType: mediaType)
    case .custom:
        throw UnsupportedFunctionalityError(functionality: "Anthropic custom tool result content")
    }
}

func convertAnthropicFileDataToV3(_ value: SharedV4FileData) throws -> LanguageModelV3DataContent {
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
        throw UnsupportedFunctionalityError(functionality: "Anthropic provider reference outside user file content")
    }
}

private func convertAnthropicFileDataToBase64(_ value: SharedV4FileData) throws -> String {
    switch value {
    case .data(let data):
        return data.base64EncodedString()
    case .base64(let base64):
        return base64
    case .text(let text):
        return Data(text.utf8).base64EncodedString()
    case .url:
        throw UnsupportedFunctionalityError(functionality: "Anthropic tool result file URL")
    case .reference:
        throw UnsupportedFunctionalityError(functionality: "Anthropic tool result provider reference")
    }
}

private func convertAnthropicGenerateResultToV4(
    _ result: LanguageModelV3GenerateResult
) throws -> LanguageModelV4GenerateResult {
    LanguageModelV4GenerateResult(
        content: try result.content.map(convertAnthropicContentToV4),
        finishReason: convertAnthropicFinishReasonToV4(result.finishReason),
        usage: convertAnthropicUsageToV4(result.usage),
        providerMetadata: result.providerMetadata,
        request: result.request.map { LanguageModelV4RequestInfo(body: $0.body) },
        response: result.response.map {
            LanguageModelV4ResponseInfo(
                id: $0.id,
                timestamp: $0.timestamp,
                modelId: $0.modelId,
                headers: $0.headers,
                body: $0.body
            )
        },
        warnings: result.warnings.map(convertAnthropicWarningToV4)
    )
}

private func convertAnthropicContentToV4(_ value: LanguageModelV3Content) throws -> LanguageModelV4Content {
    switch value {
    case .text(let content):
        return .text(LanguageModelV4Text(text: content.text, providerMetadata: content.providerMetadata))
    case .reasoning(let content):
        return .reasoning(LanguageModelV4Reasoning(text: content.text, providerMetadata: content.providerMetadata))
    case .custom(let content):
        return .custom(LanguageModelV4CustomContent(kind: content.kind, providerMetadata: content.providerMetadata))
    case .file(let content):
        let data: LanguageModelV4FileData = switch content.data {
        case .base64(let base64): .base64(base64)
        case .binary(let data): .data(data)
        }
        return .file(LanguageModelV4File(
            mediaType: content.mediaType,
            data: data,
            providerMetadata: content.providerMetadata
        ))
    case .toolApprovalRequest(let request):
        return .toolApprovalRequest(LanguageModelV4ToolApprovalRequest(
            approvalId: request.approvalId,
            toolCallId: request.toolCallId,
            providerMetadata: request.providerMetadata
        ))
    case .source(let source):
        return .source(convertAnthropicSourceToV4(source))
    case .toolCall(let toolCall):
        return .toolCall(convertAnthropicToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(convertAnthropicToolResultToV4(toolResult))
    }
}

private func convertAnthropicStreamPartToV4(
    _ value: LanguageModelV3StreamPart
) throws -> LanguageModelV4StreamPart {
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
        return .toolApprovalRequest(LanguageModelV4ToolApprovalRequest(
            approvalId: request.approvalId,
            toolCallId: request.toolCallId,
            providerMetadata: request.providerMetadata
        ))
    case .toolCall(let toolCall):
        return .toolCall(convertAnthropicToolCallToV4(toolCall))
    case .toolResult(let toolResult):
        return .toolResult(convertAnthropicToolResultToV4(toolResult))
    case .custom(let custom):
        return .custom(LanguageModelV4CustomContent(kind: custom.kind, providerMetadata: custom.providerMetadata))
    case .file(let file):
        let data: LanguageModelV4FileData = switch file.data {
        case .base64(let base64): .base64(base64)
        case .binary(let data): .data(data)
        }
        return .file(LanguageModelV4File(
            mediaType: file.mediaType,
            data: data,
            providerMetadata: file.providerMetadata
        ))
    case .source(let source):
        return .source(convertAnthropicSourceToV4(source))
    case .streamStart(let warnings):
        return .streamStart(warnings: warnings.map(convertAnthropicWarningToV4))
    case let .responseMetadata(id, modelId, timestamp):
        return .responseMetadata(id: id, modelId: modelId, timestamp: timestamp)
    case let .finish(finishReason, usage, providerMetadata):
        return .finish(
            finishReason: convertAnthropicFinishReasonToV4(finishReason),
            usage: convertAnthropicUsageToV4(usage),
            providerMetadata: providerMetadata
        )
    case .raw(let rawValue):
        return .raw(rawValue: rawValue)
    case .error(let error):
        return .error(error: error)
    }
}

private func convertAnthropicSourceToV4(_ value: LanguageModelV3Source) -> LanguageModelV4Source {
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

private func convertAnthropicToolCallToV4(_ value: LanguageModelV3ToolCall) -> LanguageModelV4ToolCall {
    LanguageModelV4ToolCall(
        toolCallId: value.toolCallId,
        toolName: value.toolName,
        input: value.input,
        providerExecuted: value.providerExecuted,
        dynamic: value.dynamic,
        providerMetadata: value.providerMetadata
    )
}

private func convertAnthropicToolResultToV4(_ value: LanguageModelV3ToolResult) -> LanguageModelV4ToolResult {
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

private func convertAnthropicFinishReasonToV4(
    _ value: LanguageModelV3FinishReason
) -> LanguageModelV4FinishReason {
    LanguageModelV4FinishReason(
        unified: LanguageModelV4FinishReason.Unified(rawValue: value.unified.rawValue) ?? .other,
        raw: value.raw
    )
}

private func convertAnthropicUsageToV4(_ value: LanguageModelV3Usage) -> LanguageModelV4Usage {
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

func convertAnthropicWarningToV3(_ value: SharedV4Warning) -> SharedV3Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case let .deprecated(setting, message):
        return .other(message: "Deprecated \(setting): \(message)")
    case .other(let message):
        return .other(message: message)
    }
}

private func convertAnthropicWarningToV4(_ value: SharedV3Warning) -> SharedV4Warning {
    switch value {
    case let .unsupported(feature, details):
        return .unsupported(feature: feature, details: details)
    case let .compatibility(feature, details):
        return .compatibility(feature: feature, details: details)
    case .other(let message):
        return .other(message: message)
    }
}
