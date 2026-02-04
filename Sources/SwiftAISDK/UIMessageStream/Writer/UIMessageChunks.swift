import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 UI message stream chunk definitions.

 Port of `@ai-sdk/ai/src/ui-message-stream/ui-message-chunks.ts`.
 */

/// Data chunk emitted within a UI message stream (`type: "data-<name>"`).
public struct DataUIMessageChunk: Sendable, Equatable {
    /// Name of the data channel (derived from the `type` suffix).
    public let name: String

    /// Optional identifier associated with the data payload.
    public let id: String?

    /// Arbitrary payload carried by the data channel.
    public let data: JSONValue

    /// Whether the payload is transient (`true`) or should be persisted (`false`/`nil`).
    public let transient: Bool?

    public init(
        name: String,
        id: String? = nil,
        data: JSONValue,
        transient: Bool? = nil
    ) {
        self.name = name
        self.id = id
        self.data = data
        self.transient = transient
    }

    /// Full type discriminator (`data-<name>`).
    public var typeIdentifier: String {
        "data-\(name)"
    }
}

/// Union of all UI message stream chunks.
public enum UIMessageChunk<MessageMetadata: Sendable & Equatable>: Sendable, Equatable {
    case textStart(id: String, providerMetadata: ProviderMetadata?)
    case textDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case textEnd(id: String, providerMetadata: ProviderMetadata?)

    case reasoningStart(id: String, providerMetadata: ProviderMetadata?)
    case reasoningDelta(id: String, delta: String, providerMetadata: ProviderMetadata?)
    case reasoningEnd(id: String, providerMetadata: ProviderMetadata?)

    case error(errorText: String)

    case toolInputAvailable(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        dynamic: Bool?,
        title: String?
    )

    case toolInputError(
        toolCallId: String,
        toolName: String,
        input: JSONValue,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        dynamic: Bool?,
        errorText: String,
        title: String?
    )

    case toolApprovalRequest(approvalId: String, toolCallId: String)

    case toolOutputAvailable(
        toolCallId: String,
        output: JSONValue,
        providerExecuted: Bool?,
        dynamic: Bool?,
        preliminary: Bool?
    )

    case toolOutputError(
        toolCallId: String,
        errorText: String,
        providerExecuted: Bool?,
        dynamic: Bool?
    )

    case toolOutputDenied(toolCallId: String)

    case toolInputStart(
        toolCallId: String,
        toolName: String,
        providerExecuted: Bool?,
        providerMetadata: ProviderMetadata?,
        dynamic: Bool?,
        title: String?
    )

    case toolInputDelta(toolCallId: String, inputTextDelta: String)

    case sourceUrl(
        sourceId: String,
        url: String,
        title: String?,
        providerMetadata: ProviderMetadata?
    )

    case sourceDocument(
        sourceId: String,
        mediaType: String,
        title: String,
        filename: String?,
        providerMetadata: ProviderMetadata?
    )

    case file(
        url: String,
        mediaType: String,
        providerMetadata: ProviderMetadata?
    )

    case data(DataUIMessageChunk)

    case startStep
    case finishStep

    case start(messageId: String?, messageMetadata: MessageMetadata?)
    case finish(finishReason: FinishReason?, messageMetadata: MessageMetadata?)
    case abort(reason: String?)
    case messageMetadata(MessageMetadata)
}

public extension UIMessageChunk {
    /// Type discriminator string mirroring the upstream literal union.
    var typeIdentifier: String {
        switch self {
        case .textStart: return "text-start"
        case .textDelta: return "text-delta"
        case .textEnd: return "text-end"
        case .reasoningStart: return "reasoning-start"
        case .reasoningDelta: return "reasoning-delta"
        case .reasoningEnd: return "reasoning-end"
        case .error: return "error"
        case .toolInputAvailable: return "tool-input-available"
        case .toolInputError: return "tool-input-error"
        case .toolApprovalRequest: return "tool-approval-request"
        case .toolOutputAvailable: return "tool-output-available"
        case .toolOutputError: return "tool-output-error"
        case .toolOutputDenied: return "tool-output-denied"
        case .toolInputStart: return "tool-input-start"
        case .toolInputDelta: return "tool-input-delta"
        case .sourceUrl: return "source-url"
        case .sourceDocument: return "source-document"
        case .file: return "file"
        case .data(let chunk): return chunk.typeIdentifier
        case .startStep: return "start-step"
        case .finishStep: return "finish-step"
        case .start: return "start"
        case .finish: return "finish"
        case .abort: return "abort"
        case .messageMetadata: return "message-metadata"
        }
    }
}

/// Returns true when the chunk represents a `data-*` payload.
public func isDataUIMessageChunk<MessageMetadata: Sendable>(
    _ chunk: UIMessageChunk<MessageMetadata>
) -> Bool {
    if case .data = chunk {
        return true
    } else {
        return false
    }
}

/// Convenience alias that mirrors the upstream `InferUIMessageChunk`.
public typealias InferUIMessageChunk<Message: UIMessageConvertible> = AnyUIMessageChunk

/// Default chunk type using untyped JSON metadata.
public typealias AnyUIMessageChunk = UIMessageChunk<JSONValue>
