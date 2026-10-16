import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Downloaded generated-file data, shared by the conversions of one step.
actor GeneratedFileDataCache {
    private var entries: [URL: Data] = [:]

    func data(for url: URL, abortSignal: (@Sendable () -> Bool)?) async throws -> Data {
        if let cached = entries[url] { return cached }
        let downloaded = try await download(url: url, isAborted: abortSignal).data
        entries[url] = downloaded
        return downloaded
    }
}

/**
 Resolves generated file data, downloading URL-backed files.

 Port of `@ai-sdk/ai/src/generate-text/resolve-generated-file-data.ts`.
 */
func resolveGeneratedFile(
    data: LanguageModelV4FileData,
    mediaType: String,
    abortSignal: (@Sendable () -> Bool)?,
    cache: GeneratedFileDataCache?
) async throws -> GeneratedFile {
    switch data {
    case .data(let bytes):
        return DefaultGeneratedFileWithType(data: bytes, mediaType: mediaType)
    case .base64(let base64):
        return DefaultGeneratedFileWithType(base64: base64, mediaType: mediaType)
    case .url(let url, _):
        let bytes: Data
        if let cache {
            bytes = try await cache.data(for: url, abortSignal: abortSignal)
        } else {
            bytes = try await download(url: url, isAborted: abortSignal).data
        }
        return DefaultGeneratedFileWithType(data: bytes, mediaType: mediaType)
    }
}

private struct ToolCallNotFoundError: LocalizedError, Sendable {
    let toolCallId: String
    var errorDescription: String? { "Tool call \(toolCallId) not found." }
}

/// A provider-executed tool error payload.
struct ProviderToolExecutionError: LocalizedError, CustomStringConvertible, Sendable {
    let value: JSONValue
    var errorDescription: String? { description }
    var description: String { value.jsonString }
}

/**
 Converts model content and tool outputs of a step to content parts.

 Port of `@ai-sdk/ai/src/generate-text/convert-language-model-content.ts`.
 Order: model content, tool outputs without approval responses, approval
 requests, approval responses, tool outputs of approved calls.
 */
func convertLanguageModelContent(
    content: [LanguageModelV4Content],
    toolCalls: [TypedToolCall],
    toolOutputs: [ToolOutput],
    toolApprovalRequests: [ToolApprovalRequestOutput],
    toolApprovalResponses: [ToolApprovalResponseOutput],
    tools: ToolSet?,
    abortSignal: (@Sendable () -> Bool)?,
    generatedFileDataCache: GeneratedFileDataCache? = nil
) async throws -> [ContentPart] {
    var contentParts: [ContentPart] = []
    let toolCallIdsWithApprovalResponses = Set(toolApprovalResponses.map(\.toolCall.toolCallId))

    func findToolCall(_ toolCallId: String) -> TypedToolCall? {
        toolCalls.first { $0.toolCallId == toolCallId }
    }

    for part in content {
        switch part {
        case .text(let text):
            contentParts.append(.text(
                text: text.text,
                citations: text.citations,
                providerMetadata: text.providerMetadata
            ))

        case .reasoning(let reasoning):
            contentParts.append(.reasoning(ReasoningOutput(
                text: reasoning.text,
                providerMetadata: reasoning.providerMetadata
            )))

        case .custom(let custom):
            contentParts.append(.custom(kind: custom.kind, providerMetadata: custom.providerMetadata))

        case .source(let source):
            contentParts.append(.source(type: "source", source: source))

        case .file(let file):
            contentParts.append(.file(
                file: try await resolveGeneratedFile(
                    data: file.data, mediaType: file.mediaType,
                    abortSignal: abortSignal, cache: generatedFileDataCache
                ),
                providerMetadata: file.providerMetadata
            ))

        case .reasoningFile(let file):
            contentParts.append(.reasoningFile(
                file: try await resolveGeneratedFile(
                    data: file.data, mediaType: file.mediaType,
                    abortSignal: abortSignal, cache: generatedFileDataCache
                ),
                providerMetadata: file.providerMetadata
            ))

        case .toolCall(let toolCallPart):
            guard let toolCall = findToolCall(toolCallPart.toolCallId) else {
                throw ToolCallNotFoundError(toolCallId: toolCallPart.toolCallId)
            }
            contentParts.append(.toolCall(toolCall, providerMetadata: toolCall.providerMetadata))

        case .toolResult(let resultPart):
            let toolCall = findToolCall(resultPart.toolCallId)
            let tool = tools?[resultPart.toolName]

            if toolCall == nil, !(tool?.type == .provider && tool?.supportsDeferredResults == true) {
                throw ToolCallNotFoundError(toolCallId: resultPart.toolCallId)
            }

            // Deferred provider results arrive without their call; upstream leaves input undefined.
            let input = toolCall?.input ?? .null
            let dynamic = toolCall.map(\.isDynamic) ?? (resultPart.dynamic == true)
            let toolMetadata = toolCall != nil ? toolCall?.toolMetadata : tool?.metadata

            if resultPart.isError == true {
                let error = ProviderToolExecutionError(value: resultPart.result)
                let typedError: TypedToolError = dynamic
                    ? .dynamic(DynamicToolError(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName,
                        input: input, error: error, providerExecuted: true,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolMetadata
                    ))
                    : .static(StaticToolError(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName,
                        input: input, error: error, providerExecuted: true,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolMetadata
                    ))
                contentParts.append(.toolError(typedError, providerMetadata: resultPart.providerMetadata))
            } else {
                let typedResult: TypedToolResult = dynamic
                    ? .dynamic(DynamicToolResult(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName,
                        input: input, output: resultPart.result, providerExecuted: true,
                        preliminary: resultPart.preliminary,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolMetadata
                    ))
                    : .static(StaticToolResult(
                        toolCallId: resultPart.toolCallId, toolName: resultPart.toolName,
                        input: input, output: resultPart.result, providerExecuted: true,
                        preliminary: resultPart.preliminary,
                        providerMetadata: resultPart.providerMetadata, toolMetadata: toolMetadata
                    ))
                contentParts.append(.toolResult(typedResult, providerMetadata: resultPart.providerMetadata))
            }

        case .toolApprovalRequest(let request):
            guard let toolCall = findToolCall(request.toolCallId) else {
                throw ToolCallNotFoundForApprovalError(toolCallId: request.toolCallId, approvalId: request.approvalId)
            }
            contentParts.append(.toolApprovalRequest(ToolApprovalRequestOutput(
                approvalId: request.approvalId,
                toolCall: toolCall
            )))
        }
    }

    let outputsWithApprovalResponses = toolOutputs.filter { toolCallIdsWithApprovalResponses.contains($0.toolCallId) }
    let outputsWithoutApprovalResponses = toolOutputs.filter { !toolCallIdsWithApprovalResponses.contains($0.toolCallId) }

    return contentParts
        + outputsWithoutApprovalResponses.map(\.contentPart)
        + toolApprovalRequests.map(ContentPart.toolApprovalRequest)
        + toolApprovalResponses.map(ContentPart.toolApprovalResponse)
        + outputsWithApprovalResponses.map(\.contentPart)
}

extension ToolOutput {
    /// The output as a content part.
    var contentPart: ContentPart {
        switch self {
        case .result(let result):
            return .toolResult(result, providerMetadata: result.providerMetadata)
        case .error(let error):
            return .toolError(error, providerMetadata: error.providerMetadata)
        }
    }

    var input: JSONValue {
        switch self {
        case .result(let result): return result.input
        case .error(let error): return error.input
        }
    }
}
