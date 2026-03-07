import Foundation
import AISDKProvider

/**
 UI message domain types used by streaming utilities and chat APIs.

 Port of `@ai-sdk/ai/src/ui/ui-messages.ts`.

 **Adaptations**:
 - Tool inputs/outputs and data part payloads use `JSONValue` to mirror the dynamic nature
   of the upstream TypeScript definitions. Swift's static generics do not allow the same
   level of inference, so the representation is type-erased while preserving structure.
 - Helper predicates (`isToolUIPart`, `isDynamicToolUIPart`, …) operate on the unified
   `UIMessagePart` enum instead of TypeScript's discriminated unions.
 */
public enum UIMessageRole: String, Sendable, Equatable {
    case system
    case user
    case assistant
}

public protocol UIMessageConvertible: Sendable, Equatable {
    var id: String { get set }
    var role: UIMessageRole { get set }
    var metadata: JSONValue? { get set }
    var parts: [UIMessagePart] { get set }

    func clone() -> Self
    init(id: String, role: UIMessageRole, metadata: JSONValue?, parts: [UIMessagePart])
}

/// Represents a UI message exchanged in the chat UI layer.
public struct UIMessage: UIMessageConvertible {
    public typealias Metadata = JSONValue

    public var id: String
    public var role: UIMessageRole
    public var metadata: JSONValue?
    public var parts: [UIMessagePart]

    public init(
        id: String,
        role: UIMessageRole,
        metadata: JSONValue? = nil,
        parts: [UIMessagePart] = []
    ) {
        self.id = id
        self.role = role
        self.metadata = metadata
        self.parts = parts
    }

    /// Creates a deep copy of the message.
    public func clone() -> UIMessage {
        UIMessage(id: id, role: role, metadata: metadata, parts: parts)
    }
}

// MARK: - Message Parts

public enum UIMessagePart: Sendable, Equatable {
    case text(TextUIPart)
    case reasoning(ReasoningUIPart)
    case tool(UIToolUIPart)
    case dynamicTool(UIDynamicToolUIPart)
    case sourceURL(SourceUrlUIPart)
    case sourceDocument(SourceDocumentUIPart)
    case file(FileUIPart)
    case data(DataUIPart)
    case stepStart

    /// String discriminator mirroring the upstream `type` literal.
    public var typeIdentifier: String {
        switch self {
        case .text: return "text"
        case .reasoning: return "reasoning"
        case .tool(let part): return part.typeIdentifier
        case .dynamicTool: return "dynamic-tool"
        case .sourceURL: return "source-url"
        case .sourceDocument: return "source-document"
        case .file: return "file"
        case .data(let part): return part.typeIdentifier
        case .stepStart: return "step-start"
        }
    }
}

public struct TextUIPart: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case streaming
        case done
    }

    public var text: String
    public var state: State
    public var providerMetadata: ProviderMetadata?

    public init(
        text: String,
        state: State = .streaming,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.text = text
        self.state = state
        self.providerMetadata = providerMetadata
    }
}

public struct ReasoningUIPart: Sendable, Equatable {
    public enum State: String, Sendable, Equatable {
        case streaming
        case done
    }

    public var text: String
    public var state: State
    public var providerMetadata: ProviderMetadata?

    public init(
        text: String,
        state: State = .streaming,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.text = text
        self.state = state
        self.providerMetadata = providerMetadata
    }
}

public struct SourceUrlUIPart: Sendable, Equatable {
    public var sourceId: String
    public var url: String
    public var title: String?
    public var providerMetadata: ProviderMetadata?

    public init(
        sourceId: String,
        url: String,
        title: String? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.sourceId = sourceId
        self.url = url
        self.title = title
        self.providerMetadata = providerMetadata
    }
}

public struct SourceDocumentUIPart: Sendable, Equatable {
    public var sourceId: String
    public var mediaType: String
    public var title: String
    public var filename: String?
    public var providerMetadata: ProviderMetadata?

    public init(
        sourceId: String,
        mediaType: String,
        title: String,
        filename: String? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.sourceId = sourceId
        self.mediaType = mediaType
        self.title = title
        self.filename = filename
        self.providerMetadata = providerMetadata
    }
}

public struct FileUIPart: Sendable, Equatable {
    public var mediaType: String
    public var filename: String?
    public var url: String
    public var providerMetadata: ProviderMetadata?

    public init(
        mediaType: String,
        filename: String? = nil,
        url: String,
        providerMetadata: ProviderMetadata? = nil
    ) {
        self.mediaType = mediaType
        self.filename = filename
        self.url = url
        self.providerMetadata = providerMetadata
    }
}

public struct DataUIPart: Sendable, Equatable {
    public var typeIdentifier: String
    public var id: String?
    public var data: JSONValue

    public init(
        typeIdentifier: String,
        id: String? = nil,
        data: JSONValue
    ) {
        self.typeIdentifier = typeIdentifier
        self.id = id
        self.data = data
    }
}

public struct UIToolApproval: Sendable, Equatable {
    public var id: String
    public var approved: Bool?
    public var reason: String?

    public init(id: String, approved: Bool? = nil, reason: String? = nil) {
        self.id = id
        self.approved = approved
        self.reason = reason
    }
}

public enum UIToolInvocationState: String, Sendable, Equatable {
    case inputStreaming = "input-streaming"
    case inputAvailable = "input-available"
    case approvalRequested = "approval-requested"
    case approvalResponded = "approval-responded"
    case outputAvailable = "output-available"
    case outputError = "output-error"
    case outputDenied = "output-denied"
}

public struct UIToolUIPart: Sendable, Equatable {
    public var toolName: String
    public var toolCallId: String
    public var title: String?
    public var state: UIToolInvocationState
    public var input: JSONValue?
    public var output: JSONValue?
    public var rawInput: JSONValue?
    public var errorText: String?
    public var providerExecuted: Bool?
    public var callProviderMetadata: ProviderMetadata?
    public var resultProviderMetadata: ProviderMetadata?
    public var preliminary: Bool?
    public var approval: UIToolApproval?

    public init(
        toolName: String,
        toolCallId: String,
        state: UIToolInvocationState,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        rawInput: JSONValue? = nil,
        errorText: String? = nil,
        providerExecuted: Bool? = nil,
        callProviderMetadata: ProviderMetadata? = nil,
        resultProviderMetadata: ProviderMetadata? = nil,
        preliminary: Bool? = nil,
        approval: UIToolApproval? = nil,
        title: String? = nil
    ) {
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.title = title
        self.state = state
        self.input = input
        self.output = output
        self.rawInput = rawInput
        self.errorText = errorText
        self.providerExecuted = providerExecuted
        self.callProviderMetadata = callProviderMetadata
        self.resultProviderMetadata = resultProviderMetadata
        self.preliminary = preliminary
        self.approval = approval
    }

    public var typeIdentifier: String {
        "tool-\(toolName)"
    }
}

public enum UIDynamicToolInvocationState: String, Sendable, Equatable {
    case inputStreaming = "input-streaming"
    case inputAvailable = "input-available"
    case approvalRequested = "approval-requested"
    case approvalResponded = "approval-responded"
    case outputAvailable = "output-available"
    case outputError = "output-error"
    case outputDenied = "output-denied"
}

public struct UIDynamicToolUIPart: Sendable, Equatable {
    public var toolName: String
    public var toolCallId: String
    public var title: String?
    public var providerExecuted: Bool?
    public var state: UIDynamicToolInvocationState
    public var input: JSONValue?
    public var output: JSONValue?
    public var errorText: String?
    public var callProviderMetadata: ProviderMetadata?
    public var resultProviderMetadata: ProviderMetadata?
    public var preliminary: Bool?
    public var approval: UIToolApproval?

    public init(
        toolName: String,
        toolCallId: String,
        state: UIDynamicToolInvocationState,
        input: JSONValue? = nil,
        output: JSONValue? = nil,
        errorText: String? = nil,
        providerExecuted: Bool? = nil,
        callProviderMetadata: ProviderMetadata? = nil,
        resultProviderMetadata: ProviderMetadata? = nil,
        preliminary: Bool? = nil,
        approval: UIToolApproval? = nil,
        title: String? = nil
    ) {
        self.toolName = toolName
        self.toolCallId = toolCallId
        self.title = title
        self.providerExecuted = providerExecuted
        self.state = state
        self.input = input
        self.output = output
        self.errorText = errorText
        self.callProviderMetadata = callProviderMetadata
        self.resultProviderMetadata = resultProviderMetadata
        self.preliminary = preliminary
        self.approval = approval
    }
}

// MARK: - Tool helpers

public func isDataUIPart(_ part: UIMessagePart) -> Bool {
    if case .data = part {
        return true
    } else {
        return false
    }
}

public func isTextUIPart(_ part: UIMessagePart) -> Bool {
    if case .text = part {
        return true
    } else {
        return false
    }
}

public func isFileUIPart(_ part: UIMessagePart) -> Bool {
    if case .file = part {
        return true
    } else {
        return false
    }
}

public func isReasoningUIPart(_ part: UIMessagePart) -> Bool {
    if case .reasoning = part {
        return true
    } else {
        return false
    }
}

public func isStaticToolUIPart(_ part: UIMessagePart) -> Bool {
    if case .tool = part {
        return true
    } else {
        return false
    }
}

public func isToolUIPart(_ part: UIMessagePart) -> Bool {
    return isStaticToolUIPart(part) || isDynamicToolUIPart(part)
}

public func isDynamicToolUIPart(_ part: UIMessagePart) -> Bool {
    if case .dynamicTool = part {
        return true
    } else {
        return false
    }
}

public func isToolOrDynamicToolUIPart(_ part: UIMessagePart) -> Bool {
    return isToolUIPart(part)
}

public func getStaticToolName(_ part: UIToolUIPart) -> String {
    part.toolName
}

public func getToolName(_ part: UIToolUIPart) -> String {
    getStaticToolName(part)
}

public func getToolName(_ part: UIDynamicToolUIPart) -> String {
    part.toolName
}

public func getToolName(_ part: UIMessagePart) -> String? {
    switch part {
    case .tool(let toolPart):
        return getStaticToolName(toolPart)
    case .dynamicTool(let dynamicToolPart):
        return getToolName(dynamicToolPart)
    default:
        return nil
    }
}

public func getToolOrDynamicToolName(_ part: UIMessagePart) -> String? {
    getToolName(part)
}

public func lastAssistantMessageIsCompleteWithToolCalls<Message: UIMessageConvertible>(
    messages: [Message]
) -> Bool {
    guard let message = messages.last, message.role == .assistant else {
        return false
    }

    let lastStepToolInvocations = toolInvocationsInLastStep(of: message)
    return !lastStepToolInvocations.isEmpty && lastStepToolInvocations.allSatisfy(isToolInvocationComplete)
}

public func lastAssistantMessageIsCompleteWithApprovalResponses<Message: UIMessageConvertible>(
    messages: [Message]
) -> Bool {
    guard let message = messages.last, message.role == .assistant else {
        return false
    }

    let lastStepToolInvocations = toolInvocationsInLastStep(of: message)
    return lastStepToolInvocations.contains(where: isToolInvocationApprovalResponse)
        && lastStepToolInvocations.allSatisfy(isToolInvocationApprovalComplete)
}

private func toolInvocationsInLastStep<Message: UIMessageConvertible>(of message: Message) -> [UIMessagePart] {
    let lastStepStartIndex = message.parts.lastIndex {
        if case .stepStart = $0 {
            return true
        } else {
            return false
        }
    }

    let startIndex = (lastStepStartIndex ?? -1) + 1

    return message.parts
        .dropFirst(startIndex)
        .compactMap { part in
            switch part {
            case .tool(let toolPart) where toolPart.providerExecuted != true:
                return .tool(toolPart)
            case .dynamicTool(let dynamicToolPart) where dynamicToolPart.providerExecuted != true:
                return .dynamicTool(dynamicToolPart)
            default:
                return nil
            }
        }
}

private func isToolInvocationComplete(_ part: UIMessagePart) -> Bool {
    switch part {
    case .tool(let toolPart):
        return toolPart.state == .outputAvailable || toolPart.state == .outputError
    case .dynamicTool(let dynamicToolPart):
        return dynamicToolPart.state == .outputAvailable || dynamicToolPart.state == .outputError
    default:
        return false
    }
}

private func isToolInvocationApprovalResponse(_ part: UIMessagePart) -> Bool {
    switch part {
    case .tool(let toolPart):
        return toolPart.state == .approvalResponded
    case .dynamicTool(let dynamicToolPart):
        return dynamicToolPart.state == .approvalResponded
    default:
        return false
    }
}

private func isToolInvocationApprovalComplete(_ part: UIMessagePart) -> Bool {
    switch part {
    case .tool(let toolPart):
        return toolPart.state == .outputAvailable
            || toolPart.state == .outputError
            || toolPart.state == .approvalResponded
    case .dynamicTool(let dynamicToolPart):
        return dynamicToolPart.state == .outputAvailable
            || dynamicToolPart.state == .outputError
            || dynamicToolPart.state == .approvalResponded
    default:
        return false
    }
}
