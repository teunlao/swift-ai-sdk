import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Encoding of streamed tool input deltas.
public typealias ToolInputEncoding = LanguageModelV4ToolInputEncoding

/**
 A part of the full stream of `streamText`.

 Port of `TextStreamPart` from `@ai-sdk/ai/src/generate-text/stream-text-result.ts`.
 The JSON coding uses the upstream part shapes (`type` discriminator and field names).
 */
public enum TextStreamPart: Sendable {
    case textStart(id: String, providerMetadata: ProviderMetadata?)
    case textEnd(id: String, providerMetadata: ProviderMetadata?, citations: [Citation]? = nil)
    case textDelta(id: String, text: String, providerMetadata: ProviderMetadata?)

    case reasoningStart(id: String, providerMetadata: ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: ProviderMetadata?)
    case reasoningDelta(id: String, text: String, providerMetadata: ProviderMetadata?)

    case toolInputStart(
        id: String,
        toolName: String,
        providerMetadata: ProviderMetadata?,
        providerExecuted: Bool?,
        dynamic: Bool?,
        title: String?,
        inputEncoding: ToolInputEncoding? = nil,
        toolMetadata: [String: JSONValue]? = nil
    )
    case toolInputEnd(id: String, providerMetadata: ProviderMetadata?)
    case toolInputDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)

    case source(Source)
    case custom(kind: String, providerMetadata: ProviderMetadata?)
    case file(file: GeneratedFile, providerMetadata: ProviderMetadata?)
    case reasoningFile(file: GeneratedFile, providerMetadata: ProviderMetadata?)

    case toolCall(TypedToolCall)
    case toolResult(TypedToolResult)
    case toolError(TypedToolError)
    case toolOutputDenied(ToolOutputDenied)
    case toolApprovalRequest(ToolApprovalRequestOutput)
    case toolApprovalResponse(ToolApprovalResponseOutput)

    case startStep(request: LanguageModelRequestMetadata, warnings: [CallWarning])
    case finishStep(
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        performance: StepResultPerformance,
        finishReason: FinishReason,
        rawFinishReason: String?,
        providerMetadata: ProviderMetadata?
    )

    case start
    case finish(finishReason: FinishReason, rawFinishReason: String?, totalUsage: LanguageModelUsage)
    case abort(reason: String?)
    case error(Error)
    case raw(rawValue: JSONValue)

    /// The upstream `type` discriminator of the part.
    public var type: String {
        switch self {
        case .textStart: return "text-start"
        case .textEnd: return "text-end"
        case .textDelta: return "text-delta"
        case .reasoningStart: return "reasoning-start"
        case .reasoningEnd: return "reasoning-end"
        case .reasoningDelta: return "reasoning-delta"
        case .toolInputStart: return "tool-input-start"
        case .toolInputEnd: return "tool-input-end"
        case .toolInputDelta: return "tool-input-delta"
        case .source: return "source"
        case .custom: return "custom"
        case .file: return "file"
        case .reasoningFile: return "reasoning-file"
        case .toolCall: return "tool-call"
        case .toolResult: return "tool-result"
        case .toolError: return "tool-error"
        case .toolOutputDenied: return "tool-output-denied"
        case .toolApprovalRequest: return "tool-approval-request"
        case .toolApprovalResponse: return "tool-approval-response"
        case .startStep: return "start-step"
        case .finishStep: return "finish-step"
        case .start: return "start"
        case .finish: return "finish"
        case .abort: return "abort"
        case .error: return "error"
        case .raw: return "raw"
        }
    }
}

// MARK: - Equatable

extension TextStreamPart: Equatable {
    /// Compares parts by their JSON encoding; errors compare by message.
    public static func == (lhs: TextStreamPart, rhs: TextStreamPart) -> Bool {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let left = try? encoder.encode(lhs), let right = try? encoder.encode(rhs) else {
            return false
        }
        return left == right
    }
}

// MARK: - Codable

extension TextStreamPart: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, id, providerMetadata, text, delta, citations, kind
        case toolCallId, toolName, title, providerExecuted, dynamic, invalid, input, output, error
        case preliminary, inputEncoding, toolMetadata
        case file, base64, mediaType
        case approvalId, approved, reason, isAutomatic, signature, toolCall
        case request, warnings, response, usage, performance, finishReason, rawFinishReason, totalUsage
        case rawValue
    }

    private static func decodeError(_ value: JSONValue?) -> any Error {
        ProviderToolExecutionError(value: value ?? .null)
    }

    private static func decodeToolCall(from container: KeyedDecodingContainer<CodingKeys>) throws -> TypedToolCall {
        let toolCallId = try container.decode(String.self, forKey: .toolCallId)
        let toolName = try container.decode(String.self, forKey: .toolName)
        let title = try container.decodeIfPresent(String.self, forKey: .title)
        let input = try container.decodeIfPresent(JSONValue.self, forKey: .input) ?? .null
        let providerExecuted = try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
        let providerMetadata = try container.decodeIfPresent(ProviderMetadata.self, forKey: .providerMetadata)
        let toolMetadata = try container.decodeIfPresent([String: JSONValue].self, forKey: .toolMetadata)
        let dynamic = try container.decodeIfPresent(Bool.self, forKey: .dynamic) ?? false
        let invalid = try container.decodeIfPresent(Bool.self, forKey: .invalid)
        let error = try container.decodeIfPresent(JSONValue.self, forKey: .error)

        if dynamic {
            return .dynamic(DynamicToolCall(
                toolCallId: toolCallId, toolName: toolName, title: title, input: input,
                providerExecuted: providerExecuted, providerMetadata: providerMetadata,
                toolMetadata: toolMetadata, invalid: invalid,
                error: error.map { decodeError($0) }
            ))
        }
        return .static(StaticToolCall(
            toolCallId: toolCallId, toolName: toolName, title: title, input: input,
            providerExecuted: providerExecuted, providerMetadata: providerMetadata,
            toolMetadata: toolMetadata
        ))
    }

    private static func encodeToolCall(_ call: TypedToolCall, into container: inout KeyedEncodingContainer<CodingKeys>) throws {
        try container.encode(call.toolCallId, forKey: .toolCallId)
        try container.encode(call.toolName, forKey: .toolName)
        try container.encodeIfPresent(call.title, forKey: .title)
        try container.encode(call.input, forKey: .input)
        try container.encodeIfPresent(call.providerExecuted, forKey: .providerExecuted)
        try container.encodeIfPresent(call.providerMetadata, forKey: .providerMetadata)
        try container.encodeIfPresent(call.toolMetadata, forKey: .toolMetadata)
        if call.isDynamic {
            try container.encode(true, forKey: .dynamic)
        }
        if call.invalid == true {
            try container.encode(true, forKey: .invalid)
        }
        if let error = call.error {
            try container.encode(errorJSON(error), forKey: .error)
        }
    }

    private static func errorJSON(_ error: any Error) -> JSONValue {
        if let providerError = error as? ProviderToolExecutionError {
            return providerError.value
        }
        return .string(AISDKProvider.getErrorMessage(error))
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        func id() throws -> String { try container.decode(String.self, forKey: .id) }
        func metadata() throws -> ProviderMetadata? {
            try container.decodeIfPresent(ProviderMetadata.self, forKey: .providerMetadata)
        }
        func generatedFile() throws -> GeneratedFile {
            let file = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            return DefaultGeneratedFileWithType(
                base64: try file.decode(String.self, forKey: .base64),
                mediaType: try file.decode(String.self, forKey: .mediaType)
            )
        }

        switch type {
        case "text-start":
            self = .textStart(id: try id(), providerMetadata: try metadata())
        case "text-end":
            self = .textEnd(
                id: try id(),
                providerMetadata: try metadata(),
                citations: try container.decodeIfPresent([Citation].self, forKey: .citations)
            )
        case "text-delta":
            self = .textDelta(id: try id(), text: try container.decode(String.self, forKey: .text), providerMetadata: try metadata())
        case "reasoning-start":
            self = .reasoningStart(id: try id(), providerMetadata: try metadata())
        case "reasoning-end":
            self = .reasoningEnd(id: try id(), providerMetadata: try metadata())
        case "reasoning-delta":
            self = .reasoningDelta(id: try id(), text: try container.decode(String.self, forKey: .text), providerMetadata: try metadata())
        case "tool-input-start":
            self = .toolInputStart(
                id: try id(),
                toolName: try container.decode(String.self, forKey: .toolName),
                providerMetadata: try metadata(),
                providerExecuted: try container.decodeIfPresent(Bool.self, forKey: .providerExecuted),
                dynamic: try container.decodeIfPresent(Bool.self, forKey: .dynamic),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                inputEncoding: try container.decodeIfPresent(ToolInputEncoding.self, forKey: .inputEncoding),
                toolMetadata: try container.decodeIfPresent([String: JSONValue].self, forKey: .toolMetadata)
            )
        case "tool-input-end":
            self = .toolInputEnd(id: try id(), providerMetadata: try metadata())
        case "tool-input-delta":
            self = .toolInputDelta(id: try id(), delta: try container.decode(String.self, forKey: .delta), providerMetadata: try metadata())
        case "source":
            self = .source(try Source(from: decoder))
        case "custom":
            self = .custom(kind: try container.decode(String.self, forKey: .kind), providerMetadata: try metadata())
        case "file":
            self = .file(file: try generatedFile(), providerMetadata: try metadata())
        case "reasoning-file":
            self = .reasoningFile(file: try generatedFile(), providerMetadata: try metadata())
        case "tool-call":
            self = .toolCall(try Self.decodeToolCall(from: container))
        case "tool-result":
            let call = try Self.decodeToolCall(from: container)
            let output = try container.decodeIfPresent(JSONValue.self, forKey: .output) ?? .null
            let preliminary = try container.decodeIfPresent(Bool.self, forKey: .preliminary)
            if call.isDynamic {
                self = .toolResult(.dynamic(DynamicToolResult(
                    toolCallId: call.toolCallId, toolName: call.toolName, title: call.title, input: call.input,
                    output: output, providerExecuted: call.providerExecuted, preliminary: preliminary,
                    providerMetadata: call.providerMetadata, toolMetadata: call.toolMetadata
                )))
            } else {
                self = .toolResult(.static(StaticToolResult(
                    toolCallId: call.toolCallId, toolName: call.toolName, title: call.title, input: call.input,
                    output: output, providerExecuted: call.providerExecuted, preliminary: preliminary,
                    providerMetadata: call.providerMetadata, toolMetadata: call.toolMetadata
                )))
            }
        case "tool-error":
            let call = try Self.decodeToolCall(from: container)
            let error = Self.decodeError(try container.decodeIfPresent(JSONValue.self, forKey: .error))
            if call.isDynamic {
                self = .toolError(.dynamic(DynamicToolError(
                    toolCallId: call.toolCallId, toolName: call.toolName, title: call.title, input: call.input,
                    error: error, providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata, toolMetadata: call.toolMetadata
                )))
            } else {
                self = .toolError(.static(StaticToolError(
                    toolCallId: call.toolCallId, toolName: call.toolName, title: call.title, input: call.input,
                    error: error, providerExecuted: call.providerExecuted,
                    providerMetadata: call.providerMetadata, toolMetadata: call.toolMetadata
                )))
            }
        case "tool-output-denied":
            self = .toolOutputDenied(ToolOutputDenied(
                toolCallId: try container.decode(String.self, forKey: .toolCallId),
                toolName: try container.decode(String.self, forKey: .toolName),
                providerExecuted: try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
            ))
        case "tool-approval-request":
            let callContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .toolCall)
            self = .toolApprovalRequest(ToolApprovalRequestOutput(
                approvalId: try container.decode(String.self, forKey: .approvalId),
                toolCall: try Self.decodeToolCall(from: callContainer),
                reason: try container.decodeIfPresent(String.self, forKey: .reason),
                isAutomatic: try container.decodeIfPresent(Bool.self, forKey: .isAutomatic),
                signature: try container.decodeIfPresent(String.self, forKey: .signature)
            ))
        case "tool-approval-response":
            let callContainer = try container.nestedContainer(keyedBy: CodingKeys.self, forKey: .toolCall)
            self = .toolApprovalResponse(ToolApprovalResponseOutput(
                approvalId: try container.decode(String.self, forKey: .approvalId),
                toolCall: try Self.decodeToolCall(from: callContainer),
                approved: try container.decode(Bool.self, forKey: .approved),
                reason: try container.decodeIfPresent(String.self, forKey: .reason),
                providerExecuted: try container.decodeIfPresent(Bool.self, forKey: .providerExecuted)
            ))
        case "start-step":
            self = .startStep(
                request: try container.decode(LanguageModelRequestMetadata.self, forKey: .request),
                warnings: try container.decode([CallWarning].self, forKey: .warnings)
            )
        case "finish-step":
            self = .finishStep(
                response: try container.decode(LanguageModelResponseMetadata.self, forKey: .response),
                usage: try container.decode(LanguageModelUsage.self, forKey: .usage),
                performance: try container.decode(StepResultPerformance.self, forKey: .performance),
                finishReason: try container.decode(FinishReason.self, forKey: .finishReason),
                rawFinishReason: try container.decodeIfPresent(String.self, forKey: .rawFinishReason),
                providerMetadata: try metadata()
            )
        case "start":
            self = .start
        case "finish":
            self = .finish(
                finishReason: try container.decode(FinishReason.self, forKey: .finishReason),
                rawFinishReason: try container.decodeIfPresent(String.self, forKey: .rawFinishReason),
                totalUsage: try container.decode(LanguageModelUsage.self, forKey: .totalUsage)
            )
        case "abort":
            self = .abort(reason: try container.decodeIfPresent(String.self, forKey: .reason))
        case "error":
            self = .error(Self.decodeError(try container.decodeIfPresent(JSONValue.self, forKey: .error)))
        case "raw":
            self = .raw(rawValue: try container.decodeIfPresent(JSONValue.self, forKey: .rawValue) ?? .null)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown TextStreamPart type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)

        func encodeFile(_ file: GeneratedFile) throws {
            var nested = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .file)
            try nested.encode(file.base64, forKey: .base64)
            try nested.encode(file.mediaType, forKey: .mediaType)
        }

        switch self {
        case .textStart(let id, let metadata),
             .reasoningStart(let id, let metadata),
             .reasoningEnd(let id, let metadata),
             .toolInputEnd(let id, let metadata):
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .textEnd(let id, let metadata, let citations):
            try container.encode(id, forKey: .id)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
            try container.encodeIfPresent(citations, forKey: .citations)

        case .textDelta(let id, let text, let metadata),
             .reasoningDelta(let id, let text, let metadata):
            try container.encode(id, forKey: .id)
            try container.encode(text, forKey: .text)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .toolInputStart(let id, let toolName, let metadata, let providerExecuted, let dynamic, let title, let inputEncoding, let toolMetadata):
            try container.encode(id, forKey: .id)
            try container.encode(toolName, forKey: .toolName)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)
            try container.encodeIfPresent(providerExecuted, forKey: .providerExecuted)
            try container.encodeIfPresent(dynamic, forKey: .dynamic)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(inputEncoding, forKey: .inputEncoding)
            try container.encodeIfPresent(toolMetadata, forKey: .toolMetadata)

        case .toolInputDelta(let id, let delta, let metadata):
            try container.encode(id, forKey: .id)
            try container.encode(delta, forKey: .delta)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .source(let source):
            try source.encode(to: encoder)

        case .custom(let kind, let metadata):
            try container.encode(kind, forKey: .kind)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .file(let file, let metadata), .reasoningFile(let file, let metadata):
            try encodeFile(file)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .toolCall(let call):
            try Self.encodeToolCall(call, into: &container)

        case .toolResult(let result):
            try container.encode(result.toolCallId, forKey: .toolCallId)
            try container.encode(result.toolName, forKey: .toolName)
            try container.encodeIfPresent(result.title, forKey: .title)
            try container.encode(result.input, forKey: .input)
            try container.encode(result.output, forKey: .output)
            try container.encodeIfPresent(result.providerExecuted, forKey: .providerExecuted)
            try container.encodeIfPresent(result.preliminary, forKey: .preliminary)
            try container.encodeIfPresent(result.providerMetadata, forKey: .providerMetadata)
            try container.encodeIfPresent(result.toolMetadata, forKey: .toolMetadata)
            if result.isDynamic {
                try container.encode(true, forKey: .dynamic)
            }

        case .toolError(let error):
            try container.encode(error.toolCallId, forKey: .toolCallId)
            try container.encode(error.toolName, forKey: .toolName)
            try container.encodeIfPresent(error.title, forKey: .title)
            try container.encode(error.input, forKey: .input)
            try container.encode(Self.errorJSON(error.error), forKey: .error)
            try container.encodeIfPresent(error.providerExecuted, forKey: .providerExecuted)
            try container.encodeIfPresent(error.providerMetadata, forKey: .providerMetadata)
            try container.encodeIfPresent(error.toolMetadata, forKey: .toolMetadata)
            if error.isDynamic {
                try container.encode(true, forKey: .dynamic)
            }

        case .toolOutputDenied(let denied):
            try container.encode(denied.toolCallId, forKey: .toolCallId)
            try container.encode(denied.toolName, forKey: .toolName)
            try container.encodeIfPresent(denied.providerExecuted, forKey: .providerExecuted)

        case .toolApprovalRequest(let request):
            try container.encode(request.approvalId, forKey: .approvalId)
            var callContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .toolCall)
            try Self.encodeToolCall(request.toolCall, into: &callContainer)
            try container.encodeIfPresent(request.reason, forKey: .reason)
            try container.encodeIfPresent(request.isAutomatic, forKey: .isAutomatic)
            try container.encodeIfPresent(request.signature, forKey: .signature)

        case .toolApprovalResponse(let response):
            try container.encode(response.approvalId, forKey: .approvalId)
            var callContainer = container.nestedContainer(keyedBy: CodingKeys.self, forKey: .toolCall)
            try Self.encodeToolCall(response.toolCall, into: &callContainer)
            try container.encode(response.approved, forKey: .approved)
            try container.encodeIfPresent(response.reason, forKey: .reason)
            try container.encodeIfPresent(response.providerExecuted, forKey: .providerExecuted)

        case .startStep(let request, let warnings):
            try container.encode(request, forKey: .request)
            try container.encode(warnings, forKey: .warnings)

        case .finishStep(let response, let usage, let performance, let finishReason, let rawFinishReason, let metadata):
            try container.encode(response, forKey: .response)
            try container.encode(usage, forKey: .usage)
            try container.encode(performance, forKey: .performance)
            try container.encode(finishReason, forKey: .finishReason)
            try container.encodeIfPresent(rawFinishReason, forKey: .rawFinishReason)
            try container.encodeIfPresent(metadata, forKey: .providerMetadata)

        case .start:
            break

        case .finish(let finishReason, let rawFinishReason, let totalUsage):
            try container.encode(finishReason, forKey: .finishReason)
            try container.encodeIfPresent(rawFinishReason, forKey: .rawFinishReason)
            try container.encode(totalUsage, forKey: .totalUsage)

        case .abort(let reason):
            try container.encodeIfPresent(reason, forKey: .reason)

        case .error(let error):
            try container.encode(Self.errorJSON(error), forKey: .error)

        case .raw(let rawValue):
            try container.encode(rawValue, forKey: .rawValue)
        }
    }
}

// MARK: - CustomStringConvertible

extension TextStreamPart: CustomStringConvertible {
    public var description: String {
        guard let data = try? JSONEncoder().encode(self) else { return type }
        return String(decoding: data, as: UTF8.self)
    }
}
